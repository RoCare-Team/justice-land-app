import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../routing/app_router.dart';
import 'dashboard_service.dart';

/// The channel id server and app agree on — src/lib/push.js sets
/// `android.notification.channelId` to the same string, which is what tells
/// Android to show an arriving push through *this* channel's settings rather
/// than falling back to a quiet, unconfigured default one.
const _kConsultationsChannel = AndroidNotificationChannel(
  'consultations',
  'Consultations',
  description: 'A new request, or an incoming call, from a client.',
  importance: Importance.max,
  playSound: true,
);

/// A new request, or an incoming call, reaching a lawyer whose app is
/// backgrounded or not running at all — the one thing LawyerController's
/// in-app poll cannot do on its own, because it only runs while the app is
/// alive to run it.
///
/// Deliberately a loud, ordinary notification rather than a full-screen
/// incoming-call UI: tapping it brings the app to the front, and the
/// existing in-app ring (LawyerShell's `_maybeRing`) takes it from there —
/// this only closes the gap before that, it does not replace it.
///
/// Every part of this fails soft. A lawyer's phone that has never heard of
/// Firebase — no google-services.json yet, an SDK the platform refused, a
/// permission declined — is a phone the in-app poll still rings on exactly as
/// it always has; nothing here is on the path a booking or a call depends on.
class PushService {
  PushService(this._dashboard);

  final DashboardService _dashboard;

  StreamSubscription<String>? _tokenSub;
  StreamSubscription<RemoteMessage>? _openedSub;
  String? _registeredToken;

  /// Requests permission, registers this device, and wires up what happens
  /// when a lawyer taps a notification. Called once a lawyer is signed in
  /// (see LawyerController) — there is nothing to register for anyone else.
  Future<void> start() async {
    try {
      final messaging = FirebaseMessaging.instance;

      final settings = await messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );
      if (settings.authorizationStatus == AuthorizationStatus.denied) return;

      await FirebaseMessaging.instance
          .setForegroundNotificationPresentationOptions(alert: true, badge: true, sound: true);

      // Created once, before the first push can arrive — a channel Android
      // creates for itself from an incoming notification comes in at default
      // importance, which shows quietly in the tray rather than as a
      // heads-up with sound. `createNotificationChannel` is idempotent, so
      // calling this on every sign-in is fine.
      await FlutterLocalNotificationsPlugin()
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(_kConsultationsChannel);

      final token = await messaging.getToken();
      if (token != null) await _register(token);

      _tokenSub?.cancel();
      _tokenSub = messaging.onTokenRefresh.listen(_register);

      _openedSub?.cancel();
      _openedSub = FirebaseMessaging.onMessageOpenedApp.listen(_openFromNotification);

      // The app was fully closed and a tap on the notification is what
      // launched it — onMessageOpenedApp never fires for that, since there is
      // no running app yet for it to fire into.
      final initial = await messaging.getInitialMessage();
      if (initial != null) _openFromNotification(initial);
    } catch (e, st) {
      // A lawyer without Firebase set up yet — or any other failure here —
      // still has the in-app ring; this is a convenience, not a dependency.
      debugPrint('PushService.start failed (pushes off, app unaffected): $e\n$st');
    }
  }

  Future<void> _register(String token) async {
    if (token == _registeredToken) return;
    try {
      await _dashboard.registerFcmToken(token);
      _registeredToken = token;
    } catch (e) {
      debugPrint('PushService: could not register token: $e');
    }
  }

  /// A tap on the notification — foreground, background, or the app just
  /// launched by it. Every kind of push this sends is about the same place:
  /// the lawyer's own home, where the pending request or the ringing call is
  /// already waiting the moment LawyerController's next poll lands.
  void _openFromNotification(RemoteMessage message) {
    AppRouter.instance?.go('/lawyer');
  }

  /// Un-registers this device — called on sign-out, so a phone that moves on
  /// to a different lawyer's account stops ringing for the one it left.
  Future<void> stop() async {
    _tokenSub?.cancel();
    _tokenSub = null;
    _openedSub?.cancel();
    _openedSub = null;
    final token = _registeredToken;
    _registeredToken = null;
    if (token == null) return;
    try {
      await _dashboard.unregisterFcmToken(token);
    } catch (e) {
      debugPrint('PushService: could not unregister token: $e');
    }
  }
}

/// Initialises Firebase itself — called once, before `runApp`. Absent
/// google-services.json (Firebase not set up on this build yet) this throws,
/// which is caught here: the app starts exactly as it did before pushes
/// existed, and `PushService.start` below simply has nothing to do.
Future<void> initFirebase() async {
  try {
    await Firebase.initializeApp();
  } catch (e, st) {
    debugPrint('Firebase.initializeApp failed (pushes off, app unaffected): $e\n$st');
  }
}

/// The handler Firebase calls in its own isolate when a push arrives while
/// the app is backgrounded or not running. Must be a top-level function (the
/// plugin looks it up by name across the isolate boundary, so a method or a
/// closure cannot be used here) and is `@pragma`-marked so a release build's
/// tree-shaking cannot remove it as apparently-unused.
///
/// It does nothing beyond ensuring Firebase is ready: the notification the
/// server already sent (a plain FCM `notification` payload, not data-only) is
/// what Android actually shows — this handler exists for `data`-only pushes
/// and future background work, neither of which this app sends yet.
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
}
