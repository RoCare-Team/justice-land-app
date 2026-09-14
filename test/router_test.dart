// Drives the real GoRouter against a stubbed server, so navigation bugs show
// up here instead of on a device.

import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:provider/provider.dart';

import 'package:flutter_legal_care/core/network/api_client.dart';
import 'package:flutter_legal_care/routing/app_router.dart';
import 'package:flutter_legal_care/services/advocate_service.dart';
import 'package:flutter_legal_care/services/auth_service.dart';
import 'package:flutter_legal_care/services/consultation_service.dart';
import 'package:flutter_legal_care/services/content_service.dart';
import 'package:flutter_legal_care/services/dashboard_service.dart';
import 'package:flutter_legal_care/services/marketplace_service.dart';
import 'package:flutter_legal_care/services/wallet_service.dart';
import 'package:flutter_legal_care/state/auth_controller.dart';
import 'package:flutter_legal_care/state/lawyer_controller.dart';
import 'package:flutter_legal_care/state/location_controller.dart';
import 'package:flutter_legal_care/state/marketplace_controller.dart';
import 'package:flutter_legal_care/state/wallet_controller.dart';

class _FakePathProvider extends PathProviderPlatform with MockPlatformInterfaceMixin {
  @override
  Future<String?> getApplicationDocumentsPath() async => '.dart_tool/test_docs';
}

/// Answers every request with an empty JSON object unless [routes] says more.
class _StubAdapter implements HttpClientAdapter {
  _StubAdapter(this.routes);

  final Map<String, Object> routes;

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? _, Future<void>? __) async {
    final body = routes[options.path] ?? <String, dynamic>{};
    return ResponseBody.fromString(
      jsonEncode(body),
      200,
      headers: {Headers.contentTypeHeader: [Headers.jsonContentType]},
    );
  }

  @override
  void close({bool force = false}) {}
}

/// Boots the client and session the way main() does.
///
/// Wrapped in [WidgetTester.runAsync] because the cookie jar reads and writes
/// real files: inside the fake-async zone a test body runs in, that I/O never
/// completes and the await never returns.
Future<(ApiClient, AuthController)> _boot(
  WidgetTester tester, {
  required Map<String, Object> server,
}) async {
  PathProviderPlatform.instance = _FakePathProvider();
  final booted = await tester.runAsync(() async {
    final api = await ApiClient.init();
    api.raw.httpClientAdapter = _StubAdapter(server);
    final auth = AuthController(AuthService(api));
    await auth.refresh();
    return (api, auth);
  });
  return booted!;
}

/// The same provider tree main() builds, minus the eager refresh/restore the
/// test does itself — the router's screens read these off the context, so a
/// shorter tree would fail on a missing provider rather than on navigation.
Widget _app(ApiClient api, AuthController auth) => MultiProvider(
      providers: [
        Provider.value(value: api),
        Provider(create: (_) => AuthService(api)),
        Provider(create: (_) => AdvocateService(api)),
        Provider(create: (_) => ConsultationService(api)),
        Provider(create: (_) => WalletService(api)),
        Provider(create: (_) => DashboardService(api)),
        Provider(create: (_) => ContentService(api)),
        Provider(create: (_) => MarketplaceService(api)),
        ChangeNotifierProvider.value(value: auth),
        ChangeNotifierProvider(
          create: (context) => LocationController(context.read<ContentService>()),
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
        ChangeNotifierProxyProvider<AuthController, LawyerController>(
          create: (context) => LawyerController(
            context.read<ConsultationService>(),
            context.read<DashboardService>(),
            context.read<AuthController>(),
          ),
          update: (_, __, lawyer) => lawyer!,
        ),
      ],
      child: MaterialApp.router(routerConfig: AppRouter.build(auth)),
    );

// The home screen shimmers while it loads, so pumpAndSettle would never
// return. Pump a fixed number of frames instead.
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  testWidgets('signed-out launch lands on home', (tester) async {
    final (api, auth) = await _boot(tester, server: {'/api/auth/me': <String, dynamic>{}});
    await tester.pumpWidget(_app(api, auth));
    await _settle(tester);
    expect(tester.takeException(), isNull);
  });

  testWidgets('pushing over a shell tab keeps page keys unique', (tester) async {
    final (api, auth) = await _boot(tester, server: {'/api/auth/me': <String, dynamic>{}});
    await tester.pumpWidget(_app(api, auth));
    await _settle(tester);

    final router = GoRouter.of(tester.element(find.byType(Navigator).first));
    router.push('/blogs');
    await _settle(tester);
    router.push('/more');
    await _settle(tester);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a signed-in lawyer gets the lawyer app, never the client side', (tester) async {
    final now = DateTime.now().toUtc();
    final pending = <String, dynamic>{
      'id': 'c1', 'userId': 'u1', 'userName': 'Amit Kumar', 'advocateId': 'a1',
      'type': 'chat', 'status': 'pending', 'rate': 10, 'maxMinutes': 30,
      'createdAt': now.subtract(const Duration(minutes: 2)).toIso8601String(),
    };
    final ended = <String, dynamic>{
      'id': 'c2', 'userId': 'u2', 'userName': 'Neha Verma', 'advocateId': 'a1',
      'type': 'video', 'status': 'ended', 'rate': 20, 'minutes': 5, 'price': 100,
      'charged': true, 'talkedMinutes': 5, 'messagesCount': 3,
      'lastMessage': {'from': 'user', 'text': 'Thank you', 'at': now.toIso8601String()},
      'startedAt': now.subtract(const Duration(hours: 1)).toIso8601String(),
      'createdAt': now.subtract(const Duration(hours: 1)).toIso8601String(),
    };
    final (api, auth) = await _boot(tester, server: {
      '/api/auth/me': <String, dynamic>{
        'role': 'advocate',
        'advocate': <String, dynamic>{
          'id': 'a1', 'name': 'Adv. Test', 'status': 'published', 'chatRate': 10,
          'officeTiming': [
            {'day': 'Monday', 'hours': '10:00 AM - 6:00 PM', 'open': true},
          ],
        },
      },
      // The inbox and the history share this path; each reads its own key.
      '/api/consultations': <String, dynamic>{
        'sessions': [pending],
        'consultations': [pending, ended],
      },
      '/api/dashboard/profile': <String, dynamic>{
        'advocate': {
          'walletBalance': 100,
          'walletTransactions': [
            {'type': 'credit', 'amount': 100, 'note': '5 min video consultation', 'createdAt': now.toIso8601String()},
          ],
        },
      },
    });
    expect(auth.isAdvocate, isTrue);

    await tester.pumpWidget(_app(api, auth));
    await _settle(tester);

    final router = GoRouter.of(tester.element(find.byType(Navigator).first));
    expect(router.routerDelegate.currentConfiguration.uri.path, '/lawyer');

    // The directory and the client home both send a lawyer back home.
    for (final path in ['/lawyers', '/', '/services', '/wallet']) {
      router.go(path);
      await _settle(tester);
      expect(router.routerDelegate.currentConfiguration.uri.path, '/lawyer', reason: path);
    }

    // Every lawyer screen opens and lays out without throwing.
    for (final path in [
      '/lawyer/requests',
      '/lawyer/consultations',
      '/lawyer/messages',
      '/lawyer/profile',
      '/lawyer/earnings',
      '/lawyer/availability',
      '/lawyer/notifications',
      '/lawyer/settings',
      '/lawyer/client/u1',
      '/lawyer/client/u2',
      '/lawyer/transcript/c2',
      '/lawyer',
    ]) {
      router.go(path);
      await _settle(tester);
      expect(router.routerDelegate.currentConfiguration.uri.path, path, reason: path);
      expect(tester.takeException(), isNull, reason: path);
    }

    // A request that arrives while the lawyer is on Home rings: the sheet opens.
    final fresh = {...pending, 'id': 'c3', 'userId': 'u3', 'userName': 'Rohit Mehta'};
    api.raw.httpClientAdapter = _StubAdapter({
      '/api/auth/me': {'role': 'advocate', 'advocate': {'id': 'a1', 'name': 'Adv. Test', 'status': 'published'}},
      '/api/consultations': {'sessions': [pending, fresh], 'consultations': [pending, ended]},
    });
    for (var i = 0; i < 60; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.text('Incoming request'), findsOneWidget);
    expect(find.text('Rohit Mehta'), findsWidgets);
    expect(tester.takeException(), isNull);

    // Unmount so the workspace's poll timers are cancelled before the test ends.
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
