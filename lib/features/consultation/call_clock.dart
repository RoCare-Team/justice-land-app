import 'dart:async';

import '../../core/network/api_exception.dart';

/// Tells the server the call's audio/video is really flowing, so the paid clock
/// starts then and not when the lawyer tapped Accept — the seconds spent ringing
/// and connecting are not billed, and the timer on screen starts at 00:00 when
/// the call does.
///
/// Both phones report and the server keeps the first, so it does not matter who
/// gets there first. A report that fails is retried a few times: until one lands
/// the timer and cost meter stay at zero on this phone, which is the wrong way to
/// be wrong for a lawyer watching their own meter.
class CallClockReporter {
  CallClockReporter(
    this._send,
    this._afterReported, {
    this.retryDelay = const Duration(seconds: 2),
    this.attempts = 4,
  });

  /// Sends the "connected" report to the server.
  final Future<void> Function() _send;

  /// Re-reads the session, so the screen picks up the new start time now rather
  /// than on the next poll.
  final Future<void> Function() _afterReported;

  final Duration retryDelay;
  final int attempts;

  bool _reported = false;
  bool _cancelled = false;

  /// Reports once per screen; a reconnect after a drop does not need to.
  Future<void> report() async {
    if (_reported) return;
    _reported = true;

    for (var i = 0; i < attempts && !_cancelled; i++) {
      try {
        await _send();
        if (!_cancelled) await _afterReported();
        return;
      } on ApiException {
        if (i < attempts - 1) await Future<void>.delayed(retryDelay);
      }
    }
    // Every try failed: let a later "connected" event try again.
    _reported = false;
  }

  /// The screen is gone — stop retrying.
  void cancel() => _cancelled = true;
}
