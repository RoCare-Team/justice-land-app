import 'dart:async';

import 'package:flutter/foundation.dart';

import '../core/config/app_config.dart';
import '../core/network/api_exception.dart';
import '../models/consultation.dart';
import '../services/consultation_service.dart';

/// Drives one live consultation.
///
/// The web client polls rather than holding a socket, and this does the same —
/// on purpose, not as a shortcut. The poll is what settles a phone call: the
/// server asks the telephony provider on each tick whether the lawyer picked
/// up or hung up, and moves the session to match. Stop polling and an audio
/// consultation never starts and never ends.
class SessionController extends ChangeNotifier {
  SessionController(this._service, this.consultationId);

  final ConsultationService _service;
  final String consultationId;

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
  void start() {
    _fetch(initial: true);
    _poll = Timer.periodic(AppConfig.sessionPoll, (_) => _fetch());
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_session?.status.isLive ?? false) _safeNotify();
    });
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
      if (initial || _session == null) _error = e.message;
    } finally {
      _loading = false;
      _safeNotify();
    }
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
      _error = e.message;
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
    _disposed = true;
    _poll?.cancel();
    _tick?.cancel();
    super.dispose();
  }
}
