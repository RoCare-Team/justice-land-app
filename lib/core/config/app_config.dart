/// Build-time configuration.
///
/// The app talks to the same Next.js backend the website runs on — no separate
/// mobile API. Point [baseUrl] at whichever deployment you are testing:
///
///   flutter run --dart-define=API_BASE_URL=http://10.0.2.2:3000
///
/// 10.0.2.2 is how the Android emulator reaches the host machine's localhost.
/// On a physical device use the machine's LAN address (http://192.168.x.x:3000)
/// and make sure `next dev` is listening on it.
class AppConfig {
  const AppConfig._();

  static const String baseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'https://www.justiceland.online',
  );

  /// Razorpay key id. Public by design — it ships in the web page too — but the
  /// app never hardcodes it in a payment: /api/wallet/order returns the key
  /// that is actually configured, so rotating it in /admin takes effect here
  /// on the very next top-up.
  static const String razorpayFallbackKeyId = String.fromEnvironment(
    'RAZORPAY_KEY_ID',
    defaultValue: '',
  );

  static const String appName = 'Justiceland';

  /// Shown on the More screen. Kept in step with `version:` in pubspec.yaml by
  /// hand — Flutter does not expose it to Dart without a plugin, and one plugin
  /// for one string on one screen is not a trade worth making.
  static const String version = '1.0.8';
  static const String supportEmail = 'support@justiceland.online';

  /// How often live screens re-read the server. These mirror the web client:
  /// the consultation screens poll, they do not hold a socket open.
  static const Duration sessionPoll = Duration(seconds: 2);
  static const Duration inboxPoll = Duration(seconds: 4);
  static const Duration callSignalPoll = Duration(seconds: 1);

  /// The same reads while a call is being put together — waiting for the
  /// lawyer to accept, for the call to ring, for the handshake. Each of those
  /// steps waits on the other phone's next read, so these decide how long
  /// "Connecting…" lasts; they drop back to the rates above once connected.
  static const Duration sessionPollConnecting = Duration(milliseconds: 400);
  static const Duration callSignalPollConnecting = Duration(milliseconds: 250);

  /// A live chat re-reads a little faster once the server reports typing,
  /// so "typing…" and the blue ticks keep up with the conversation.
  static const Duration chatPollTyping = Duration(milliseconds: 1200);

  /// Wallet top-up bounds, matching /api/wallet/order.
  static const int minTopUp = 50;
  static const int maxTopUp = 100000;
  static const List<int> quickTopUps = [50, 100, 500, 1000, 2000];
}
