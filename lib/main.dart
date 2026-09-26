import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'core/network/api_client.dart';
import 'core/theme/app_theme.dart';
import 'routing/app_router.dart';
import 'services/advocate_service.dart';
import 'services/auth_service.dart';
import 'services/consultation_service.dart';
import 'services/content_service.dart';
import 'services/dashboard_service.dart';
import 'services/marketplace_service.dart';
import 'services/membership_service.dart';
import 'services/voice_service.dart';
import 'services/push_service.dart';
import 'services/query_service.dart';
import 'services/wallet_service.dart';
import 'features/consultation/active_call_bar.dart';
import 'features/onboarding/onboarding_screen.dart';
import 'state/auth_controller.dart';
import 'state/lawyer_controller.dart';
import 'state/location_controller.dart';
import 'state/saved_lawyers_controller.dart';
import 'state/marketplace_controller.dart';
import 'state/queries_controller.dart';
import 'state/wallet_controller.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Portrait only: a live consultation, a chat thread and a five-step form are
  // all built around a single column, and the video screen manages its own
  // orientation while a call is up.
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  // Absent google-services.json this fails and is caught inside — the rest of
  // the app starts exactly as it did before pushes existed. The background
  // handler is registered either way; it is a no-op until Firebase is.
  await initFirebase();
  FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

  // The cookie jar has to exist before the first request — it *is* the
  // session, so a request made before it loads would arrive signed out.
  final api = await ApiClient.init();

  // Accept on the incoming-call screen is what launched the app: tell the
  // server now, before the sign-in check and the first screen, so the
  // client's phone is already ringing by the time the call screen opens.
  unawaited(acceptAnsweredCallEarly(ConsultationService(api)));

  // Read here rather than from the splash screen. The router leaves /splash
  // the moment the session resolves, and that beat an async preference read
  // started after the first frame — which is how a fresh install skipped the
  // intro and the role choice and opened straight on the home screen.
  final showIntro = await OnboardingScreen.isPending();

  runApp(JusticelandApp(api: api, showIntro: showIntro));
}

class JusticelandApp extends StatelessWidget {
  const JusticelandApp({super.key, required this.api, this.showIntro = false});

  final ApiClient api;

  /// True on a first launch, when the intro and the role choice are still owed.
  final bool showIntro;

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        Provider.value(value: api),

        // Services are stateless wrappers around the API.
        Provider(create: (_) => AuthService(api)),
        Provider(create: (_) => AdvocateService(api)),
        Provider(create: (_) => ConsultationService(api)),
        Provider(create: (_) => WalletService(api)),
        Provider(create: (_) => DashboardService(api)),
        Provider(create: (_) => ContentService(api)),
        Provider(create: (_) => MarketplaceService(api)),
        Provider(create: (_) => QueryService(api)),
        Provider(create: (_) => MembershipService(api)),
        Provider(create: (_) => VoiceService(api)),
        Provider(create: (context) => PushService(context.read<DashboardService>())),

        // Controllers hold what the server last said.
        ChangeNotifierProvider(
          create: (context) => AuthController(context.read<AuthService>())..refresh(),
        ),
        ChangeNotifierProvider(
          create: (context) =>
              LocationController(context.read<ContentService>())..restore(),
        ),
        // The shortlist behind the heart on every lawyer card. Device-local,
        // so it is read once at startup and never waits on the network.
        ChangeNotifierProvider(
          create: (_) => SavedLawyersController()..load(),
        ),
        ChangeNotifierProxyProvider<AuthController, WalletController>(
          create: (context) => WalletController(
            context.read<WalletService>(),
            context.read<AuthController>(),
          ),
          update: (_, __, wallet) => wallet!,
        ),
        ChangeNotifierProxyProvider<AuthController, MarketplaceController>(
          create: (context) => MarketplaceController(
            context.read<MarketplaceService>(),
            context.read<AuthController>(),
          ),
          update: (_, __, market) => market!,
        ),
        // The lawyer workspace. Idle for clients; starts polling the moment a
        // lawyer signs in and stops when they sign out.
        ChangeNotifierProxyProvider<AuthController, LawyerController>(
          create: (context) => LawyerController(
            context.read<ConsultationService>(),
            context.read<DashboardService>(),
            context.read<AuthController>(),
            context.read<PushService>(),
          ),
          update: (_, __, lawyer) => lawyer!,
        ),
        // Client queries and credits for a signed-in lawyer; idle otherwise.
        ChangeNotifierProxyProvider<AuthController, QueriesController>(
          create: (context) => QueriesController(
            context.read<QueryService>(),
            context.read<AuthController>(),
          ),
          update: (_, __, queries) => queries!,
        ),
      ],
      child: _App(showIntro: showIntro),
    );
  }
}

class _App extends StatefulWidget {
  const _App({required this.showIntro});

  final bool showIntro;

  @override
  State<_App> createState() => _AppState();
}

class _AppState extends State<_App> {
  @override
  Widget build(BuildContext context) {
    final auth = context.read<AuthController>();

    return MaterialApp.router(
      title: 'Justiceland',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      routerConfig: AppRouter.build(auth, showIntro: widget.showIntro),
      builder: (context, child) {
        // Text scaling is respected but capped: past ~1.3 the live consultation
        // meters and the five-step wizard start clipping, and a clipped
        // countdown on a billing screen is worse than a slightly smaller one.
        final media = MediaQuery.of(context);
        return MediaQuery(
          data: media.copyWith(
            textScaler: media.textScaler.clamp(maxScaleFactor: 1.3),
          ),
          // The green "call in progress" strip, over every screen while an
          // audio consultation runs without its own screen showing.
          child: _BackGuard(child: ActiveCallBar(child: child ?? const SizedBox.shrink())),
        );
      },
    );
  }
}

/// Asks before the back button closes the app.
///
/// The tabs are reached with `go`, which replaces the stack rather than
/// stacking on it, so on a tab there is nothing to pop and the first back press
/// used to drop the lawyer — or the client — straight out of the app, mid
/// session and without warning. Back still means back wherever there is
/// somewhere to go back to; it only asks at the point where the answer is
/// "nowhere, so we would be leaving".
class _BackGuard extends StatelessWidget {
  const _BackGuard({required this.child});

  final Widget child;

  Future<bool> _confirm(BuildContext context) async {
    final leave = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Close Justiceland?'),
        content: const Text('You will stay signed in for the next time.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Stay'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Close'),
          ),
        ],
      ),
    );
    return leave ?? false;
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      // Never pop straight away: whether this back press should move within the
      // app or leave it is decided below.
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;

        final router = GoRouter.of(context);
        if (router.canPop()) {
          router.pop();
          return;
        }

        if (await _confirm(context)) {
          await SystemNavigator.pop();
        }
      },
      child: child,
    );
  }
}
