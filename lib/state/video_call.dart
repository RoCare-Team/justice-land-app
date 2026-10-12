import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:permission_handler/permission_handler.dart';

import '../core/config/app_config.dart';
import '../core/network/api_exception.dart';
import '../core/platform/ongoing_call.dart';
import '../core/platform/pip.dart';
import '../features/consultation/call_clock.dart';
import '../features/consultation/call_recorder.dart';
import '../models/consultation.dart';
import '../services/consultation_service.dart';
import 'session_controller.dart';

/// One running video consultation: camera, microphone, WebRTC peer,
/// signalling, recording and the billing clock.
///
/// Like [AudioCall] it lives outside its screen. VideoCallScreen is only a
/// view of it, so going back leaves the call running in a small floating
/// window over the rest of the app (VideoCallBubble) — the way WhatsApp lets
/// you keep talking while you use the rest of it — and a tap on the window
/// brings the full screen back. Leaving the app altogether (home) shrinks it
/// into Android's own picture-in-picture window instead (see [Pip]).
///
/// The handshake — offer, answer, ICE candidates — is relayed through the
/// backend, exactly as the web client does it. Once the two peers connect
/// the media flows directly between the devices and never touches the
/// server. Direction mirrors the booking: the client rings, the lawyer
/// answers.
class VideoCall extends ChangeNotifier {
  VideoCall._(this._service, this.consultationId, {required this.isAdvocate, required bool acceptOnOpen})
      : session = SessionController(_service, consultationId, cancelIfLeftWaiting: !isAdvocate) {
    _recording = CallRecorder(_service, consultationId);
    _clock = CallClockReporter(
      () => _service.callConnected(consultationId),
      () => session.reload(),
    );
    session.addListener(_onSession);
    session.start(acceptFirst: acceptOnOpen);
    // Fetched now, alongside the camera, rather than after the call has been
    // started.
    _iceServers = _fetchIceServers();
    unawaited(_prepare());
  }

  /// The video call running now, if any — one at a time.
  static final ValueNotifier<VideoCall?> current = ValueNotifier(null);

  /// The running call for [consultationId], or a new one. Opening a
  /// different consultation ends whatever video call was running before.
  static VideoCall open(
    ConsultationService service,
    String consultationId, {
    required bool isAdvocate,
    bool acceptOnOpen = false,
  }) {
    final running = current.value;
    if (running != null && running.consultationId == consultationId && !running._closed) {
      return running;
    }
    running?.close();
    final call = VideoCall._(service, consultationId, isAdvocate: isAdvocate, acceptOnOpen: acceptOnOpen);
    current.value = call;
    return call;
  }

  final ConsultationService _service;
  final String consultationId;
  final bool isAdvocate;

  /// The consultation itself — status, clock, billing.
  final SessionController session;

  /// What this side's camera sees, and the other person. Shown by the full
  /// screen and by the floating window alike.
  final localRenderer = RTCVideoRenderer();
  final remoteRenderer = RTCVideoRenderer();

  late final CallRecorder _recording;
  late final CallClockReporter _clock;
  late final Future<List<Map<String, dynamic>>> _iceServers;
  RTCPeerConnection? _peer;
  MediaStream? _localStream;
  Timer? _signalPoll;

  /// This side's connection, built ahead of the call (see [_prewarm]) so its
  /// network search — STUN, the TURN relay — is done or under way by the
  /// time the call needs it. On the client's side it already holds its offer.
  Future<RTCPeerConnection>? _prePeer;
  RTCSessionDescription? _preOffer;

  /// Candidates found before the call had an id to send them under.
  final List<String> _queuedCandidates = [];

  /// The lawyer's side before the client has rung: reads the call itself so
  /// the ring is answered the moment it starts.
  Timer? _ringWatch;

  String _callId = '';
  int _since = 0;
  bool _ready = false;
  bool _connecting = false;
  bool _connected = false;
  bool _micOn = true;
  bool _cameraOn = true;

  /// The loudspeaker, on from the start: a video call is held away from the
  /// ear, the way WhatsApp's video calls start on the speaker too. The
  /// button moves it to the earpiece (or back).
  bool _speakerOn = true;

  /// Which camera the local stream is on. Only the front camera is shown
  /// mirrored, the way every camera app does; mirroring the back camera
  /// flips the room — and any document held up to it — the wrong way round.
  bool _frontCamera = true;
  String _error = '';

  bool _closed = false;

  /// VideoCallScreens showing this call (a re-opened one can mount before
  /// the one it replaces has gone). While any does, the floating window hides.
  int _screens = 0;

  /// Like the audio call, the video call rings and answers itself: the
  /// lawyer already agreed by accepting, so a second tap on each side only
  /// adds seconds of "Connecting…".
  bool _autoStarted = false;
  bool _autoAnswered = false;

  /// Candidates already sent to the peer, so a re-poll does not resend them.
  final Set<String> _sentCandidates = {};

  /// Whether the other side's offer/answer has been applied. Tracked here
  /// rather than read back off the peer connection, which on some devices
  /// reports an empty description instead of none.
  bool _remoteSet = false;

  /// ICE candidates that arrived before the remote description — adding them
  /// then fails, and the cursor has already moved past them, so they are held
  /// and applied once the description is in. Losing them is how a call sits
  /// on "Connecting…" for good.
  final List<String> _pendingIce = [];

  /// One signalling read at a time. A 1-second timer does not wait for the
  /// previous read, and two overlapping reads could each apply the offer and
  /// send two different answers.
  bool _polling = false;

  bool get ready => _ready;
  bool get connecting => _connecting;
  bool get connected => _connected;
  bool get micOn => _micOn;
  bool get cameraOn => _cameraOn;
  bool get speakerOn => _speakerOn;
  bool get frontCamera => _frontCamera;
  bool get autoStarted => _autoStarted;
  String get error => _error;
  bool get onScreen => _screens > 0;

  /// The consultation is running — worth a way back to it from anywhere.
  bool get isLive => session.session?.status.isLive ?? false;

  // ── Screen ───────────────────────────────────────────────────────────────

  void attach() {
    _screens++;
    _notify();
  }

  /// The screen went away. A running consultation carries on without it, in
  /// the floating window; one that is not running (still waiting, or over)
  /// has nothing to come back to.
  void detach() {
    if (_screens > 0) _screens--;
    if (onScreen) return;
    if (!isLive) {
      close();
    } else {
      _notify();
    }
  }

  void _onSession() {
    final s = session.session;
    if (s == null || _closed) return;
    // Over while nobody is looking at it: nothing left to return to.
    if (s.status.isOver && !onScreen) {
      close();
      return;
    }
    if (s.status.isLive) _autoDrive(s);
    // Re-publish so views listening to the call see the session's changes.
    _notify();
  }

  void _autoDrive(Consultation s) {
    if (!_ready || _connecting || _connected || _error.isNotEmpty || _closed) return;
    if (!isAdvocate && !_autoStarted) {
      _autoStarted = true;
      unawaited(startCall());
    } else if (isAdvocate && !_autoAnswered) {
      if (s.call?.isRinging ?? false) {
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
    unawaited(answer(accept: true, ring: ring));
  }

  void _watchForRing() {
    if (_ringWatch?.isActive ?? false) return;
    _ringWatch = Timer.periodic(AppConfig.callSignalPollConnecting, (_) async {
      if (_closed || _autoAnswered || _connecting || _connected) {
        _ringWatch?.cancel();
        return;
      }
      try {
        final call = await _service.callState(consultationId);
        if (call.isRinging && !_closed) _answerRing(call);
      } on ApiException {
        /* the next tick asks again */
      }
    });
  }

  // ── Media ────────────────────────────────────────────────────────────────

  Future<void> _prepare() async {
    await localRenderer.initialize();
    await remoteRenderer.initialize();
    if (_closed) return;

    // Camera and microphone must be granted before anything else — asking
    // mid handshake leaves the peer connection half-built.
    final statuses = await [Permission.camera, Permission.microphone].request();
    if (_closed) return;
    if (statuses.values.any((s) => !s.isGranted)) {
      _setError('Camera and microphone access are needed for a video consultation. '
          'Enable them in Settings and reopen this session.');
      return;
    }

    try {
      final stream = await navigator.mediaDevices.getUserMedia({
        'audio': true,
        'video': {
          'facingMode': 'user',
          'width': {'ideal': 1280},
          'height': {'ideal': 720},
        },
      });
      if (_closed) {
        await _stopStream(stream);
        return;
      }
      _localStream = stream;
      localRenderer.srcObject = stream;
      unawaited(_applySpeaker());
      _ready = true;
      _prewarm();
      _notify();
      final s = session.session;
      if (s != null && s.status.isLive) _autoDrive(s);
    } catch (e) {
      _setError('Could not open the camera. Close other apps using it and try again.');
    }
  }

  /// Fetched, not hardcoded: a call between two mobile networks usually needs
  /// the TURN relay, and those credentials rotate.
  Future<List<Map<String, dynamic>>> _fetchIceServers() async {
    try {
      return await _service.iceServers();
    } on ApiException {
      return [
        {'urls': 'stun:stun.l.google.com:19302'},
      ];
    }
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
      if (event.streams.isNotEmpty && !_closed) {
        remoteRenderer.srcObject = event.streams.first;
        _connected = true;
        _notify();
        // WebRTC re-picks the audio output when the other side's audio
        // arrives; put it back where the lawyer or client chose.
        unawaited(_applySpeaker());
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
        unawaited(hangUp(failed: true));
      }
      if (state == RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
        // Handshake done: back to the relaxed rate, which now only notices
        // the other side hanging up.
        _beginPolling(connecting: false);
        if (!_closed) {
          _connected = true;
          _notify();
        }
        unawaited(_applySpeaker());
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
      await _service.signal(
        consultationId,
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

  void _resetHandshake() {
    _since = 0;
    _remoteSet = false;
    _pendingIce.clear();
    _sentCandidates.clear();
    _queuedCandidates.clear();
  }

  Future<void> _flushQueuedCandidates() {
    final queued = List<String>.of(_queuedCandidates);
    _queuedCandidates.clear();
    return Future.wait(queued.map((c) => _pushSignal(candidate: c)));
  }

  /// The client's connection (offer and all) while it waits for the lawyer
  /// to accept; the lawyer's while the client's phone is still ringing it.
  void _prewarm() {
    if (_closed || !_ready || _prePeer != null || _peer != null || _connecting || _connected) return;
    _callId = '';
    _resetHandshake();
    _prePeer = isAdvocate ? _createPeer() : _buildOffer();
    // A failure here is retried when the call is actually started.
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
    return isAdvocate ? _createPeer() : _buildOffer();
  }

  // ── Call ─────────────────────────────────────────────────────────────────

  /// The client starts the call.
  Future<void> startCall() async {
    _connecting = true;
    _error = '';
    _notify();
    // Ringing the other side, and this side's connection (normally built
    // already, offer included, while waiting for the lawyer) — together.
    final started = _service.startCall(consultationId);
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
      _connecting = false;
      _setError(e.message);
    } catch (_) {
      _discard(peerReady);
      await hangUp(failed: true);
      _setError('Could not start the video call. Please try again.');
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
  Future<void> answer({required bool accept, CallState? ring}) async {
    _connecting = true;
    _error = '';
    _notify();
    final answered = _service.answerCall(consultationId, accept: accept);
    answered.then((_) {}, onError: (_) {});
    final peerReady = accept ? _takePrepared() : null;
    try {
      if (!accept) {
        final call = await answered;
        _callId = call.id;
        _connecting = false;
        _notify();
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
      _connecting = false;
      _setError(e.message);
    } catch (_) {
      if (peerReady != null) _discard(peerReady);
      await hangUp(failed: true);
      _setError('Could not answer the video call. Please try again.');
    }
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
      final state = await _service.callState(consultationId, since: _since);
      if (!identical(peer, _peer)) return; // hung up while the read was out

      // A newer call replaced this one, or it was hung up / declined.
      final stale = state.id.isNotEmpty && _callId.isNotEmpty && state.id != _callId;
      if (stale || state.isOver || (state.isIdle && _callId.isNotEmpty)) {
        _signalPoll?.cancel();
        final endingCallId = _callId;
        await _recording.stop();
        await _teardownPeer();
        unawaited(_recording.upload(endingCallId));
        _connected = false;
        _connecting = false;
        if (state.endedReason == 'rejected') _error = '';
        _notify();
        return;
      }

      // The lawyer's side: adopt the client's offer, then answer it.
      if (isAdvocate && !_remoteSet && state.offer.isNotEmpty) {
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
      if (!isAdvocate && !_remoteSet && state.answer.isNotEmpty) {
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
      await _addCandidates(peer, ready);

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

  Future<void> hangUp({bool failed = false}) async {
    _signalPoll?.cancel();
    final endingCallId = _callId;
    try {
      await _service.endCall(consultationId, failed: failed);
    } on ApiException {
      // Hanging up locally still has to happen even if the server missed it.
    }
    await _recording.stop();
    await _teardownPeer();
    unawaited(_recording.upload(endingCallId));
    _connected = false;
    _connecting = false;
    _notify();
  }

  /// Closes the connection but keeps the camera open, so the next call in the
  /// same session can start without asking for it again.
  Future<void> _teardownPeer() async {
    final peer = _peer;
    _peer = null;
    await peer?.close();
    if (!_closed) remoteRenderer.srcObject = null;
    _resetHandshake();
  }

  // ── Controls ─────────────────────────────────────────────────────────────

  /// firstOrNull lives in package:collection, which this project does not
  /// pull in for one call. An empty track list is a real case — a device with
  /// no camera — so it has to be handled rather than assumed away.
  MediaStreamTrack? _firstTrack(List<MediaStreamTrack>? tracks) =>
      (tracks == null || tracks.isEmpty) ? null : tracks.first;

  void toggleMic() {
    final track = _firstTrack(_localStream?.getAudioTracks());
    if (track == null) return;
    _micOn = !_micOn;
    track.enabled = _micOn;
    _notify();
  }

  void toggleCamera() {
    final track = _firstTrack(_localStream?.getVideoTracks());
    if (track == null) return;
    _cameraOn = !_cameraOn;
    track.enabled = _cameraOn;
    _notify();
  }

  Future<void> switchCamera() async {
    final track = _firstTrack(_localStream?.getVideoTracks());
    if (track == null) return;
    await Helper.switchCamera(track);
    _frontCamera = !_frontCamera;
    _notify();
  }

  Future<void> _applySpeaker() async {
    try {
      await Helper.setSpeakerphoneOn(_speakerOn);
    } catch (e) {
      debugPrint('VideoCall: could not switch speaker: $e');
    }
  }

  void toggleSpeaker() {
    _speakerOn = !_speakerOn;
    _notify();
    unawaited(_applySpeaker());
  }

  void _setError(String message) {
    _error = message;
    _notify();
  }

  /// Async work can land after [close]; a disposed notifier must not fire.
  void _notify() {
    if (_closed) return;
    _syncOngoing();
    notifyListeners();
  }

  /// A live call with the camera open keeps running behind the app, and the
  /// home button shrinks it into Android's picture-in-picture window — the
  /// screen may already be gone (see [detach]).
  void _syncOngoing() {
    final on = _ready && isLive;
    if (on == _ongoing) return;
    _ongoing = on;
    unawaited(Pip.setInCall(on));
    unawaited(on ? OngoingCall.start(this, video: true) : OngoingCall.stop(this));
  }

  bool _ongoing = false;

  // ── End ──────────────────────────────────────────────────────────────────

  /// Releases everything: peer, camera, microphone, polling. Leaving a
  /// request that is still waiting also withdraws it (the client's side —
  /// see SessionController.cancelIfLeftWaiting).
  void close() {
    if (_closed) return;
    _closed = true;
    if (_ongoing) {
      _ongoing = false;
      unawaited(Pip.setInCall(false));
      unawaited(OngoingCall.stop(this));
    }
    if (identical(current.value, this)) current.value = null;
    _clock.cancel();
    _signalPoll?.cancel();
    _ringWatch?.cancel();
    session.removeListener(_onSession);
    session.dispose();
    unawaited(_teardown());
    dispose();
  }

  Future<void> _teardown() async {
    final prepared = _prePeer;
    _prePeer = null;
    prepared?.then((p) => p.close(), onError: (_) {});
    await _peer?.close();
    _peer = null;
    await _recording.discard();
    final stream = _localStream;
    _localStream = null;
    if (stream != null) await _stopStream(stream);
    localRenderer.srcObject = null;
    remoteRenderer.srcObject = null;
    await localRenderer.dispose();
    await remoteRenderer.dispose();
  }

  Future<void> _stopStream(MediaStream stream) async {
    for (final track in stream.getTracks()) {
      await track.stop();
    }
    await stream.dispose();
  }
}
