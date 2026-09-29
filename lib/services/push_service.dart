import 'dart:async';
import 'dart:convert';

import 'package:android_intent_plus/android_intent.dart';
import 'package:dio/dio.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_callkit_incoming/entities/entities.dart';
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/network/api_client.dart';
import '../routing/app_router.dart';
import '../state/auth_controller.dart';
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

/// Everything else the server sends a signed-in person: consultation
/// updates, chat messages, wallet and account news. The phone's own sound.
/// Also the manifest's default, for a push naming a channel not created yet.
const _kGeneralChannel = AndroidNotificationChannel(
  'general',
  'Updates',
  description: 'Your consultations, messages, wallet and account.',
  importance: Importance.high,
);

/// Offers, festival greetings and new articles — its own channel so it can be
/// muted without silencing calls, requests or updates.
const _kOffersChannel = AndroidNotificationChannel(
  'offers',
  'Offers & festivals',
  description: 'Offers, festival greetings and new articles from Justiceland.',
  importance: Importance.defaultImportance,
);

/// The single channel earlier builds created, with the phone's default
/// sound. Removed so it does not linger in the app's notification settings.
const _kLegacyChannelId = 'consultations';

/// The only screens a push may open — the same list the server checks before
/// sending (src/lib/notifications.js). Anything else opens Home, so a typo in
/// an admin send can never crash the app or open a blank screen.
final _kAllowedRoutes = <RegExp>[
  RegExp(r'^/$'),
  RegExp(r'^/lawyers$'), RegExp(r'^/lawyers/[^/?#\s]+$'),
  RegExp(r'^/services$'), RegExp(r'^/services/all$'), RegExp(r'^/services/[^/?#\s]+$'),
  RegExp(r'^/consultations$'), RegExp(r'^/consultation/[^/?#\s]+/chat$'),
  RegExp(r'^/orders$'), RegExp(r'^/wallet$'), RegExp(r'^/saved$'), RegExp(r'^/profile$'),
  RegExp(r'^/blogs$'), RegExp(r'^/blogs/[^/?#\s]+$'),
  RegExp(r'^/lawyer$'), RegExp(r'^/lawyer/requests(\?tab=missed)?$'),
  RegExp(r'^/lawyer/(consultations|queries|earnings|plan|profile)$'),
];

/// The screen a tap on this push opens: the route it carries when that is an
/// allowed one, otherwise its type's default (the server's defaults too).
String pushRoute(Map<String, dynamic> data) {
  final route = data['route']?.toString() ?? '';
  if (route.isNotEmpty && _kAllowedRoutes.any((rx) => rx.hasMatch(route))) return route;
  final id = _consultationIdOf(data);
  switch (data['type']) {
    case 'consultation_update':
    case 'chat_message':
      return id != null ? '/consultation/$id/chat' : '/consultations';
    case 'consultation_request':
    case 'new_request':
      return '/lawyer';
    case 'order_update':
      return '/orders';
    case 'wallet':
      return '/wallet';
    case 'lawyer_account':
      switch (data['reason']) {
        case 'plan_expiring':
          return '/lawyer/plan';
        case 'payout':
          return '/lawyer/earnings';
        default:
          return '/lawyer/profile';
      }
    case 'offer':
      return '/services/all';
    case 'blog':
      final slug = data['slug']?.toString() ?? '';
      return slug.isNotEmpty ? '/blogs/$slug' : '/blogs';
    default:
      return '/';
  }
}

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

  final FlutterLocalNotificationsPlugin _local = FlutterLocalNotificationsPlugin();
  AuthController? _auth;
  bool _attached = false;

  /// 'client' or 'lawyer' while this device is registered for someone; null
  /// when signed out.
  String? _role;

  /// A tap that arrived before the app could navigate (cold start, session
  /// still being read) — opened as soon as it can.
  String? _pendingRoute;
  VoidCallback? _pendingThen;

  // ── Everyone: set up once at launch ──────────────────────────────────────

  /// Everything pushes need for every user, signed in or not. Called once
  /// from the app shell after the first frame.
  ///
  ///  - the Updates and Offers channels, and the tray while the app is open;
  ///  - the `all` topic (and `test` on debug builds), so offers and festival
  ///    greetings reach people who have not signed in;
  ///  - one tap handler for every push, whichever state the app was in;
  ///  - following sign-in and sign-out: this device is registered with the
  ///    server for whoever is signed in, and joins that audience's topic.
  ///
  /// Fails soft like the rest of this file: no Firebase, no pushes, and the
  /// app carries on.
  /// [askPermission] is false on a first launch, so the notification prompt
  /// does not land on top of the intro; sign-in asks then, as it always has.
  Future<void> attach(AuthController auth, {bool askPermission = true}) async {
    if (_attached) return;
    _attached = true;
    _auth = auth;
    try {
      if (Firebase.apps.isEmpty) return;

      await _local.initialize(
        const InitializationSettings(
          android: AndroidInitializationSettings('ic_notification'),
          iOS: DarwinInitializationSettings(
            requestAlertPermission: false,
            requestBadgePermission: false,
            requestSoundPermission: false,
          ),
        ),
        onDidReceiveNotificationResponse: (response) => _tapFromPayload(response.payload),
      );
      final android = _local
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
      await android?.createNotificationChannel(_kGeneralChannel);
      await android?.createNotificationChannel(_kOffersChannel);

      final messaging = FirebaseMessaging.instance;
      unawaited(messaging.subscribeToTopic('all'));
      // Asked here as well as at sign-in: Android 13+ shows nothing without
      // it, and the `all` topic's offers and festival greetings are for people
      // who have not signed in too. Already answered, this shows no prompt.
      if (askPermission) {
        unawaited(messaging.requestPermission(alert: true, badge: true, sound: true));
      }
      if (kDebugMode) unawaited(messaging.subscribeToTopic('test'));

      _openedSub?.cancel();
      _openedSub = FirebaseMessaging.onMessageOpenedApp.listen((m) => _handleTap(m.data));
      _foregroundSub?.cancel();
      _foregroundSub = FirebaseMessaging.onMessage.listen(_onForegroundMessage);

      // The app was closed and a tap on a push is what launched it.
      final initial = await messaging.getInitialMessage();
      if (initial != null) _handleTap(initial.data);
      // Or a tap on one this app drew itself while it was open, then closed.
      final launch = await _local.getNotificationAppLaunchDetails();
      if (launch?.didNotificationLaunchApp ?? false) {
        _tapFromPayload(launch!.notificationResponse?.payload);
      }

      auth.addListener(_onAuthChanged);
      _onAuthChanged();
    } catch (e, st) {
      debugPrint('PushService.attach failed (pushes off, app unaffected): $e\n$st');
    }
  }

  void _onAuthChanged() {
    final auth = _auth;
    if (auth == null || !auth.isResolved) return;
    final role = auth.isAdvocate ? 'lawyer' : (auth.isUser ? 'client' : null);
    if (role != _role) unawaited(_switchRole(role));
    _flushPendingTap();
  }

  /// Moves this device from one audience to the next: out of the old one's
  /// topic and off its account on the server, into the new one's.
  Future<void> _switchRole(String? role) async {
    final previous = _role;
    _role = role;
    final messaging = FirebaseMessaging.instance;
    try {
      if (previous != null) {
        unawaited(messaging.unsubscribeFromTopic('${previous}s'));
        _tokenSub?.cancel();
        _tokenSub = null;
        final token = _registeredToken;
        _registeredToken = null;
        // Works after sign-out too: the server needs only the token.
        if (token != null) await _dashboard.unregisterDevice(token);
      }
      if (role == null) return;

      final settings = await messaging.requestPermission(alert: true, badge: true, sound: true);
      if (settings.authorizationStatus == AuthorizationStatus.denied) return;
      await messaging.setForegroundNotificationPresentationOptions(alert: true, badge: true, sound: true);

      unawaited(messaging.subscribeToTopic('${role}s'));
      final token = await messaging.getToken();
      if (token != null) await _register(token);
      _tokenSub = messaging.onTokenRefresh.listen(_register);
    } catch (e) {
      debugPrint('PushService: could not switch push audience: $e');
    }
  }

  /// A push arriving while the app is open. Android shows nothing on its own
  /// then, so it is drawn here — except the call pushes, which drive the call
  /// screen, and a chat message for the chat already on screen.
  Future<void> _onForegroundMessage(RemoteMessage message) async {
    final data = message.data;
    final id = _consultationIdOf(data);
    switch (data['type']) {
      case _kIncomingCall:
        if (id == null) return;
        if (WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed) {
          // On screen: the in-app ringing sheet, straight away rather than on
          // the next poll.
          onOpened?.call(id);
        } else {
          await FlutterCallkitIncoming.showCallkitIncoming(_callParams(id, data));
        }
        return;
      case _kCallCancelled:
        if (id == null) return;
        await _showMissedIfRinging(id);
        await dismissCall(id);
        return;
      case 'consultation_request':
      case 'new_request':
        // The lawyer's in-app poll rings for it already.
        return;
      case 'chat_message':
        final here = AppRouter.instance?.routerDelegate.currentConfiguration.uri.path;
        if (id != null && here == '/consultation/$id/chat') return;
    }
    await _showInTray(message);
  }

  Future<void> _showInTray(RemoteMessage message) async {
    final data = message.data;
    final title = message.notification?.title ?? data['title']?.toString() ?? '';
    final body = message.notification?.body ?? data['body']?.toString() ?? '';
    if (title.isEmpty && body.isEmpty) return;

    final type = data['type']?.toString() ?? '';
    final channel = message.notification?.android?.channelId ??
        (const {'offer', 'festival', 'blog'}.contains(type) ? _kOffersChannel.id : _kGeneralChannel.id);
    final imageUrl = data['imageUrl']?.toString() ?? message.notification?.android?.imageUrl ?? '';

    StyleInformation? style;
    AndroidBitmap<Object>? thumbnail;
    if (imageUrl.startsWith('https://')) {
      try {
        final res = await Dio().get<List<int>>(
          imageUrl,
          options: Options(responseType: ResponseType.bytes, receiveTimeout: const Duration(seconds: 8)),
        );
        final bytes = res.data;
        if (bytes != null && bytes.isNotEmpty) {
          final picture = ByteArrayAndroidBitmap(Uint8List.fromList(bytes));
          style = BigPictureStyleInformation(
            picture,
            contentTitle: title,
            summaryText: body,
            hideExpandedLargeIcon: true,
          );
          // The same picture as a thumbnail on the collapsed notification, the
          // way Android shows a push with an image that it draws itself.
          thumbnail = picture;
        }
      } catch (_) {
        // No picture, still a notification.
      }
    }

    final isOffer = channel == _kOffersChannel.id;
    final tag = message.notification?.android?.tag ?? data['notificationId']?.toString();
    await _local.show(
      (tag ?? message.messageId ?? '$title$body').hashCode & 0x7fffffff,
      title,
      body,
      NotificationDetails(
        android: AndroidNotificationDetails(
          channel,
          isOffer ? _kOffersChannel.name : _kGeneralChannel.name,
          importance: isOffer ? Importance.defaultImportance : Importance.high,
          priority: isOffer ? Priority.defaultPriority : Priority.high,
          styleInformation: style ?? BigTextStyleInformation(body),
          largeIcon: thumbnail,
          // res/drawable/ic_notification: a flat silhouette, in the app's gold.
          icon: 'ic_notification',
          color: const Color(0xFFD4A017),
          tag: tag,
        ),
        iOS: const DarwinNotificationDetails(presentAlert: true, presentSound: true),
      ),
      payload: jsonEncode(data),
    );
  }

  void _tapFromPayload(String? payload) {
    if (payload == null || payload.isEmpty) return;
    try {
      final data = jsonDecode(payload);
      if (data is Map) _handleTap(Map<String, dynamic>.from(data));
    } catch (_) {}
  }

  /// A tap on any push, from any state of the app. Opens the screen it names
  /// (see [pushRoute]); a screen that needs signing in is sent through
  /// sign-in first by the router, which then comes back to it.
  void _handleTap(Map<String, dynamic> data) {
    final type = data['type']?.toString() ?? '';
    // The call pushes have their own screen and buttons.
    if (type == _kIncomingCall || type == _kCallCancelled) return;

    final url = data['url']?.toString() ?? '';
    if (url.startsWith('https://')) {
      unawaited(launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication));
      return;
    }
    if (type == 'consultation_request' || type == 'new_request') {
      // The lawyer's home, with the ringing sheet for that request.
      final id = _consultationIdOf(data);
      _navigate('/lawyer', then: () => onOpened?.call(id));
      return;
    }
    _navigate(pushRoute(data));
  }

  void _navigate(String route, {VoidCallback? then}) {
    _pendingRoute = route;
    _pendingThen = then;
    _flushPendingTap();
  }

  /// Opens a waiting tap once there is a router and a settled session — on a
  /// cold start the tap arrives while the splash is still reading who is
  /// signed in, and going anywhere then would be undone by the splash.
  void _flushPendingTap() {
    final route = _pendingRoute;
    final router = AppRouter.instance;
    if (route == null || router == null || !(_auth?.isResolved ?? false)) return;
    final then = _pendingThen;
    _pendingRoute = null;
    _pendingThen = null;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Future.delayed(const Duration(milliseconds: 300), () {
        router.go(route);
        then?.call();
      });
    });
  }

  /// Calls this app took down itself. Ending an unanswered call reports back
  /// as a Decline event, and that must not turn the request down.
  final Set<String> _dismissed = {};

  /// The lawyer-only part: the full-screen call screen, its buttons, and the
  /// call and request channels. Called once a lawyer is signed in (see
  /// LawyerController). Registering the device is [attach]'s job.
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

      // Registering this device with the server, the tap handler, and the
      // open-app handler that also drives the call screen are all in
      // [attach], which runs for every user — clients as well as lawyers.

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
      await _dashboard.registerDevice(token);
      _registeredToken = token;
    } catch (e) {
      debugPrint('PushService: could not register token: $e');
    }
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

  /// The lawyer signed out: the call screen's listeners go. The device itself
  /// comes off the server in [_switchRole], which follows sign-out for every
  /// user — so a phone that moves on to another account stops ringing for
  /// the one it left. The tap and open-app handlers stay: they serve whoever
  /// uses the app next, signed in or not.
  Future<void> stop() async {
    _callSub?.cancel();
    _callSub = null;
    _lifecycle?.dispose();
    _lifecycle = null;
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
