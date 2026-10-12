import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Android's ongoing-call foreground service: while a consultation call is
/// live, leaving the app (home, another app, the screen locking) keeps the
/// microphone — and for a video call the camera — running, with a
/// notification that brings the call back. Native side: OngoingCallService,
/// via MainActivity (`justiceland/call`).
class OngoingCall {
  OngoingCall._();

  static const _channel = MethodChannel('justiceland/call');

  /// The call currently holding the service, so a screen tearing down after
  /// another call took over does not stop it.
  static Object? _owner;

  static bool get _supported => defaultTargetPlatform == TargetPlatform.android;

  /// [owner] is the call (or its screen) the service is kept for.
  static Future<void> start(Object owner, {required bool video}) async {
    if (!_supported || identical(_owner, owner)) return;
    _owner = owner;
    try {
      await _channel.invokeMethod<bool>('start', {
        'title': video ? 'Justiceland video consultation' : 'Justiceland audio consultation',
        'video': video,
      });
    } catch (e) {
      debugPrint('OngoingCall.start failed: $e');
    }
  }

  static Future<void> stop(Object owner) async {
    if (!_supported || !identical(_owner, owner)) return;
    _owner = null;
    try {
      await _channel.invokeMethod<void>('stop');
    } catch (e) {
      debugPrint('OngoingCall.stop failed: $e');
    }
  }
}
