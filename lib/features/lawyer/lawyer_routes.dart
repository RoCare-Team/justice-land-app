import 'package:go_router/go_router.dart';

import 'client_details_screen.dart';
import 'lawyer_availability_screen.dart';
import 'lawyer_cases_screen.dart';
import 'lawyer_earnings_screen.dart';
import 'lawyer_home_screen.dart';
import 'lawyer_messages_screen.dart';
import 'lawyer_notifications_screen.dart';
import 'lawyer_plan_screen.dart';
import 'lawyer_profile_screen.dart';
import 'lawyer_queries_screen.dart';
import 'lawyer_requests_screen.dart';
import 'lawyer_settings_screen.dart';
import 'lawyer_shell.dart';

/// Every screen of the lawyer app. The router only lets a signed-in lawyer in
/// here, and only lets a signed-in lawyer out to a live session, the profile
/// editor and a few reading pages (see AppRouter).
///
/// The inner screens are declared before the tab shell so that, for instance,
/// '/lawyer/earnings' is never mistaken for a tab.
final List<RouteBase> lawyerRoutes = [
  GoRoute(
    path: '/lawyer/client/:userId',
    builder: (context, state) => ClientDetailsScreen(userId: state.pathParameters['userId']!),
  ),
  GoRoute(
    path: '/lawyer/transcript/:id',
    builder: (context, state) => TranscriptScreen(
      consultationId: state.pathParameters['id']!,
      name: state.uri.queryParameters['name'] ?? '',
    ),
  ),
  GoRoute(path: '/lawyer/earnings', builder: (_, __) => const LawyerEarningsScreen()),
  GoRoute(path: '/lawyer/availability', builder: (_, __) => const LawyerAvailabilityScreen()),
  GoRoute(path: '/lawyer/notifications', builder: (_, __) => const LawyerNotificationsScreen()),
  GoRoute(path: '/lawyer/settings', builder: (_, __) => const LawyerSettingsScreen()),
  GoRoute(path: '/lawyer/queries', builder: (_, __) => const LawyerQueriesScreen()),
  GoRoute(path: '/lawyer/plan', builder: (_, __) => const LawyerPlanScreen()),
  ShellRoute(
    builder: (context, state, child) => LawyerShell(child: child),
    routes: [
      GoRoute(path: '/lawyer', builder: (_, __) => const LawyerHomeScreen()),
      GoRoute(path: '/lawyer/requests', builder: (_, __) => const LawyerRequestsScreen()),
      GoRoute(path: '/lawyer/consultations', builder: (_, __) => const LawyerCasesScreen()),
      GoRoute(path: '/lawyer/messages', builder: (_, __) => const LawyerMessagesScreen()),
      GoRoute(path: '/lawyer/profile', builder: (_, __) => const LawyerProfileScreen()),
    ],
  ),
];
