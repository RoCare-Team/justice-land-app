import 'dart:async';

import 'package:flutter/foundation.dart';

import '../core/config/app_config.dart';
import '../core/network/api_exception.dart';
import '../models/consultation.dart';
import '../services/consultation_service.dart';

/// Drives one live consultation.
///
/// The web client polls rather than holding a socket, and this does the same —
/// on purpose, not as a shortcut. The poll is how the screen learns the lawyer
/// accepted, declined, or that the session ended.
class SessionController extends ChangeNotifier {
  SessionController(this._service, this.consultationId, {this.cancelIfLeftWaiting = false});

  final ConsultationService _service;
  final String consultationId;

  /// The client's side of a call request: leaving the "Waiting for…" screen
  /// hangs up, the way leaving a ringing call does. Otherwise the request
  /// stays pending on the server and keeps ringing the lawyer for a client
  /// who is gone.
  final bool cancelIfLeftWaiting;

  Consultation? _session;
  Timer? _poll;
  Timer? _tick;
  bool _loading = true;
  bool _sending = false;
  String? _error;
  bool _disposed = false;

  Consultation? get session => _session;
  bool get loading => _loading;
  bool get sending => _sending;
  String? get error => _error;

  /// A second-by-second rebuild for the countdown and the running-cost meter,
  /// separate from the network poll so the clock stays smooth between reads.
  ///
  /// [acceptFirst]: the lawyer already said yes (Accept on the incoming-call
  /// screen or the ringing sheet) and this screen opened at once, before the
  /// server heard it. Accepting returns the session, so it is the first read
  /// too — one round trip to a live call instead of two. The poll starts only
  /// after it, so a read of the still-pending session cannot flash the
  /// accept/decline panel in between.
  void start({bool acceptFirst = false}) {
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_session?.status.isLive ?? false) _safeNotify();
    });
    if (!acceptFirst) {
      _fetch(initial: true);
      _startPolling();
      return;
    }
    accept().then((ok) async {
      // No longer waiting (cancelled, or answered elsewhere): show what it
      // is now rather than an error.
      if (!ok) await _fetch(initial: true);
      _loading = false;
      _safeNotify();
      if (!_disposed) _startPolling();
    });
  }

  /// One read at a time, each scheduled when the last lands: fast while the
  /// consultation is being set up (see AppConfig.sessionPollConnecting),
  /// the usual rate once it runs.
  void _startPolling() {
    _poll?.cancel();
    _poll = Timer(_pollInterval, () async {
      await _fetch();
      if (!_disposed && !(_session?.status.isOver ?? false)) _startPolling();
    });
  }

  Duration get _pollInterval {
    final s = _session;
    final settingUp = s == null || s.status.isWaiting || s.awaitingCallClock;
    if (settingUp) return AppConfig.sessionPollConnecting;
    // A live chat that reports typing wants it to show up promptly.
    if (s.isChat && s.status.isLive && s.supportsTyping) return AppConfig.chatPollTyping;
    return AppConfig.sessionPoll;
  }

  Future<void> _fetch({bool initial = false}) async {
    try {
      final next = await _service.read(consultationId);
      _session = next;
      _error = null;
      // Nothing more will change once it is over — stop hammering the server.
      if (next.status.isOver) _poll?.cancel();
    } on ApiException catch (e) {
      // A blip mid-session should not blank a live conversation; only report
      // when there is nothing on screen to keep.
      debugPrint('SessionController: read failed (${e.statusCode}): ${e.message}');
      if (initial || _session == null) _error = e.message;
    } catch (e, st) {
      // Anything else (a response this app cannot read) used to escape
      // silently and freeze the screen on its last state.
      debugPrint('SessionController: read failed: $e\n$st');
      if (initial || _session == null) _error = 'Something went wrong. Please try again.';
    } finally {
      _loading = false;
      _safeNotify();
    }
  }

  // ── Chat presence ────────────────────────────────────────────────────────

  DateTime? _lastTypingSent;
  DateTime? _readSentUpTo;

  /// Called on every keystroke; tells the server at most every 3 seconds.
  void notifyTyping() {
    final s = _session;
    if (s == null || !s.supportsTyping || !s.status.isLive) return;
    final now = DateTime.now();
    final last = _lastTypingSent;
    if (last != null && now.difference(last) < const Duration(seconds: 3)) return;
    _lastTypingSent = now;
    _service.typing(consultationId).catchError((Object e) {
      debugPrint('SessionController: typing not sent: $e');
    });
  }

  /// The chat is on screen: marks what the other side has written as read,
  /// once per new message.
  void markRead({required bool viewerIsAdvocate}) {
    final s = _session;
    if (s == null || !s.supportsReadReceipts) return;
    DateTime? latest;
    for (final m in s.messages) {
      final theirs = viewerIsAdvocate ? m.fromUser : !m.fromUser;
      final at = m.at;
      if (theirs && at != null && (latest == null || at.isAfter(latest))) latest = at;
    }
    if (latest == null) return;
    final sent = _readSentUpTo;
    if (sent != null && !latest.isAfter(sent)) return;
    _readSentUpTo = latest;
    _service.markRead(consultationId, latest).catchError((Object e) {
      debugPrint('SessionController: read receipt not sent: $e');
      _readSentUpTo = sent;
    });
  }

  /// Manual refresh, for pull-to-refresh and after an action.
  Future<void> reload() => _fetch();

  // ── Actions ──────────────────────────────────────────────────────────────

  Future<bool> sendMessage(String text) async {
    final clean = text.trim();
    if (clean.isEmpty) return false;
    _sending = true;
    _safeNotify();
    try {
      // The server returns the thread with the message appended, so the
      // conversation stays its version rather than a local guess that may not
      // have landed.
      _session = await _service.sendMessage(consultationId, clean);
      _error = null;
      return true;
    } on ApiException catch (e) {
      _error = e.message;
      return false;
    } finally {
      _sending = false;
      _safeNotify();
    }
  }

  Future<bool> accept() => _act(() => _service.accept(consultationId));
  Future<bool> reject() => _act(() => _service.reject(consultationId));
  Future<bool> cancel() => _act(() => _service.cancel(consultationId));

  /// Ends the session. This is where the server bills the minutes used and
  /// records the leftover the client can reclaim free for 24 hours.
  Future<bool> end() => _act(() => _service.end(consultationId));

  Future<bool> _act(Future<Consultation> Function() action) async {
    _sending = true;
    _safeNotify();
    try {
      _session = await action();
      _error = null;
      if (_session?.status.isOver ?? false) _poll?.cancel();
      return true;
    } on ApiException catch (e) {
      debugPrint('SessionController: action failed (${e.statusCode}): ${e.message}');
      _error = e.message;
      return false;
    } catch (e, st) {
      debugPrint('SessionController: action failed: $e\n$st');
      _error = 'Something went wrong. Please try again.';
      return false;
    } finally {
      _sending = false;
      _safeNotify();
    }
  }

  void clearError() {
    if (_error == null) return;
    _error = null;
    _safeNotify();
  }

  void _safeNotify() {
    if (_disposed) return;
    notifyListeners();
  }

  @override
  void dispose() {
    if (cancelIfLeftWaiting && !_sending && (_session?.status.isWaiting ?? false)) {
      _service.cancel(consultationId).catchError((Object e) {
        debugPrint('SessionController: could not cancel on leave: $e');
        return _session!;
      });
    }
    _disposed = true;
    _poll?.cancel();
    _tick?.cancel();
    super.dispose();
  }
}
