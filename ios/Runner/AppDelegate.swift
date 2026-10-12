import FirebaseCore
import FirebaseMessaging
import Flutter
import UIKit
import UserNotifications

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // Firebase first, so the APNs token below always has somewhere to go;
    // Firebase.initializeApp() in main.dart then finds it already set up.
    if FirebaseApp.app() == nil {
      FirebaseApp.configure()
    }
    // Lets a notification the app posts itself (a push that arrived while the
    // app was open — see PushService._showInTray) show as a banner.
    UNUserNotificationCenter.current().delegate = self
    // Ask iOS for this phone's APNs token now. The plugins register only once
    // the Flutter engine is up — after launch, with the scene-based app — so
    // firebase_messaging's own launch-time request never ran, no APNs token
    // came, and without one Firebase has no token and joins no topic.
    application.registerForRemoteNotifications()
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  // The APNs token, straight to Firebase. Firebase's own swizzling does this
  // too, but it hooks the app delegate as it is at Firebase's start, which in
  // the scene-based app can be after iOS has already answered.
  override func application(
    _ application: UIApplication,
    didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
  ) {
    Messaging.messaging().apnsToken = deviceToken
    super.application(application, didRegisterForRemoteNotificationsWithDeviceToken: deviceToken)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
  }
}
