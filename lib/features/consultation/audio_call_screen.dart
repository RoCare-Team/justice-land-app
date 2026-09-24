import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:go_router/go_router.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';

import '../../core/config/app_config.dart';
import '../../core/network/api_exception.dart';
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

/// An audio consultation.
///
/// Same in-house WebRTC handshake as VideoCallScreen — relayed through the
/// backend, direct between the two devices once connected — just without a
/// camera. A voice call over the internet, not a phone call: neither side's
/// real number is ever involved.
///
/// Direction mirrors the booking: the client rings, the lawyer answers.
class AudioCallScreen extends StatelessWidget {
  const AudioCallScreen({super.key, required this.consultationId});

  final String consultationId;

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (context) =>
          SessionController(context.read<ConsultationService>(), consultationId)
            ..start(),
      child: _AudioCallView(consultationId: consultationId),
    );
  }
}

class _AudioCallView extends StatefulWidget {
  const _AudioCallView({required this.consultationId});

  final String consultationId;

  @override
  State<_AudioCallView> createState() => _AudioCallViewState();
}

class _AudioCallViewState extends State<_AudioCallView> {
  RTCPeerConnection? _peer;
  MediaStream? _localStream;
  late final CallRecorder _recording;
  late final CallClockReporter _clock;
  Timer? _signalPoll;

  String _callId = '';
  int _since = 0;
  bool _ready = false;
  bool _connecting = false;
  bool _connected = false;
  bool _micOn = true;
  String _error = '';

  /// Candidates already sent to the peer, so a re-poll does not resend them.
  final Set<String> _sentCandidates = {};

  /// Whether the other side's offer/answer has been applied.
  bool _remoteSet = false;

  /// ICE candidates that arrived before the remote description.
  final List<String> _pendingIce = [];

  /// One signalling read at a time.
  bool _polling = false;

  /// The call rings / answers itself once per screen, like the web client: the
  /// lawyer already agreed by accepting the booking, so a second tap is friction.
  bool _autoStarted = false;
  bool _autoAnswered = false;

  void _autoDrive(Consultation session, bool isAdvocate) {
    if (!_ready || _connecting || _connected || _error.isNotEmpty) return;
    if (!isAdvocate && !_autoStarted) {
      _autoStarted = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _startCall();
      });
    } else if (isAdvocate && !_autoAnswered && (session.call?.isRinging ?? false)) {
      _autoAnswered = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _answer(accept: true);
      });
    }
  }

  void _resetHandshake() {
    _since = 0;
    _remoteSet = false;
    _pendingIce.clear();
    _sentCandidates.clear();
  }

  @override
  void initState() {
    super.initState();
    _recording = CallRecorder(context.read<ConsultationService>(), widget.consultationId);
    _clock = CallClockReporter(
      () => context.read<ConsultationService>().callConnected(widget.consultationId),
      () => context.read<SessionController>().reload(),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) => _prepare());
  }

  @override
  void dispose() {
    _clock.cancel();
    _signalPoll?.cancel();
    _teardown();
    super.dispose();
  }

  Future<void> _prepare() async {
    final status = await Permission.microphone.request();
    if (!status.isGranted) {
      if (!mounted) return;
      setState(() => _error =
          'Microphone access is needed for an audio consultation. '
          'Enable it in Settings and reopen this session.');
      return;
    }

    try {
      _localStream = await navigator.mediaDevices.getUserMedia({
        'audio': true,
        'video': false,
      });
      if (!mounted) return;
      setState(() => _ready = true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'Could not open the microphone. Close other apps using it and try again.');
    }
  }

  Future<RTCPeerConnection> _createPeer() async {
    final service = context.read<ConsultationService>();
    List<Map<String, dynamic>> iceServers;
    try {
      iceServers = await service.iceServers();
    } on ApiException {
      iceServers = [
        {'urls': 'stun:stun.l.google.com:19302'},
      ];
    }

    final peer = await createPeerConnection({
      'iceServers': iceServers,
      'sdpSemantics': 'unified-plan',
    });

    final stream = _localStream;
    if (stream != null) {
      for (final track in stream.getTracks()) {
        await peer.addTrack(track, stream);
      }
    }

    peer.onTrack = (event) {
      if (event.streams.isNotEmpty && mounted) {
        setState(() => _connected = true);
      }
    };

    peer.onIceCandidate = (candidate) {
      final json = jsonEncode(candidate.toMap());
      if (_sentCandidates.contains(json)) return;
      _sentCandidates.add(json);
      _pushSignal(candidate: json);
    };

    peer.onConnectionState = (state) {
      if (state == RTCPeerConnectionState.RTCPeerConnectionStateFailed) {
        _hangUp(failed: true);
      }
      if (state == RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
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
      /* a dropped candidate is survivable — ICE retries */
    }
  }

  /// The client starts the call.
  Future<void> _startCall() async {
    setState(() {
      _connecting = true;
      _error = '';
    });
    _resetHandshake();
    try {
      final service = context.read<ConsultationService>();
      final call = await service.startCall(widget.consultationId);
      _callId = call.id;

      _peer = await _createPeer();
      final offer = await _peer!.createOffer();
      await _peer!.setLocalDescription(offer);
      await _pushSignal(offer: jsonEncode(offer.toMap()));

      _beginPolling();
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _connecting = false;
        _error = e.message;
      });
    } catch (_) {
      await _hangUp(failed: true);
      if (!mounted) return;
      setState(() => _error = 'Could not start the call. Please try again.');
    }
  }

  /// The lawyer answers.
  Future<void> _answer({required bool accept}) async {
    setState(() {
      _connecting = true;
      _error = '';
    });
    _resetHandshake();
    try {
      final service = context.read<ConsultationService>();
      final call = await service.answerCall(widget.consultationId, accept: accept);
      _callId = call.id;

      if (!accept) {
        if (mounted) setState(() => _connecting = false);
        return;
      }

      _peer = await _createPeer();
      _beginPolling();
      unawaited(_readSignals());
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _connecting = false;
        _error = e.message;
      });
    } catch (_) {
      await _hangUp(failed: true);
      if (!mounted) return;
      setState(() => _error = 'Could not answer the call. Please try again.');
    }
  }

  void _beginPolling() {
    _signalPoll?.cancel();
    _signalPoll = Timer.periodic(AppConfig.callSignalPoll, (_) => _readSignals());
  }

  Future<void> _readSignals() async {
    final peer = _peer;
    if (peer == null || _polling) return;
    _polling = true;

    try {
      final state = await context
          .read<ConsultationService>()
          .callState(widget.consultationId, since: _since);
      if (!identical(peer, _peer)) return;

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

      if (!_isAdvocate && !_remoteSet && state.answer.isNotEmpty) {
        final map = jsonDecode(state.answer) as Map<String, dynamic>;
        await peer.setRemoteDescription(
          RTCSessionDescription(map['sdp'] as String?, map['type'] as String?),
        );
        _remoteSet = true;
      }

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
          /* one malformed candidate must not stop the rest arriving */
        }
      }

      _since = state.cursor;
    } on ApiException {
      /* keep polling; a single failed read is not a dropped call */
    } catch (_) {
      /* a description the peer refused — keep polling rather than throwing */
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
      /* hanging up locally still has to happen even if the server missed it */
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

  Future<void> _teardownPeer() async {
    final peer = _peer;
    _peer = null;
    await peer?.close();
    _resetHandshake();
  }

  Future<void> _teardown() async {
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
  }

  MediaStreamTrack? _firstTrack(List<MediaStreamTrack>? tracks) =>
      (tracks == null || tracks.isEmpty) ? null : tracks.first;

  void _toggleMic() {
    final track = _firstTrack(_localStream?.getAudioTracks());
    if (track == null) return;
    setState(() => _micOn = !_micOn);
    track.enabled = _micOn;
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<SessionController>();
    final auth = context.watch<AuthController>();
    final session = controller.session;
    final isAdvocate = auth.isAdvocate;

    if (controller.loading && session == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Audio consultation')),
        body: const LoadingView(label: 'Opening the session…'),
      );
    }

    if (session == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Audio consultation')),
        body: ErrorView(
          message: controller.error ?? 'This consultation could not be opened.',
          onRetry: controller.reload,
        ),
      );
    }

    if (!session.status.isLive) {
      return Scaffold(
        appBar: AppBar(title: const Text('Audio consultation')),
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
              const Icon(Icons.mic_off_rounded, size: 46, color: Colors.white54),
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
            Text('Preparing microphone…', style: TextStyle(color: Colors.white70)),
          ],
        ),
      );
    }

    final otherName = isAdvocate ? session.userName : session.advocateName;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Stack(
              alignment: Alignment.center,
              children: [
                if (_connecting && !_connected)
                  SizedBox(
                    height: 116,
                    width: 116,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.4,
                      color: Colors.white.withValues(alpha: 0.35),
                    ),
                  ),
                Avatar(name: otherName, size: 96),
              ],
            ),
            const SizedBox(height: 18),
            Text(
              otherName,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _connected
                  ? 'On call'
                  : isAdvocate
                      ? (session.call?.isRinging ?? false)
                          ? 'is calling you.'
                          : 'Waiting for the client to start the call.'
                      : _connecting
                          ? 'Connecting…'
                          : 'Ready when you are.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white60, height: 1.5),
            ),
            const SizedBox(height: 26),
            if (!isAdvocate && !_connecting && !_connected)
              FilledButton.icon(
                onPressed: _startCall,
                icon: const Icon(Icons.call_rounded),
                label: const Text('Start audio call'),
              )
            else if (isAdvocate && (session.call?.isRinging ?? false) && !_connecting) ...[
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
                    icon: const Icon(Icons.call_rounded),
                    label: const Text('Answer'),
                  ),
                ],
              ),
            ] else if (_connecting && !_connected)
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

  Widget _topBar(Consultation session, bool isAdvocate) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.black.withValues(alpha: 0.65), Colors.transparent],
        ),
      ),
      child: Row(
        children: [
          IconButton(
            onPressed: () => context.pop(),
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
                          : '${Fmt.clock(session.elapsed)} · ${Fmt.amount(session.runningCost)} so far',
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
          colors: [Colors.black.withValues(alpha: 0.75), Colors.transparent],
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
            icon: Icons.call_end_rounded,
            active: true,
            danger: true,
            onTap: () async {
              await _hangUp();
              if (!context.mounted) return;
              // Hanging up the call does not end the consultation — the
              // session is still live and still billing until someone ends it.
              if (await confirmEndSession(context, session)) {
                await controller.end();
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
