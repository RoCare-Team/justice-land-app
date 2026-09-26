import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Android picture-in-picture for a live video call: the app shrinks into a
/// small floating window instead of closing the call screen, the way WhatsApp
/// does. Native side: MainActivity (`justiceland/pip`).
class Pip {
  Pip._();

  static const _channel = MethodChannel('justiceland/pip');

  /// Whether the app is showing as the floating window right now — the call
  /// screen swaps to a video-only layout while it is.
  static final ValueNotifier<bool> active = ValueNotifier(false);

  static bool _listening = false;

  static bool get _supported => defaultTargetPlatform == TargetPlatform.android;

  static void _listen() {
    if (_listening) return;
    _listening = true;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'changed') active.value = call.arguments == true;
    });
  }

  /// Shrinks the app into the floating window. False where the phone cannot
  /// (below Android 8, or PiP switched off for the app in settings).
  static Future<bool> enter() async {
    if (!_supported) return false;
    _listen();
    try {
      return await _channel.invokeMethod<bool>('enter') ?? false;
    } catch (e) {
      debugPrint('Pip.enter failed: $e');
      return false;
    }
  }

  /// A call is (or is no longer) on screen: while it is, leaving the app with
  /// the home button also goes to the floating window.
  static Future<void> setInCall(bool inCall) async {
    if (!_supported) return;
    _listen();
    try {
      await _channel.invokeMethod<void>('setInCall', inCall);
    } catch (e) {
      debugPrint('Pip.setInCall failed: $e');
    }
  }
}
