import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
import 'services/wallet_service.dart';
import 'features/onboarding/onboarding_screen.dart';
import 'state/auth_controller.dart';
import 'state/location_controller.dart';
import 'state/marketplace_controller.dart';
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

  // The cookie jar has to exist before the first request — it *is* the
  // session, so a request made before it loads would arrive signed out.
  final api = await ApiClient.init();

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

        // Controllers hold what the server last said.
        ChangeNotifierProvider(
          create: (context) => AuthController(context.read<AuthService>())..refresh(),
        ),
        ChangeNotifierProvider(
          create: (context) =>
              LocationController(context.read<ContentService>())..restore(),
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
          child: child ?? const SizedBox.shrink(),
        );
      },
    );
  }
}
