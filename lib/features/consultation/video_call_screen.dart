import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:go_router/go_router.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';

import '../../core/config/app_config.dart';
import '../../core/network/api_exception.dart';
import '../../core/platform/pip.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/states.dart';
import '../../models/consultation.dart';
import '../../services/consultation_service.dart';
import '../../state/auth_controller.dart';
import '../../state/session_controller.dart';
import 'call_clock.dart';
import 'call_recorder.dart';
import 'session_shell.dart';

/// A video consultation.
///
/// The handshake — offer, answer, ICE candidates — is relayed through the
/// backend, exactly as the web client does it. Once the two peers connect the
/// media flows directly between the devices and never touches the server.
///
/// Direction mirrors the booking: the client rings, the lawyer answers.
class VideoCallScreen extends StatelessWidget {
  const VideoCallScreen({super.key, required this.consultationId, this.acceptOnOpen = false});

  final String consultationId;

  /// Opened by the lawyer's Accept: the screen sends the accept itself, so it
  /// shows at once instead of after the server answers.
  final bool acceptOnOpen;

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (context) =>
          SessionController(
        context.read<ConsultationService>(),
        consultationId,
        cancelIfLeftWaiting: !context.read<AuthController>().isAdvocate,
      )..start(acceptFirst: acceptOnOpen),
      child: _VideoCallView(consultationId: consultationId),
    );
  }
}

class _VideoCallView extends StatefulWidget {
  const _VideoCallView({required this.consultationId});

  final String consultationId;

  @override
  State<_VideoCallView> createState() => _VideoCallViewState();
}

class _VideoCallViewState extends State<_VideoCallView> {
  final _localRenderer = RTCVideoRenderer();
  final _remoteRenderer = RTCVideoRenderer();
  late final CallRecorder _recording;
  late final CallClockReporter _clock;

  RTCPeerConnection? _peer;
  MediaStream? _localStream;
  Timer? _signalPoll;

  /// Fetched when the screen opens, alongside the camera, rather than after
  /// the call has been started.
  late final Future<List<Map<String, dynamic>>> _iceServers;

  /// Like the audio call, the video call rings and answers itself: the
  /// lawyer already agreed by accepting, so a second tap on each side only
  /// adds seconds of "Connecting…".
  bool _autoStarted = false;
  bool _autoAnswered = false;

  /// The lawyer's side before the client has rung: reads the call itself so
  /// the ring is answered the moment it starts.
  Timer? _ringWatch;

  String _callId = '';
  int _since = 0;
  bool _ready = false;

  /// Leaving the app shrinks the call into a floating window (see [Pip])
  /// only while a call is actually running here.
  bool _pipArmed = false;

  void _armPip(bool armed) {
    if (armed == _pipArmed) return;
    _pipArmed = armed;
    unawaited(Pip.setInCall(armed));
  }

  /// Back (the phone's or the arrow's) on a running call: shrink into the
  /// floating window. Closing this screen would hang the call up, and there
  /// would be no way back to it.
  Future<void> _minimize() async {
    if (await Pip.enter() || !mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('The call is still on. Use the red button to end it.')),
    );
  }
  bool _connecting = false;
  bool _connected = false;
  bool _micOn = true;
  bool _cameraOn = true;

  /// Which camera the local stream is on. Only the front camera is shown
  /// mirrored, the way every camera app does; mirroring the back camera
  /// flips the room — and any document held up to it — the wrong way round.
  bool _frontCamera = true;
  String _error = '';

  /// Candidates already sent to the peer, so a re-poll does not resend them.
  final Set<String> _sentCandidates = {};

  /// Whether the other side's offer/answer has been applied. Tracked here
  /// rather than read back off the peer connection, which on some devices
  /// reports an empty description instead of none.
  bool _remoteSet = false;

  /// ICE candidates that arrived before the remote description — adding them
  /// then fails, and the cursor has already moved past them, so they are held
  /// and applied once the description is in. Losing them is how a call sits on
  /// "Connecting…" for good.
  final List<String> _pendingIce = [];

  /// One signalling read at a time. A 1-second timer does not wait for the
  /// previous read, and two overlapping reads could each apply the offer and
  /// send two different answers.
  bool _polling = false;

  void _resetHandshake() {
    _since = 0;
    _remoteSet = false;
    _pendingIce.clear();
    _sentCandidates.clear();
    _queuedCandidates.clear();
  }

  /// This side's connection, built ahead of the call (see [_prewarm]) so its
  /// network search — STUN, the TURN relay — is done or under way by the
  /// time the call needs it. On the client's side it already holds its offer.
  Future<RTCPeerConnection>? _prePeer;
  RTCSessionDescription? _preOffer;

  /// Candidates found before the call had an id to send them under.
  final List<String> _queuedCandidates = [];

  Future<void> _flushQueuedCandidates() {
    final queued = List<String>.of(_queuedCandidates);
    _queuedCandidates.clear();
    return Future.wait(queued.map((c) => _pushSignal(candidate: c)));
  }

  /// The client's connection (offer and all) while it waits for the lawyer
  /// to accept; the lawyer's while the client's phone is still ringing it.
  void _prewarm() {
    if (!mounted || !_ready || _prePeer != null || _peer != null || _connecting || _connected) return;
    _callId = '';
    _resetHandshake();
    _prePeer = _isAdvocate ? _createPeer() : _buildOffer();
    _prePeer!.then((_) {}, onError: (_) {});
  }

  Future<RTCPeerConnection> _buildOffer() async {
    final peer = await _createPeer();
    final offer = await peer.createOffer();
    await peer.setLocalDescription(offer);
    _preOffer = offer;
    return peer;
  }

  /// The prepared connection, or a fresh one if none was prepared or it
  /// failed to build.
  Future<RTCPeerConnection> _takePrepared() async {
    final prepared = _prePeer;
    _prePeer = null;
    if (prepared != null) {
      try {
        return await prepared;
      } catch (_) {
        /* build it again below */
      }
    }
    _resetHandshake();
    return _isAdvocate ? _createPeer() : _buildOffer();
  }

  /// Applies the client's offer and returns this side's answer, ready to send.
  Future<String> _answerOffer(RTCPeerConnection peer, String offer) async {
    final map = jsonDecode(offer) as Map<String, dynamic>;
    await peer.setRemoteDescription(
      RTCSessionDescription(map['sdp'] as String?, map['type'] as String?),
    );
    _remoteSet = true;
    final answer = await peer.createAnswer();
    await peer.setLocalDescription(answer);
    return jsonEncode(answer.toMap());
  }

  Future<void> _addCandidates(RTCPeerConnection peer, List<String> candidates) async {
    for (final raw in candidates) {
      try {
        final map = jsonDecode(raw) as Map<String, dynamic>;
        await peer.addCandidate(
          RTCIceCandidate(
            map['candidate'] as String?,
            map['sdpMid'] as String?,
            (map['sdpMLineIndex'] as num?)?.toInt(),
          ),
        );
      } catch (_) {
        /* one malformed candidate must not stop the rest arriving */
      }
    }
  }

  @override
  void initState() {
    super.initState();
    _recording = CallRecorder(context.read<ConsultationService>(), widget.consultationId);
    _clock = CallClockReporter(
      () => context.read<ConsultationService>().callConnected(widget.consultationId),
      () => context.read<SessionController>().reload(),
    );
    _iceServers = _fetchIceServers();
    WidgetsBinding.instance.addPostFrameCallback((_) => _prepare());
  }

  @override
  void dispose() {
    if (_pipArmed) unawaited(Pip.setInCall(false));
    _clock.cancel();
    _signalPoll?.cancel();
    _ringWatch?.cancel();
    _teardown();
    _localRenderer.dispose();
    _remoteRenderer.dispose();
    super.dispose();
  }

  Future<void> _prepare() async {
    await _localRenderer.initialize();
    await _remoteRenderer.initialize();

    // Camera and microphone must be granted before anything else — asking mid
    // handshake leaves the peer connection half-built.
    final statuses = await [Permission.camera, Permission.microphone].request();
    final denied = statuses.values.any((s) => !s.isGranted);
    if (denied) {
      if (!mounted) return;
      setState(() => _error =
          'Camera and microphone access are needed for a video consultation. '
          'Enable them in Settings and reopen this session.');
      return;
    }

    try {
      _localStream = await navigator.mediaDevices.getUserMedia({
        'audio': true,
        'video': {
          'facingMode': 'user',
          'width': {'ideal': 1280},
          'height': {'ideal': 720},
        },
      });
      _localRenderer.srcObject = _localStream;
      if (!mounted) return;
      setState(() => _ready = true);
      _prewarm();
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'Could not open the camera. Close other apps using it and try again.');
    }
  }

  /// Fetched, not hardcoded: a call between two mobile networks usually needs
  /// the TURN relay, and those credentials rotate.
  Future<List<Map<String, dynamic>>> _fetchIceServers() async {
    try {
      return await context.read<ConsultationService>().iceServers();
    } on ApiException {
      return [
        {'urls': 'stun:stun.l.google.com:19302'},
      ];
    }
  }

  void _autoDrive(Consultation session, bool isAdvocate) {
    if (!_ready || _connecting || _connected || _error.isNotEmpty) return;
    if (!isAdvocate && !_autoStarted) {
      _autoStarted = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _startCall();
      });
    } else if (isAdvocate && !_autoAnswered) {
      if (session.call?.isRinging ?? false) {
        _answerRing(null);
      } else {
        _watchForRing();
      }
    }
  }

  /// [ring]: the call as the ring watch read it, offer usually included.
  void _answerRing(CallState? ring) {
    if (_autoAnswered) return;
    _autoAnswered = true;
    _ringWatch?.cancel();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _answer(accept: true, ring: ring);
    });
  }

  void _watchForRing() {
    if (_ringWatch?.isActive ?? false) return;
    final service = context.read<ConsultationService>();
    _ringWatch = Timer.periodic(AppConfig.callSignalPollConnecting, (_) async {
      if (!mounted || _autoAnswered || _connecting || _connected) {
        _ringWatch?.cancel();
        return;
      }
      try {
        final call = await service.callState(widget.consultationId);
        if (call.isRinging && mounted) _answerRing(call);
      } on ApiException {
        /* the next tick asks again */
      }
    });
  }

  Future<RTCPeerConnection> _createPeer() async {
    final iceServers = await _iceServers;

    final peer = await createPeerConnection({
      'iceServers': iceServers,
      'sdpSemantics': 'unified-plan',
      // Gathers candidates (and allocates the TURN relay) as soon as the
      // connection exists, not when the handshake begins.
      'iceCandidatePoolSize': 2,
      'bundlePolicy': 'max-bundle',
      'rtcpMuxPolicy': 'require',
    });

    final stream = _localStream;
    if (stream != null) {
      for (final track in stream.getTracks()) {
        await peer.addTrack(track, stream);
      }
    }

    peer.onTrack = (event) {
      if (event.streams.isNotEmpty) {
        _remoteRenderer.srcObject = event.streams.first;
        if (mounted) setState(() => _connected = true);
      }
    };

    peer.onIceCandidate = (candidate) {
      final json = jsonEncode(candidate.toMap());
      if (_sentCandidates.contains(json)) return;
      _sentCandidates.add(json);
      if (_callId.isEmpty) {
        _queuedCandidates.add(json);
      } else {
        _pushSignal(candidate: json);
      }
    };

    peer.onConnectionState = (state) {
      if (state == RTCPeerConnectionState.RTCPeerConnectionStateFailed) {
        _hangUp(failed: true);
      }
      if (state == RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
        // Handshake done: back to the relaxed rate, which now only notices
        // the other side hanging up.
        _beginPolling(connecting: false);
        if (mounted) setState(() => _connected = true);
        unawaited(_recording.start());
        // Billing starts now, not when the request was accepted.
        unawaited(_clock.report());
      }
    };

    return peer;
  }

  Future<void> _pushSignal({String? offer, String? answer, String? candidate}) async {
    if (_callId.isEmpty) return;
    try {
      await context.read<ConsultationService>().signal(
            widget.consultationId,
            callId: _callId,
            offer: offer,
            answer: answer,
            candidate: candidate,
          );
    } on ApiException {
      // A dropped candidate is survivable — ICE retries. A dropped offer is
      // not, but the poll below re-reads state and the UI reports failure.
    }
  }

  /// The client starts the call.
  Future<void> _startCall() async {
    setState(() {
      _connecting = true;
      _error = '';
    });
    // Ringing the other side, and this side's connection (normally built
    // already, offer included, while waiting for the lawyer) — together.
    final started = context.read<ConsultationService>().startCall(widget.consultationId);
    started.then((_) {}, onError: (_) {});
    final peerReady = _takePrepared();
    try {
      final peer = await peerReady;
      final call = await started;
      _callId = call.id;
      _peer = peer;

      await Future.wait([
        _pushSignal(offer: jsonEncode(_preOffer!.toMap())),
        _flushQueuedCandidates(),
      ]);

      _beginPolling();
    } on ApiException catch (e) {
      _discard(peerReady);
      if (!mounted) return;
      setState(() {
        _connecting = false;
        _error = e.message;
      });
    } catch (_) {
      _discard(peerReady);
      await _hangUp(failed: true);
      if (!mounted) return;
      setState(() => _error = 'Could not start the video call. Please try again.');
    }
  }

  /// A connection built for a call that then failed to start.
  void _discard(Future<RTCPeerConnection> peer) {
    peer.then((p) {
      if (!identical(p, _peer)) p.close();
    }).catchError((_) {});
  }

  /// The lawyer answers. With [ring] — the call as read when it started
  /// ringing — the answer is built while the server records the lawyer
  /// answering, not after.
  Future<void> _answer({required bool accept, CallState? ring}) async {
    setState(() {
      _connecting = true;
      _error = '';
    });
    final answered = context.read<ConsultationService>().answerCall(widget.consultationId, accept: accept);
    answered.then((_) {}, onError: (_) {});
    final peerReady = accept ? _takePrepared() : null;
    try {
      if (!accept) {
        final call = await answered;
        _callId = call.id;
        if (mounted) setState(() => _connecting = false);
        return;
      }

      final peer = await peerReady!;
      _peer = peer;
      String? answerSdp;
      if (ring != null && ring.offer.isNotEmpty) {
        answerSdp = await _answerOffer(peer, ring.offer);
        await _addCandidates(peer, ring.candidates);
        _since = ring.cursor;
      }

      final call = await answered;
      _callId = call.id;
      await Future.wait([
        if (answerSdp != null) _pushSignal(answer: answerSdp),
        _flushQueuedCandidates(),
      ]);

      _beginPolling();
      // Read straight away rather than a second from now — the offer is
      // already waiting on the server.
      unawaited(_readSignals());
    } on ApiException catch (e) {
      if (peerReady != null) _discard(peerReady);
      if (!mounted) return;
      setState(() {
        _connecting = false;
        _error = e.message;
      });
    } catch (_) {
      if (peerReady != null) _discard(peerReady);
      await _hangUp(failed: true);
      if (!mounted) return;
      setState(() => _error = 'Could not answer the video call. Please try again.');
    }
  }

  void _beginPolling({bool connecting = true}) {
    _signalPoll?.cancel();
    _signalPoll = Timer.periodic(
      connecting ? AppConfig.callSignalPollConnecting : AppConfig.callSignalPoll,
      (_) => _readSignals(),
    );
  }

  Future<void> _readSignals() async {
    final peer = _peer;
    if (peer == null || _polling) return;
    _polling = true;

    try {
      final state = await context
          .read<ConsultationService>()
          .callState(widget.consultationId, since: _since);
      if (!identical(peer, _peer)) return; // hung up while the read was out

      // A newer call replaced this one, or it was hung up / declined.
      final stale = state.id.isNotEmpty && _callId.isNotEmpty && state.id != _callId;
      if (stale || state.isOver || (state.isIdle && _callId.isNotEmpty)) {
        _signalPoll?.cancel();
        final endingCallId = _callId;
        await _recording.stop();
        await _teardownPeer();
        unawaited(_recording.upload(endingCallId));
        if (mounted) {
          setState(() {
            _connected = false;
            _connecting = false;
            if (state.endedReason == 'rejected') {
              _error = '';
            }
          });
        }
        return;
      }

      // The lawyer's side: adopt the client's offer, then answer it.
      if (_isAdvocate && !_remoteSet && state.offer.isNotEmpty) {
        final map = jsonDecode(state.offer) as Map<String, dynamic>;
        await peer.setRemoteDescription(
          RTCSessionDescription(map['sdp'] as String?, map['type'] as String?),
        );
        _remoteSet = true;
        final answer = await peer.createAnswer();
        await peer.setLocalDescription(answer);
        await _pushSignal(answer: jsonEncode(answer.toMap()));
      }

      // The client's side: adopt the lawyer's answer.
      if (!_isAdvocate && !_remoteSet && state.answer.isNotEmpty) {
        final map = jsonDecode(state.answer) as Map<String, dynamic>;
        await peer.setRemoteDescription(
          RTCSessionDescription(map['sdp'] as String?, map['type'] as String?),
        );
        _remoteSet = true;
      }

      // Candidates can arrive before the description; hold them until then.
      final ready = <String>[];
      if (_remoteSet) {
        ready
          ..addAll(_pendingIce)
          ..addAll(state.candidates);
        _pendingIce.clear();
      } else {
        _pendingIce.addAll(state.candidates);
      }
      for (final raw in ready) {
        try {
          final map = jsonDecode(raw) as Map<String, dynamic>;
          await peer.addCandidate(
            RTCIceCandidate(
              map['candidate'] as String?,
              map['sdpMid'] as String?,
              (map['sdpMLineIndex'] as num?)?.toInt(),
            ),
          );
        } catch (_) {
          // One malformed candidate must not stop the rest arriving.
        }
      }

      // Only now that everything read has been used or held.
      _since = state.cursor;
    } on ApiException {
      // Keep polling; a single failed read is not a dropped call.
    } catch (_) {
      // A description the peer refused. Keep polling rather than throwing out
      // of a timer; if the connection truly fails, onConnectionState ends it.
    } finally {
      _polling = false;
    }
  }

  bool get _isAdvocate => context.read<AuthController>().isAdvocate;

  Future<void> _hangUp({bool failed = false}) async {
    _signalPoll?.cancel();
    final endingCallId = _callId;
    try {
      await context
          .read<ConsultationService>()
          .endCall(widget.consultationId, failed: failed);
    } on ApiException {
      // Hanging up locally still has to happen even if the server missed it.
    }
    await _recording.stop();
    await _teardownPeer();
    unawaited(_recording.upload(endingCallId));
    if (mounted) {
      setState(() {
        _connected = false;
        _connecting = false;
      });
    }
  }

  /// Closes the connection but keeps the camera open, so the next call in the
  /// same session can start without asking for it again.
  Future<void> _teardownPeer() async {
    final peer = _peer;
    _peer = null;
    await peer?.close();
    _remoteRenderer.srcObject = null;
    _resetHandshake();
  }

  Future<void> _teardown() async {
    final prepared = _prePeer;
    _prePeer = null;
    prepared?.then((p) => p.close(), onError: (_) {});
    await _peer?.close();
    _peer = null;
    await _recording.discard();
    final stream = _localStream;
    if (stream != null) {
      for (final track in stream.getTracks()) {
        await track.stop();
      }
      await stream.dispose();
      _localStream = null;
    }
    _localRenderer.srcObject = null;
    _remoteRenderer.srcObject = null;
  }

  /// firstOrNull lives in package:collection, which this project does not
  /// pull in for one call. An empty track list is a real case — a device with
  /// no camera — so it has to be handled rather than assumed away.
  MediaStreamTrack? _firstTrack(List<MediaStreamTrack>? tracks) =>
      (tracks == null || tracks.isEmpty) ? null : tracks.first;

  void _toggleMic() {
    final track = _firstTrack(_localStream?.getAudioTracks());
    if (track == null) return;
    setState(() => _micOn = !_micOn);
    track.enabled = _micOn;
  }

  void _toggleCamera() {
    final track = _firstTrack(_localStream?.getVideoTracks());
    if (track == null) return;
    setState(() => _cameraOn = !_cameraOn);
    track.enabled = _cameraOn;
  }

  Future<void> _switchCamera() async {
    final track = _firstTrack(_localStream?.getVideoTracks());
    if (track == null) return;
    await Helper.switchCamera(track);
    if (mounted) setState(() => _frontCamera = !_frontCamera);
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<SessionController>();
    final auth = context.watch<AuthController>();
    final session = controller.session;
    final isAdvocate = auth.isAdvocate;

    if (controller.loading && session == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Video consultation')),
        body: const LoadingView(label: 'Opening the session…'),
      );
    }

    if (session == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Video consultation')),
        body: ErrorView(
          message: controller.error ?? 'This consultation could not be opened.',
          onRetry: controller.reload,
        ),
      );
    }

    _armPip(session.status.isLive && _ready);

    if (!session.status.isLive) {
      return Scaffold(
        appBar: AppBar(title: const Text('Video consultation')),
        body: Column(
          children: [
            SessionHeader(session: session, viewerIsAdvocate: isAdvocate),
            Expanded(
              child: session.status.isWaiting
                  ? PendingPanel(
                      session: session,
                      viewerIsAdvocate: isAdvocate,
                      busy: controller.sending,
                      onAccept: controller.accept,
                      onReject: controller.reject,
                      onCancel: () async {
                        await controller.cancel();
                        if (context.mounted) context.pop();
                      },
                    )
                  : EndedPanel(session: session, viewerIsAdvocate: isAdvocate),
            ),
          ],
        ),
      );
    }

    _autoDrive(session, isAdvocate);

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _minimize();
      },
      child: ValueListenableBuilder<bool>(
        valueListenable: Pip.active,
        builder: (context, inPip, fullScreen) => inPip ? _pipView() : fullScreen!,
        child: _fullScreen(session, isAdvocate, controller),
      ),
    );
  }

  /// The floating window: just the other person, nothing to tap.
  Widget _pipView() {
    return ColoredBox(
      color: Colors.black,
      child: _connected
          ? RTCVideoView(
              _remoteRenderer,
              objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
            )
          : const Center(
              child: Text('Connecting…', style: TextStyle(color: Colors.white70, fontSize: 12)),
            ),
    );
  }

  Widget _fullScreen(Consultation session, bool isAdvocate, SessionController controller) {
    return Scaffold(
      backgroundColor: AppColors.secondary,
      body: SafeArea(
        child: Stack(
          children: [
            Positioned.fill(child: _stage(session, isAdvocate)),
            Positioned(
              left: 0,
              right: 0,
              top: 0,
              child: _topBar(session, isAdvocate),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: _controls(session, isAdvocate, controller),
            ),
          ],
        ),
      ),
    );
  }

  Widget _stage(Consultation session, bool isAdvocate) {
    if (_error.isNotEmpty) {
      return Container(
        color: AppColors.secondary,
        padding: const EdgeInsets.all(28),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.videocam_off_rounded, size: 46, color: Colors.white54),
              const SizedBox(height: 16),
              Text(
                _error,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white70, height: 1.5),
              ),
            ],
          ),
        ),
      );
    }

    if (!_ready) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: Colors.white),
            SizedBox(height: 16),
            Text('Preparing camera…', style: TextStyle(color: Colors.white70)),
          ],
        ),
      );
    }

    if (!_connected && !_connecting) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Avatar(
                name: isAdvocate ? session.userName : session.advocateName,
                size: 88,
              ),
              const SizedBox(height: 18),
              Text(
                isAdvocate ? session.userName : session.advocateName,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                // Both sides join on their own; nothing to wait on but the line.
                (isAdvocate || _autoStarted) ? 'Connecting…' : 'Ready when you are.',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white60, height: 1.5),
              ),
              const SizedBox(height: 26),
              if (!isAdvocate && !_autoStarted)
                FilledButton.icon(
                  onPressed: _startCall,
                  icon: const Icon(Icons.videocam_rounded),
                  label: const Text('Start video call'),
                )
              else if (session.call?.isRinging ?? false) ...[
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    OutlinedButton.icon(
                      onPressed: () => _answer(accept: false),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white70,
                        side: const BorderSide(color: Colors.white24),
                      ),
                      icon: const Icon(Icons.call_end_rounded, size: 18),
                      label: const Text('Decline'),
                    ),
                    const SizedBox(width: 12),
                    FilledButton.icon(
                      onPressed: () => _answer(accept: true),
                      icon: const Icon(Icons.videocam_rounded),
                      label: const Text('Answer'),
                    ),
                  ],
                ),
              ] else
                const SizedBox(
                  height: 26,
                  width: 26,
                  child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white54),
                ),
            ],
          ),
        ),
      );
    }

    return Stack(
      children: [
        Positioned.fill(
          child: _connected
              ? RTCVideoView(
                  _remoteRenderer,
                  objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                )
              : const Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircularProgressIndicator(color: Colors.white),
                      SizedBox(height: 14),
                      Text('Connecting…', style: TextStyle(color: Colors.white70)),
                    ],
                  ),
                ),
        ),
        Positioned(
          right: 14,
          bottom: 130,
          child: Container(
            height: 168,
            width: 118,
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.white24),
              color: Colors.black54,
            ),
            child: _cameraOn
                ? RTCVideoView(
                    _localRenderer,
                    mirror: _frontCamera,
                    objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                  )
                : const Center(
                    child: Icon(Icons.videocam_off_rounded, color: Colors.white54),
                  ),
          ),
        ),
      ],
    );
  }

  Widget _topBar(Consultation session, bool isAdvocate) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.black.withOpacity(0.65), Colors.transparent],
        ),
      ),
      child: Row(
        children: [
          IconButton(
            onPressed: _minimize,
            icon: const Icon(Icons.keyboard_arrow_down_rounded, color: Colors.white),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isAdvocate ? session.userName : session.advocateName,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  session.awaitingCallClock
                      ? 'Connecting…'
                      : session.isResume
                          ? 'Free resume · ${Fmt.clock(session.elapsed)}'
                          : Fmt.clock(session.elapsed),
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _controls(
    Consultation session,
    bool isAdvocate,
    SessionController controller,
  ) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 26),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [Colors.black.withOpacity(0.75), Colors.transparent],
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _circleButton(
            icon: _micOn ? Icons.mic_rounded : Icons.mic_off_rounded,
            active: _micOn,
            onTap: _toggleMic,
          ),
          _circleButton(
            icon: _cameraOn ? Icons.videocam_rounded : Icons.videocam_off_rounded,
            active: _cameraOn,
            onTap: _toggleCamera,
          ),
          _circleButton(
            icon: Icons.cameraswitch_rounded,
            active: true,
            onTap: _switchCamera,
          ),
          _circleButton(
            icon: Icons.call_end_rounded,
            active: true,
            danger: true,
            onTap: () async {
              await _hangUp();
              if (!context.mounted) return;
              // Hanging up the video does not end the consultation — the
              // session is still live and still billing until someone ends it.
              if (await confirmEndSession(context, session) && context.mounted) {
                await endSessionOrExplain(context, controller);
              }
            },
          ),
        ],
      ),
    );
  }

  Widget _circleButton({
    required IconData icon,
    required bool active,
    required VoidCallback onTap,
    bool danger = false,
  }) {
    return Material(
      color: danger
          ? AppColors.danger
          : active
              ? Colors.white24
              : Colors.white10,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Container(
          height: 58,
          width: 58,
          alignment: Alignment.center,
          child: Icon(icon, color: Colors.white, size: 24),
        ),
      ),
    );
  }
}
