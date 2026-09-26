import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:permission_handler/permission_handler.dart';

import '../core/config/app_config.dart';
import '../core/network/api_exception.dart';
import '../features/consultation/call_clock.dart';
import '../features/consultation/call_recorder.dart';
import '../models/consultation.dart';
import '../services/consultation_service.dart';
import 'session_controller.dart';

/// One running audio consultation: microphone, WebRTC peer, signalling,
/// recording and the billing clock.
///
/// It lives outside AudioCallScreen on purpose. The screen is only a view of
/// it, so leaving the screen (back, the arrow, another tab) leaves the call
/// running — the way a phone call keeps going when you go back to the home
/// screen — and the app-wide "call in progress" bar (ActiveCallBar) brings
/// the screen back. Same in-house handshake as VideoCallScreen — relayed
/// through the backend, direct between the two devices once connected.
///
/// Direction mirrors the booking: the client rings, the lawyer answers.
class AudioCall extends ChangeNotifier {
  AudioCall._(this._service, this.consultationId, {required this.isAdvocate, required bool acceptOnOpen})
      : session = SessionController(_service, consultationId, cancelIfLeftWaiting: !isAdvocate) {
    _recording = CallRecorder(_service, consultationId);
    _clock = CallClockReporter(
      () => _service.callConnected(consultationId),
      () => session.reload(),
    );
    session.addListener(_onSession);
    session.start(acceptFirst: acceptOnOpen);
    // Fetched now, alongside the microphone, rather than after the call has
    // been started — one round trip less between "Accept" and a voice.
    _iceServers = _fetchIceServers();
    unawaited(_prepare());
  }

  /// The call running now, if any — one at a time.
  static final ValueNotifier<AudioCall?> current = ValueNotifier(null);

  /// The running call for [consultationId], or a new one. Opening a
  /// different consultation ends whatever call was running before.
  static AudioCall open(
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
    final call = AudioCall._(service, consultationId, isAdvocate: isAdvocate, acceptOnOpen: acceptOnOpen);
    current.value = call;
    return call;
  }

  final ConsultationService _service;
  final String consultationId;
  final bool isAdvocate;

  /// The consultation itself — status, clock, billing.
  final SessionController session;

  late final CallRecorder _recording;
  late final CallClockReporter _clock;
  late Future<List<Map<String, dynamic>>> _iceServers;
  RTCPeerConnection? _peer;
  MediaStream? _localStream;
  Timer? _signalPoll;

  /// This side's connection, built ahead of the call (see [_prewarm]) so the
  /// network search it starts — STUN, the TURN relay — is done or under way
  /// by the time the call needs it, instead of starting only then. On the
  /// client's side it already holds its offer ([_preOffer]).
  Future<RTCPeerConnection>? _prePeer;
  RTCSessionDescription? _preOffer;

  /// Candidates this side found before the call had an id to send them
  /// under; sent the moment it does.
  final List<String> _queuedCandidates = [];

  /// The lawyer's side, before the client has rung: reads the call itself
  /// (rather than waiting for the next session read) so the ring is answered
  /// the moment it starts.
  Timer? _ringWatch;

  /// A connection that dropped mid-call is put back together automatically,
  /// a few times, before it is left to the buttons.
  static const _maxReconnects = 3;
  int _reconnects = 0;
  bool _reconnecting = false;

  String _callId = '';
  int _since = 0;
  bool _ready = false;
  bool _connecting = false;
  bool _connected = false;
  bool _micOn = true;

  /// Earpiece by default, like a phone call — the loudspeaker is the
  /// lawyer's or client's choice, not something a consultation starts on.
  bool _speakerOn = false;
  String _error = '';

  bool _closed = false;

  /// AudioCallScreens showing this call (a re-opened one can mount before the
  /// one it replaces has gone). While any does, the app-wide bar hides.
  int _screens = 0;

  /// Candidates already sent to the peer, so a re-poll does not resend them.
  final Set<String> _sentCandidates = {};

  /// Whether the other side's offer/answer has been applied.
  bool _remoteSet = false;

  /// ICE candidates that arrived before the remote description.
  final List<String> _pendingIce = [];

  /// One signalling read at a time.
  bool _polling = false;

  /// The call rings / answers itself once, like the web client: the lawyer
  /// already agreed by accepting the booking, so a second tap is friction.
  bool _autoStarted = false;
  bool _autoAnswered = false;

  bool get ready => _ready;
  bool get reconnecting => _reconnecting;
  bool get connecting => _connecting;
  bool get connected => _connected;
  bool get micOn => _micOn;
  bool get speakerOn => _speakerOn;
  String get error => _error;
  bool get onScreen => _screens > 0;

  /// The consultation is running — worth a way back to it from anywhere.
  bool get isLive => session.session?.status.isLive ?? false;

  // ── Screen ───────────────────────────────────────────────────────────────

  void attach() {
    _screens++;
    _notify();
  }

  /// The screen went away. A running consultation carries on without it; one
  /// that is not running (still waiting, or over) has nothing to come back to.
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

  /// [ring] is the call as the ring watch read it — offer and candidates
  /// included — so the answer can be built from it without another read.
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
    final status = await Permission.microphone.request();
    if (_closed) return;
    if (!status.isGranted) {
      _setError('Microphone access is needed for an audio consultation. '
          'Enable it in Settings and reopen this session.');
      return;
    }

    try {
      final stream = await navigator.mediaDevices.getUserMedia({
        'audio': true,
        'video': false,
      });
      if (_closed) {
        await _stopStream(stream);
        return;
      }
      _localStream = stream;
      unawaited(_applySpeaker());
      _ready = true;
      _prewarm();
      _notify();
      final s = session.session;
      if (s != null && s.status.isLive) _autoDrive(s);
    } catch (e) {
      _setError('Could not open the microphone. Close other apps using it and try again.');
    }
  }

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
      // Starts gathering network candidates (and allocating the TURN relay)
      // as soon as the connection exists, not when the handshake begins.
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
        _connected = true;
        _notify();
        // WebRTC re-picks the output when the other side's audio arrives,
        // and on this app's audio-only calls it picks the loudspeaker.
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
        unawaited(_recover(peer));
      }
      if (state == RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
        _reconnects = 0;
        _reconnecting = false;
        // Connected: the handshake is done, so back to the relaxed rate —
        // polling now only notices the other side hanging up.
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
      /* a dropped candidate is survivable — ICE retries */
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

  /// Builds this side's connection before the call: the client's while it
  /// waits for the lawyer to accept (offer and all), the lawyer's while the
  /// client's phone is still ringing it. Everything that can happen before
  /// the other phone answers, happens then.
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
      _setError('Could not start the call. Please try again.');
    }
  }

  /// A connection built for a call that then failed to start.
  void _discard(Future<RTCPeerConnection> peer) {
    peer.then((p) {
      if (!identical(p, _peer)) p.close();
    }).catchError((_) {});
  }

  /// The lawyer answers. With [ring] — the call as read when it started
  /// ringing, the client's offer usually already in it — the answer is built
  /// while the server records the lawyer answering, not after.
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
      unawaited(_readSignals());
    } on ApiException catch (e) {
      if (peerReady != null) _discard(peerReady);
      _connecting = false;
      _setError(e.message);
    } catch (_) {
      if (peerReady != null) _discard(peerReady);
      await hangUp(failed: true);
      _setError('Could not answer the call. Please try again.');
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
      if (!identical(peer, _peer)) return;

      final stale = state.id.isNotEmpty && _callId.isNotEmpty && state.id != _callId;
      if (stale || state.isOver || (state.isIdle && _callId.isNotEmpty)) {
        _signalPoll?.cancel();
        final endingCallId = _callId;
        // Stop the recording before the peer: it is fed by the call's audio
        // path, and closing the peer first leaves an empty file.
        await _recording.stop();
        await _teardownPeer();
        unawaited(_recording.upload(endingCallId));
        _connected = false;
        _connecting = false;
        if (state.endedReason == 'rejected') _error = '';
        _notify();
        return;
      }

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

      if (!isAdvocate && !_remoteSet && state.answer.isNotEmpty) {
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

  /// The connection dropped (network change, a long signal loss). The client
  /// rings again and the lawyer answers again, automatically, while the
  /// consultation is still running — up to [_maxReconnects] times in a row.
  /// Only the client tells the server the old call failed: the lawyer
  /// hanging up too could land after, and end, the client's new call.
  Future<void> _recover(RTCPeerConnection failedPeer) async {
    if (!identical(failedPeer, _peer) || _closed) return;
    if (_reconnects >= _maxReconnects || !isLive) {
      await hangUp(failed: true);
      return;
    }
    _reconnects++;
    _reconnecting = true;
    if (isAdvocate) {
      _signalPoll?.cancel();
      await _teardownPeer();
      _connected = false;
      _connecting = false;
      _autoAnswered = false;
    } else {
      await hangUp(failed: true);
      _autoStarted = false;
    }
    _notify();
    _prewarm();
    await Future<void>.delayed(const Duration(milliseconds: 1200));
    final s = session.session;
    if (!_closed && s != null && s.status.isLive) _autoDrive(s);
  }

  Future<void> hangUp({bool failed = false}) async {
    _signalPoll?.cancel();
    final endingCallId = _callId;
    try {
      await _service.endCall(consultationId, failed: failed);
    } on ApiException {
      /* hanging up locally still has to happen even if the server missed it */
    }
    await _recording.stop();
    await _teardownPeer();
    unawaited(_recording.upload(endingCallId));
    _connected = false;
    _connecting = false;
    _reconnecting = false;
    _notify();
  }

  Future<void> _teardownPeer() async {
    final peer = _peer;
    _peer = null;
    await peer?.close();
    _resetHandshake();
  }

  // ── Controls ─────────────────────────────────────────────────────────────

  /// "Try again" after an error: the microphone if that is what failed,
  /// otherwise the call — rung or answered again, the same as at the start.
  void retry() {
    _error = '';
    _reconnects = 0;
    _notify();
    if (!_ready) {
      unawaited(_prepare());
      return;
    }
    _autoStarted = false;
    _autoAnswered = false;
    final s = session.session;
    if (s != null && s.status.isLive) _autoDrive(s);
  }

  Future<void> _applySpeaker() async {
    try {
      await Helper.setSpeakerphoneOn(_speakerOn);
    } catch (e) {
      debugPrint('AudioCall: could not switch speaker: $e');
    }
  }

  void toggleSpeaker() {
    _speakerOn = !_speakerOn;
    _notify();
    unawaited(_applySpeaker());
  }

  void toggleMic() {
    final tracks = _localStream?.getAudioTracks();
    if (tracks == null || tracks.isEmpty) return;
    _micOn = !_micOn;
    tracks.first.enabled = _micOn;
    _notify();
  }

  void _setError(String message) {
    _error = message;
    _notify();
  }

  /// Async work can land after [close]; a disposed notifier must not fire.
  void _notify() {
    if (!_closed) notifyListeners();
  }

  // ── End ──────────────────────────────────────────────────────────────────

  /// Releases everything: peer, microphone, polling. Leaving a request that
  /// is still waiting also withdraws it (the client's side — see
  /// SessionController.cancelIfLeftWaiting).
  void close() {
    if (_closed) return;
    _closed = true;
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
  }

  Future<void> _stopStream(MediaStream stream) async {
    for (final track in stream.getTracks()) {
      await track.stop();
    }
    await stream.dispose();
  }
}
