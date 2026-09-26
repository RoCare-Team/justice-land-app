import 'dart:async';

import 'package:android_intent_plus/android_intent.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_callkit_incoming/entities/entities.dart';
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/network/api_client.dart';
import '../routing/app_router.dart';
import 'consultation_service.dart';
import 'dashboard_service.dart';

/// The channel ids server and app agree on — src/lib/push.js sets
/// `android.notification.channelId` to one of these, which is what tells
/// Android to show an arriving push through *that* channel's settings (and
/// sound) rather than falling back to a quiet, unconfigured default one.
///
/// Android fixes a channel's sound the moment it is created, so a new sound
/// means a new id — never re-use one of these with a different sound.

/// An audio or video call request: rings like a phone (res/raw/call_ring).
const _kCallsChannel = AndroidNotificationChannel(
  'consultation_calls',
  'Incoming calls',
  description: 'A client calling you, by audio or video.',
  importance: Importance.max,
  playSound: true,
  sound: RawResourceAndroidNotificationSound('call_ring'),
);

/// Every other request (chat) — a short alert (res/raw/request_alert). Also
/// the manifest's default, for any push that names no channel we know.
const _kRequestsChannel = AndroidNotificationChannel(
  'consultation_requests',
  'Requests',
  description: 'A new chat request, or other news from a client.',
  importance: Importance.max,
  playSound: true,
  sound: RawResourceAndroidNotificationSound('request_alert'),
);

/// The single channel earlier builds created, with the phone's default
/// sound. Removed so it does not linger in the app's notification settings.
const _kLegacyChannelId = 'consultations';

/// A new request, or an incoming call, reaching a lawyer whose app is
/// backgrounded or not running at all — the one thing LawyerController's
/// in-app poll cannot do on its own, because it only runs while the app is
/// alive to run it.
///
/// A chat request is an ordinary notification: tapping it brings the app to
/// the front and the in-app ringing sheet (LawyerShell's `_maybeRing`) takes
/// it from there. An audio or video call rings full-screen instead, over the
/// lock screen, like a phone call (flutter_callkit_incoming) — Accept goes
/// straight into the session, Decline turns the request down.
///
/// Every part of this fails soft. A lawyer's phone that has never heard of
/// Firebase — no google-services.json yet, an SDK the platform refused, a
/// permission declined — is a phone the in-app poll still rings on exactly as
/// it always has; nothing here is on the path a booking or a call depends on.
class PushService {
  PushService(this._dashboard);

  final DashboardService _dashboard;

  /// Told which request a tapped notification was about (null when the push
  /// did not say), so the ringing sheet can open for it — set by
  /// LawyerController.
  void Function(String? consultationId)? onOpened;

  /// Accept / Decline pressed on the full-screen incoming-call screen — set
  /// by LawyerController, which carries them out.
  void Function(String consultationId)? onCallAccepted;
  void Function(String consultationId)? onCallDeclined;

  StreamSubscription<String>? _tokenSub;
  StreamSubscription<RemoteMessage>? _openedSub;
  StreamSubscription<RemoteMessage>? _foregroundSub;
  StreamSubscription<CallEvent?>? _callSub;
  AppLifecycleListener? _lifecycle;
  String? _registeredToken;

  /// Calls this app took down itself. Ending an unanswered call reports back
  /// as a Decline event, and that must not turn the request down.
  final Set<String> _dismissed = {};

  /// Requests permission, registers this device, and wires up what happens
  /// when a lawyer taps a notification. Called once a lawyer is signed in
  /// (see LawyerController) — there is nothing to register for anyone else.
  Future<void> start() async {
    try {
      // First, before anything that waits on the network: when Accept on the
      // call screen is what launched the app, the lawyer is watching a blank
      // app until this runs.
      _callSub?.cancel();
      _callSub = FlutterCallkitIncoming.onEvent.listen(_onCallEvent);
      // Accept pressed while the app was closed: the app is starting because
      // of it, and the event itself fired before anything here listened.
      for (final call in await FlutterCallkitIncoming.activeCalls()) {
        if (call.isAccepted) _accept(call.id, video: call.type == 1);
      }
      // The app opened some other way while a call is still ringing — its
      // icon, the banner body, recents. The in-app ringing sheet takes over
      // (and takes the call screen down), rather than leaving the lawyer on
      // the home screen with a phone that is still ringing.
      _lifecycle?.dispose();
      _lifecycle = AppLifecycleListener(onResume: _takeOverRingingCall);
      unawaited(_takeOverRingingCall());
      await _watchMissedCallTaps();

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
      final android = FlutterLocalNotificationsPlugin()
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
      await android?.createNotificationChannel(_kCallsChannel);
      await android?.createNotificationChannel(_kRequestsChannel);
      await android?.deleteNotificationChannel(_kLegacyChannelId);

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

      // A call push while the app's process counts as foreground — which
      // includes the phone being locked over the app, and the full-screen
      // call UI itself being up. The background handler below never runs
      // for these, so they are handled here.
      _foregroundSub?.cancel();
      _foregroundSub = FirebaseMessaging.onMessage.listen((message) async {
        final data = message.data;
        final id = _consultationIdOf(data);
        if (id == null) return;
        switch (data['type']) {
          case _kIncomingCall:
            if (WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed) {
              // On screen: the in-app ringing sheet, straight away rather
              // than on the next poll.
              onOpened?.call(id);
            } else {
              await FlutterCallkitIncoming.showCallkitIncoming(_callParams(id, data));
            }
          case _kCallCancelled:
            await _showMissedIfRinging(id);
            await dismissCall(id);
        }
      });

      await _askForFullScreenCalls();
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

  /// A tap on the notification — background, or the app just launched by it.
  /// Lands on the lawyer's home and asks for the ringing sheet (Accept /
  /// Decline) to open for that request, rather than leaving the lawyer to
  /// find it in the list.
  void _openFromNotification(RemoteMessage message) {
    AppRouter.instance?.go('/lawyer');
    onOpened?.call(_consultationIdOf(message.data));
  }

  void _onCallEvent(CallEvent? event) {
    switch (event) {
      case CallEventActionCallAccept(:final callKitParams):
        _accept(callKitParams.id, video: callKitParams.type == 1);
      case CallEventActionCallDecline(:final callKitParams):
        if (!_dismissed.remove(callKitParams.id)) onCallDeclined?.call(callKitParams.id);
      default:
        break;
    }
  }

  /// A tap on the missed-call notification opens the Missed requests tab.
  /// MainActivity spots it (the notification carries no action of its own)
  /// and reports it on this channel — held for us when it launched the app.
  Future<void> _watchMissedCallTaps() async {
    if (defaultTargetPlatform != TargetPlatform.android) return;
    try {
      _launch.setMethodCallHandler((call) async {
        if (call.method == 'missedCallTapped') _openMissed();
      });
      if (await _launch.invokeMethod<bool>('takeMissedCallTap') ?? false) _openMissed();
    } catch (e) {
      debugPrint('PushService: missed-call taps: $e');
    }
  }

  void _openMissed() => AppRouter.instance?.go('/lawyer/requests?tab=missed');

  static const _launch = MethodChannel('justiceland/launch');

  Future<void> _takeOverRingingCall() async {
    try {
      for (final call in await FlutterCallkitIncoming.activeCalls()) {
        if (!call.isAccepted && !_answered.contains(call.id)) onOpened?.call(call.id);
      }
    } catch (e) {
      debugPrint('PushService: could not check ringing calls: $e');
    }
  }

  /// Straight into the call: the session screen opens now and sends the
  /// accept itself (`?answer=1`), so there is no stop on the lawyer's home
  /// and no wait on the server before anything shows.
  void _accept(String consultationId, {required bool video}) {
    if (!_answered.add(consultationId)) return;
    final router = AppRouter.instance;
    router?.go('/lawyer');
    router?.push('/consultation/$consultationId/${video ? 'video' : 'audio'}?answer=1');
    onCallAccepted?.call(consultationId);
    // The plugin's ongoing-call notification — the call itself lives in the
    // app from here.
    dismissCall(consultationId);
  }

  /// Accepted calls already opened — the accept event and the cold-start
  /// check can both report the same one.
  final Set<String> _answered = {};

  /// Takes the full-screen call UI (or its ongoing-call notification) down —
  /// the request was answered in the app, or is no longer waiting.
  Future<void> dismissCall(String consultationId) async {
    if (!await _isRinging(consultationId)) return;
    _dismissed.add(consultationId);
    await _endCallUi(consultationId);
  }

  /// Takes down any ringing call whose request is no longer waiting — the
  /// client left, or it was answered elsewhere — even when the server's
  /// `call_cancelled` push never came.
  Future<void> dismissCallsNotWaiting(Set<String> waitingIds) async {
    try {
      for (final call in await FlutterCallkitIncoming.activeCalls()) {
        if (!call.isAccepted && !waitingIds.contains(call.id)) await dismissCall(call.id);
      }
    } catch (e) {
      debugPrint('PushService: could not tidy ringing calls: $e');
    }
  }

  /// Android 14+ shows the incoming-call screen over the lock screen only
  /// with this permission, which a sideloaded app does not get by default.
  /// Asked once — the settings page it opens is not something to repeat on
  /// every sign-in.
  Future<void> _askForFullScreenCalls() async {
    try {
      if (await FlutterCallkitIncoming.canUseFullScreenIntent()) return;
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getBool(_kAskedFullScreen) ?? false) return;
      await prefs.setBool(_kAskedFullScreen, true);
      await FlutterCallkitIncoming.requestFullIntentPermission();
    } catch (e) {
      debugPrint('PushService: full-screen call permission: $e');
    }
  }

  /// Un-registers this device — called on sign-out, so a phone that moves on
  /// to a different lawyer's account stops ringing for the one it left.
  Future<void> stop() async {
    _tokenSub?.cancel();
    _tokenSub = null;
    _openedSub?.cancel();
    _openedSub = null;
    _foregroundSub?.cancel();
    _foregroundSub = null;
    _callSub?.cancel();
    _callSub = null;
    _lifecycle?.dispose();
    _lifecycle = null;
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
/// A request push with a `notification` payload is shown by Android itself.
/// An incoming call arrives data-only instead (see [_kIncomingCall]), and
/// this is where it becomes the full-screen call UI, ringing over the lock
/// screen like a phone call.
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  final data = message.data;
  final id = _consultationIdOf(data);
  if (id == null) return;
  switch (data['type']) {
    case _kIncomingCall:
      // So Decline reaches the server even with the app closed — see
      // [callEventInBackground].
      await FlutterCallkitIncoming.onBackgroundMessage(callEventInBackground);
      await FlutterCallkitIncoming.showCallkitIncoming(_callParams(id, data));
    case _kCallCancelled:
      await _showMissedIfRinging(id);
      await _endCallUi(id);
  }
}

/// The client hung up, or the request ran out, while the lawyer's phone was
/// still ringing: that is a missed call, the same as the call screen timing
/// out on its own (which the plugin already reports). A call the lawyer
/// answered or declined — or saw in the app — is no longer ringing, and
/// gets nothing.
Future<void> _showMissedIfRinging(String id) async {
  try {
    for (final call in await FlutterCallkitIncoming.activeCalls()) {
      if (call.id == id && !call.isAccepted) {
        // Same notification the plugin shows on its own timeout, but saying
        // what it is: under the name, "Missed audio call" rather than the
        // ringing screen's "Audio consultation".
        await FlutterCallkitIncoming.showMissCallNotification(CallKitParams(
          id: call.id,
          nameCaller: call.nameCaller,
          appName: call.appName,
          avatar: call.avatar,
          handle: call.type == 1 ? 'Missed video call' : 'Missed audio call',
          type: call.type,
          extra: call.extra,
          missedCallNotification: call.missedCallNotification,
          android: call.android,
          ios: call.ios,
        ));
        return;
      }
    }
  } catch (e) {
    debugPrint('PushService: could not show missed call: $e');
  }
}

Future<bool> _isRinging(String id) async {
  try {
    return (await FlutterCallkitIncoming.activeCalls()).any((c) => c.id == id);
  } catch (_) {
    return false;
  }
}

/// Ends the call and closes the full-screen call screen. flutter_callkit_incoming
/// (3.1.6) tells that screen to close with a broadcast aimed at the activity's
/// class, which Android never delivers to the receiver the screen registers —
/// so the screen stayed up, silent, until its own timeout. Sending the same
/// action without the class name is what actually reaches it.
Future<void> _endCallUi(String id) async {
  try {
    await FlutterCallkitIncoming.endCall(id);
    if (defaultTargetPlatform == TargetPlatform.android) {
      await const AndroidIntent(
        action: '$_kAppId.com.hiennv.flutter_callkit_incoming.ACTION_ENDED_CALL_INCOMING',
        package: _kAppId,
        arguments: {'ACCEPTED': false},
      ).sendBroadcast();
    }
  } catch (e) {
    debugPrint('PushService: could not end call UI: $e');
  }
}

/// android/app/build.gradle.kts `applicationId`.
const _kAppId = 'com.justiceland.care';

/// Accept pressed on the full-screen call while the app was closed: the
/// accept is sent from main() as soon as the app can make a request, rather
/// than after sign-in is checked and the call screen has opened (which then
/// finds it already accepted and simply shows it).
Future<void> acceptAnsweredCallEarly(ConsultationService service) async {
  try {
    for (final call in await FlutterCallkitIncoming.activeCalls()) {
      if (call.isAccepted) {
        await service.accept(call.id);
      }
    }
  } catch (e) {
    // Accepted already, or no longer waiting — the call screen shows which.
    debugPrint('acceptAnsweredCallEarly: $e');
  }
}

/// Call-screen buttons pressed while no app screen is running — the call was
/// shown from a push with the app closed. Accept starts the app, which takes
/// it from there (PushService.start); Decline does not, so it is sent to the
/// server from here. Without this the request stayed pending, and the client
/// sat on "Waiting for…" until it expired.
@pragma('vm:entry-point')
Future<void> callEventInBackground(CallEvent event) async {
  if (event is! CallEventActionCallDecline) return;
  try {
    final api = await ApiClient.init();
    await ConsultationService(api).reject(event.callKitParams.id);
  } catch (e) {
    // Also lands here for a call this app took down itself (the client had
    // already gone) — there is nothing left to decline.
    debugPrint('callEventInBackground: decline not sent: $e');
  }
}

/// The data-only pushes the server sends for a call (src/lib/push.js):
///
///   { type: 'incoming_call', consultationId, callType: 'audio'|'video',
///     callerName }             — a client is calling; ring full-screen.
///   { type: 'call_cancelled', consultationId }
///                              — they hung up, or it was answered elsewhere.
///
/// Data-only, and at high priority, because a `notification` push is drawn
/// by Android on its own and never reaches the handler above.
const _kIncomingCall = 'incoming_call';
const _kCallCancelled = 'call_cancelled';

const _kAskedFullScreen = 'push.askedFullScreenIntent';

String? _consultationIdOf(Map<String, dynamic> data) =>
    (data['consultationId'] ?? data['consultation_id'] ?? data['sessionId'] ?? data['id'])?.toString();

CallKitParams _callParams(String id, Map<String, dynamic> data) {
  final video = data['callType'] == 'video';
  final name = data['callerName']?.toString().trim() ?? '';
  return CallKitParams(
    id: id,
    nameCaller: name.isEmpty ? 'Client' : name,
    appName: 'Justiceland',
    handle: video ? 'Video consultation' : 'Audio consultation',
    type: video ? 1 : 0,
    // A little over the server's one-minute expiry (expireStaleCallRequests):
    // its call_cancelled normally ends the ring first, with a "Missed audio
    // call" notification. This timeout is the fallback for when nothing
    // reaches the server (the client's phone went away), and shows the
    // plugin's own missed-call notification.
    duration: 70000,
    extra: {'consultationId': id},
    missedCallNotification: const NotificationParams(
      showNotification: true,
      isShowCallback: false,
      subtitle: 'Missed consultation request',
    ),
    // The app's mark in the round avatar, the way the in-app sheet puts the
    // client's initial in a white circle.
    avatar: 'assets/images/call_logo.jpg',
    // In the app's colours, not the plugin's: the navy gradient of the in-app
    // ringing sheet; the button colours and tick/cross icons are Android
    // resources (res/values/callkit_theme.xml, res/drawable-anydpi-v21).
    android: const AndroidParams(
      isCustomNotification: true,
      isShowLogo: false,
      isShowCallID: true,
      isShowFullLockedScreen: true,
      ringtonePath: 'call_ring',
      backgroundColor: '#0B1F3A',
      backgroundUrl: 'assets/images/call_background.png',
      actionColor: '#22C55E',
      textColor: '#FFFFFF',
      incomingCallNotificationChannelName: 'Incoming calls',
      missedCallNotificationChannelName: 'Missed calls',
      textAccept: 'Accept',
      textDecline: 'Decline',
    ),
    ios: const IOSParams(handleType: 'generic', supportsVideo: true),
  );
}
