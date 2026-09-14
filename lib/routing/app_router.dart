import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../core/theme/app_theme.dart';
import '../core/widgets/states.dart';
import '../features/account/more_screen.dart';
import '../features/account/profile_screen.dart';
import '../features/account/wallet_screen.dart';
import '../features/auth/advocate_auth_screen.dart';
import '../features/auth/login_screen.dart';
import '../features/consultation/audio_call_screen.dart';
import '../features/consultation/chat_screen.dart';
import '../features/consultation/consultations_screen.dart';
import '../features/consultation/video_call_screen.dart';
import '../features/content/content_screens.dart';
import '../features/dashboard/dashboard_screen.dart';
import '../features/dashboard/edit_profile_screen.dart';
import '../features/home/home_screen.dart';
import '../features/lawyers/advocate_profile_screen.dart';
import '../features/lawyers/lawyers_screen.dart';
import '../features/onboarding/onboarding_screen.dart';
import '../features/onboarding/role_selection_screen.dart';
import '../features/services/all_services_screen.dart';
import '../features/services/my_orders_screen.dart';
import '../features/services/order_summary_screen.dart';
import '../features/services/service_detail_screen.dart';
import '../features/services/services_screen.dart';
import '../features/splash/splash_screen.dart';
import '../state/auth_controller.dart';

/// Every route in the app, mapped to the website's own URLs so a link shared
/// from one lands in the same place on the other.
class AppRouter {
  const AppRouter._();

  static GoRouter build(AuthController auth, {bool showIntro = false}) {
    return GoRouter(
      initialLocation: '/splash',
      // Rebuilds the redirect whenever the session changes, so signing out on
      // one screen cannot leave a protected screen open behind it.
      refreshListenable: auth,
      redirect: (context, state) {
        final path = state.uri.path;

        // Nothing is decided until the session has been read once.
        if (!auth.isResolved) return path == '/splash' ? null : '/splash';
        // A first launch is owed the intro and the role choice. This is
        // decided here, with a flag main() resolved before the app started,
        // because the splash used to ask the question itself after its first
        // frame and the session often resolved first — sending a brand-new
        // install straight to the home screen.
        if (path == '/splash') return showIntro ? '/onboarding' : '/';

        // The intro and the role choice are first-launch things that show
        // themselves out; neither needs a session to be useful.
        if (path == '/onboarding' || path == '/role') return null;

        const guardedForAdvocate = ['/dashboard'];

        // The consultations and wallet tabs are deliberately NOT guarded. A tab
        // that bounces to a sign-in form the moment it is touched is worse than
        // one that stays put and says what signing in would give you — each of
        // those screens does that itself.
        if (guardedForAdvocate.any(path.startsWith) && !auth.isAdvocate) {
          return '/advocate/login';
        }
        // A live consultation belongs to whoever is signed in; anonymous
        // visitors get sent to sign in rather than a 403 screen.
        if (path.startsWith('/consultation/') && !auth.isSignedIn) {
          return '/login?redirect=$path';
        }
        return null;
      },
      routes: [
        GoRoute(path: '/splash', builder: (_, __) => const SplashScreen()),
        GoRoute(path: '/onboarding', builder: (_, __) => const OnboardingScreen()),
        GoRoute(path: '/role', builder: (_, __) => const RoleSelectionScreen()),

        ShellRoute(
          builder: (context, state, child) => AppShell(child: child),
          routes: [
            GoRoute(path: '/', builder: (_, __) => const HomeScreen()),
            GoRoute(
              path: '/lawyers',
              builder: (context, state) => LawyersScreen(
                initialCity: state.uri.queryParameters['city'] ?? '',
                initialService: state.uri.queryParameters['service'] ?? '',
                initialQuery: state.uri.queryParameters['q'] ?? '',
              ),
            ),
            GoRoute(
              path: '/consultations',
              builder: (context, state) => ConsultationsScreen(
                initialTab: state.uri.queryParameters['tab'] ?? 'active',
              ),
            ),
            GoRoute(
              path: '/services',
              builder: (context, state) => ServicesScreen(
                initialCategory: state.uri.queryParameters['category'] ?? '',
              ),
            ),
            GoRoute(path: '/wallet', builder: (_, __) => const WalletScreen()),
            GoRoute(path: '/profile', builder: (_, __) => const ProfileScreen()),
            GoRoute(
              path: '/dashboard',
              builder: (context, state) => DashboardScreen(
                initialTab: state.uri.queryParameters['tab'] ?? 'inbox',
              ),
            ),
          ],
        ),

        GoRoute(path: '/more', builder: (_, __) => const MoreScreen()),

        // Declared before '/services/:slug' on purpose. go_router takes the
        // first route that matches, and without this ordering the literal
        // 'all' would be read as a service slug and 404.
        GoRoute(
          path: '/services/all',
          builder: (context, state) => AllServicesScreen(
            initialCategory: state.uri.queryParameters['category'] ?? '',
            autofocusSearch: state.uri.queryParameters['focus'] == '1',
          ),
        ),

        // A service keeps the shape of its slug, so a link to
        // /services/trademark-registration opens the same thing everywhere.
        GoRoute(
          path: '/services/:slug',
          builder: (context, state) =>
              ServiceDetailScreen(slug: state.pathParameters['slug']!),
          routes: [
            GoRoute(
              path: 'order',
              builder: (context, state) =>
                  OrderSummaryScreen(slug: state.pathParameters['slug']!),
            ),
          ],
        ),
        GoRoute(
          path: '/orders',
          builder: (context, state) => MyOrdersScreen(
            highlightId: state.uri.queryParameters['placed'] ?? '',
          ),
        ),

        // Lawyer profiles keep the website's path shape, so
        // /lawyers/advocate-manoj-sharma-jusld04 opens the same profile here.
        GoRoute(
          path: '/lawyers/:profilePath',
          builder: (context, state) => AdvocateProfileScreen(
            profilePath: state.pathParameters['profilePath']!,
          ),
        ),

        GoRoute(
          path: '/login',
          builder: (context, state) => LoginScreen(
            redirectTo: state.uri.queryParameters['redirect'],
          ),
        ),
        GoRoute(
          path: '/advocate/login',
          builder: (_, __) =>
              const AdvocateAuthScreen(intent: AdvocateAuthIntent.login),
        ),
        GoRoute(
          path: '/advocate/register',
          // Same screen. The number decides whether this ends in a sign-in
          // or a sign-up, so two entry points need only one destination.
          builder: (_, __) =>
              const AdvocateAuthScreen(intent: AdvocateAuthIntent.register),
        ),
        // No forgot-password route. There is no password to forget: a lawyer
        // signs in with a code sent to their number, and the website's reset
        // endpoints were removed along with the password itself.

        GoRoute(
          path: '/dashboard/profile',
          builder: (_, __) => const EditProfileScreen(),
        ),

        GoRoute(
          path: '/consultation/:id/chat',
          builder: (context, state) =>
              ChatScreen(consultationId: state.pathParameters['id']!),
        ),
        GoRoute(
          path: '/consultation/:id/video',
          builder: (context, state) =>
              VideoCallScreen(consultationId: state.pathParameters['id']!),
        ),
        GoRoute(
          path: '/consultation/:id/audio',
          builder: (context, state) =>
              AudioCallScreen(consultationId: state.pathParameters['id']!),
        ),

        GoRoute(path: '/blogs', builder: (_, __) => const BlogsScreen()),
        GoRoute(
          path: '/blogs/:slug',
          builder: (context, state) =>
              BlogDetailScreen(slug: state.pathParameters['slug']!),
        ),
        GoRoute(path: '/contact', builder: (_, __) => const ContactScreen()),
      ],
      errorBuilder: (context, state) => Scaffold(
        appBar: AppBar(title: const Text('Not found')),
        body: EmptyView(
          icon: Icons.explore_off_rounded,
          title: 'Page not found',
          message: 'That link does not lead anywhere in the app.',
          action: FilledButton(
            onPressed: () => context.go('/'),
            child: const Text('Back to home'),
          ),
        ),
      ),
    );
  }
}

/// One destination in the bottom bar.
typedef AppTab = ({String path, IconData icon, IconData active, String label});

/// The bottom navigation the main sections share.
///
/// Five slots, and the middle two are the difference between the two people who
/// use this app. A client gets their consultations, their wallet and their
/// profile; a lawyer gets their dashboard in place of the wallet, because a
/// lawyer earns rather than tops up and their earnings live on the dashboard.
class AppShell extends StatelessWidget {
  const AppShell({super.key, required this.child});

  final Widget child;

  static const AppTab _home =
      (path: '/', icon: Icons.home_outlined, active: Icons.home_rounded, label: 'Home');
  /// The raised gold slot. Reaching a lawyer is the errand this app exists
  /// for, and on a bar of five identical grey icons it looked exactly as
  /// important as "Profile", which it is not.
  static const AppTab _topLawyers = (
    path: '/lawyers',
    icon: Icons.gavel_outlined,
    active: Icons.gavel_rounded,
    label: 'Top Lawyers',
  );

  static const AppTab _services = (
    path: '/services',
    icon: Icons.workspace_premium_outlined,
    active: Icons.workspace_premium_rounded,
    label: 'Services',
  );
  static const AppTab _consultations = (
    path: '/consultations',
    icon: Icons.forum_outlined,
    active: Icons.forum_rounded,
    label: 'Consults',
  );
  static const AppTab _wallet = (
    path: '/wallet',
    icon: Icons.account_balance_wallet_outlined,
    active: Icons.account_balance_wallet_rounded,
    label: 'Wallet',
  );
  static const AppTab _profile = (
    path: '/profile',
    icon: Icons.person_outline_rounded,
    active: Icons.person_rounded,
    label: 'Profile',
  );
  static const AppTab _dashboard = (
    path: '/dashboard',
    icon: Icons.dashboard_outlined,
    active: Icons.dashboard_rounded,
    label: 'Dashboard',
  );

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthController>();
    final location = GoRouterState.of(context).uri.path;

    // Top Lawyers sits in the middle, in the raised gold slot, because it is
    // what someone opens this app to do. Services takes the slot beside it —
    // the second thing there is to buy here, and the one a client browsing
    // rather than in trouble is after.
    //
    // Consultations are not a tab. A client has one open only occasionally,
    // and giving a rarely-used destination a fifth of the bar cost the two
    // things that are used constantly. It is reached from the bell in the home
    // header and from Profile, both of which are always one tap away.
    final List<AppTab> tabs = auth.isAdvocate
        ? const [_home, _services, _topLawyers, _dashboard, _profile]
        : const [_home, _services, _topLawyers, _wallet, _profile];

    // A route that is not itself a tab keeps the bar on Home rather than on
    // nothing; anything pushed over the shell covers the bar anyway.
    var index = tabs.indexWhere((t) => t.path == location);
    if (index < 0) index = 0;

    final middle = tabs.length ~/ 2;

    return Scaffold(
      body: child,
      extendBody: true,
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: AppColors.surface,
          boxShadow: [
            BoxShadow(
              color: AppColors.ink.withValues(alpha: 0.07),
              blurRadius: 18,
              offset: const Offset(0, -3),
            ),
          ],
        ),
        child: SafeArea(
          top: false,
          child: SizedBox(
            height: 62,
            child: Row(
              // Stretch so each tab is exactly as tall as the bar: the raised
              // tab positions its circle against that height.
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < tabs.length; i++)
                  Expanded(
                    child: i == middle
                        ? _raisedTab(context, tabs[i], i == index)
                        : _flatTab(context, tabs[i], i == index),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _flatTab(BuildContext context, AppTab tab, bool selected) {
    return InkWell(
      onTap: () => context.go(tab.path),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            selected ? tab.active : tab.icon,
            size: 22,
            color: selected
                ? AppColors.primary
                : AppColors.ink.withValues(alpha: 0.42),
          ),
          const SizedBox(height: 3),
          Text(
            tab.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              color: selected
                  ? AppColors.primary
                  : AppColors.ink.withValues(alpha: 0.45),
            ),
          ),
        ],
      ),
    );
  }

  Widget _raisedTab(BuildContext context, AppTab tab, bool selected) {
    return InkWell(
      onTap: () => context.go(tab.path),
      // A Stack, not a Column. The circle is 50 tall and lifted clear of the
      // bar, and anything that claims height inside a 62px bar pushes the
      // label off the baseline the other four labels sit on — which is what
      // left "Top Lawyers" sitting lower than its neighbours. Here the label
      // is laid out in exactly the skeleton a flat tab uses, so it lands on
      // the same baseline at any text size, and the circle is painted over
      // that skeleton rather than measured into it. `extendBody` on the
      // Scaffold is what lets the lifted part sit over the content.
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // The slot a flat tab gives its icon, left empty here.
                const SizedBox(height: 22),
                const SizedBox(height: 3),
                Text(
                  tab.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                    color: selected
                        ? AppColors.primary
                        : AppColors.ink.withValues(alpha: 0.55),
                  ),
                ),
              ],
            ),
          ),
          Positioned(
            top: -12,
            left: 0,
            right: 0,
            child: Center(
              child: Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                  color: AppColors.accent,
                  shape: BoxShape.circle,
                  border: Border.all(color: AppColors.surface, width: 3.5),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.accent.withValues(alpha: 0.35),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Icon(tab.active, size: 23, color: AppColors.primaryDark),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
