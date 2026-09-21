// The lawyer's profile editor: what was chosen in the onboarding shows as
// chosen, the matters are there, About comes last, and ticking past the plan
// opens the plans instead of failing on save.

import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:provider/provider.dart';

import 'package:flutter_legal_care/core/network/api_client.dart';
import 'package:flutter_legal_care/core/theme/app_theme.dart';
import 'package:flutter_legal_care/core/widgets/common.dart';
import 'package:flutter_legal_care/features/dashboard/edit_profile_screen.dart';
import 'package:flutter_legal_care/features/lawyer/city_picker.dart';
import 'package:flutter_legal_care/services/auth_service.dart';
import 'package:flutter_legal_care/services/content_service.dart';
import 'package:flutter_legal_care/services/dashboard_service.dart';
import 'package:flutter_legal_care/services/membership_service.dart';
import 'package:flutter_legal_care/state/auth_controller.dart';

class _FakePathProvider extends PathProviderPlatform with MockPlatformInterfaceMixin {
  @override
  Future<String?> getApplicationDocumentsPath() async => '.dart_tool/test_docs';
}

class _Adapter implements HttpClientAdapter {
  _Adapter(this.handler);

  final (int, Object) Function(RequestOptions) handler;
  final List<RequestOptions> seen = [];

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? _, Future<void>? __) async {
    seen.add(options);
    final (status, body) = handler(options);
    return ResponseBody.fromString(
      jsonEncode(body),
      status,
      headers: {Headers.contentTypeHeader: [Headers.jsonContentType]},
    );
  }

  @override
  void close({bool force = false}) {}
}

Map<String, dynamic> _plan(String id, String name, int monthly, {int? areas, int? matters, int? cities}) => {
      'id': id,
      'name': name,
      'tagline': '',
      'monthly': monthly,
      'queryCredits': 0,
      'areas': areas,
      'matters': matters,
      'cities': cities,
      'placement': '',
      'features': <String>[],
      'price': {'base': 0, 'gst': 0, 'total': monthly * 12, 'monthly': monthly},
    };

Map<String, dynamic> _service(String name) => {
      'name': name,
      'slug': name.toLowerCase().replaceAll(' ', '-'),
      'description': '',
      'count': 0,
      'subServices': [
        for (final m in ['A', 'B']) {'name': '$name matter $m', 'slug': '$name-$m'.toLowerCase().replaceAll(' ', '-')},
      ],
    };

const _services = ['Civil Law', 'Criminal Law', 'Family Law'];

late ApiClient _api;
late _Adapter _adapter;
late String _currentPlan;
late Map<String, dynamic> _saved;

(int, Object) _server(RequestOptions o) {
  switch ('${o.method} ${o.path}') {
    case 'GET /api/dashboard/profile':
      return (
        200,
        {
          'advocate': {
            'name': 'Robin',
            'city': 'Gurgaon',
            'state': 'Haryana',
            'tagline': 'Corporate Lawyer',
            'about': 'Robin is a lawyer based in Gurgaon with over twenty years of experience.',
            'experience': 20,
            ..._saved,
          },
        }
      );
    case 'PUT /api/dashboard/profile':
      return (200, {'advocate': {'name': 'Robin', 'city': 'Gurgaon', 'state': 'Haryana'}});
    case 'GET /api/services':
      return (200, {'services': [for (final n in _services) _service(n)]});
    case 'GET /api/cities':
      return (
        200,
        {
          'cities': [
            for (final c in ['Delhi', 'Alwar', 'Mumbai', 'Gurgaon'])
              {'name': c, 'slug': c.toLowerCase(), 'state': 'X', 'image': '', 'count': 1},
          ],
        }
      );
    case 'GET /api/membership/plans':
      return (
        200,
        {
          'plans': [
            _plan('free', 'Starter', 0, areas: 2, matters: 4, cities: 2),
            _plan('professional', 'Professional', 199, areas: 5, matters: 10, cities: 5),
            _plan('premium', 'Premium', 499),
          ],
          'current': {'planId': _currentPlan, 'planName': _currentPlan, 'expiresAt': null, 'credits': <String, dynamic>{}},
        }
      );
  }
  return (404, {'error': 'unexpected'});
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    PathProviderPlatform.instance = _FakePathProvider();
    _api = await ApiClient.init();
  });

  setUp(() {
    _currentPlan = 'free';
    _saved = {
      'specializations': ['Civil Law', 'Criminal Law'],
      'subSpecializations': ['Civil Law matter A', 'Criminal Law matter B'],
      'practiceCities': ['Alwar'],
    };
    _adapter = _Adapter(_server);
    _api.raw.httpClientAdapter = _adapter;
  });

  Future<void> open(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 7000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    // Built and first-framed inside runAsync: the screen starts its reads on
    // that first frame, and the cookie jar's file I/O never completes inside the
    // fake-async zone a test body runs in.
    await tester.runAsync(() async {
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            Provider(create: (_) => DashboardService(_api)),
            Provider(create: (_) => ContentService(_api)),
            Provider(create: (_) => MembershipService(_api)),
            ChangeNotifierProvider(create: (_) => AuthController(AuthService(_api))),
          ],
          child: MaterialApp(theme: AppTheme.light(), home: const EditProfileScreen()),
        ),
      );
      await tester.pump();
      await Future<void>.delayed(const Duration(milliseconds: 400));
    });
    await tester.pump();
  }

  bool chosen(WidgetTester tester, String label) =>
      tester.widget<SelectableChip>(find.widgetWithText(SelectableChip, label)).selected;

  testWidgets('what was chosen in the onboarding shows as chosen, matters included', (tester) async {
    await open(tester);

    expect(chosen(tester, 'Civil Law'), isTrue);
    expect(chosen(tester, 'Criminal Law'), isTrue);
    expect(chosen(tester, 'Family Law'), isFalse);

    // The matters of the chosen areas are listed, and the saved ones are ticked.
    expect(chosen(tester, 'Civil Law matter A'), isTrue);
    expect(chosen(tester, 'Civil Law matter B'), isFalse);
    expect(chosen(tester, 'Criminal Law matter B'), isTrue);
    expect(find.widgetWithText(SelectableChip, 'Family Law matter A'), findsNothing,
        reason: 'matters are offered only under areas that are chosen');

    // A city from anywhere in the country, not only the lawyer's own state.
    final picker = find.byType(CityPicker);
    expect(find.descendant(of: picker, matching: find.text('Alwar')), findsOneWidget);
  });

  testWidgets('the city picker never offers the base city or one already chosen', (tester) async {
    final added = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: SingleChildScrollView(
            child: CityPicker(
              options: const ['Delhi', 'Gurgaon', 'Pune'],
              selected: const ['Pune'],
              baseCity: 'gurgaon',
              onAdd: added.add,
              onRemove: (_) {},
            ),
          ),
        ),
      ),
    );

    expect(find.widgetWithText(SelectableChip, 'Delhi'), findsOneWidget);
    expect(find.widgetWithText(SelectableChip, 'Gurgaon'), findsNothing);
    expect(find.widgetWithText(SelectableChip, 'Pune'), findsNothing);
    expect(find.text('Pune'), findsOneWidget, reason: 'the chosen one is a removable chip instead');

    await tester.tap(find.widgetWithText(SelectableChip, 'Delhi'));
    expect(added, ['Delhi']);
  });

  testWidgets('About is the last card, after everything that is picked', (tester) async {
    await open(tester);

    final cities = tester.getTopLeft(find.text('Cities you work in')).dy;
    final about = tester.getTopLeft(find.text('About').first).dy;
    final save = tester.getTopLeft(find.text('Save changes')).dy;
    final basics = tester.getTopLeft(find.text('Basics')).dy;

    expect(basics < cities, isTrue);
    expect(cities < about, isTrue);
    expect(about < save, isTrue);
  });

  testWidgets('a third area on Starter opens the plans instead of being added', (tester) async {
    await open(tester);

    await tester.tap(find.widgetWithText(SelectableChip, 'Family Law'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('Upgrade to add more'), findsOneWidget);
    expect(find.textContaining('Starter covers 2 practice areas'), findsOneWidget);
    expect(chosen(tester, 'Family Law'), isFalse);
  });

  testWidgets('Premium takes any number, and save sends the matters with the areas and cities', (tester) async {
    _currentPlan = 'premium';
    await open(tester);

    await tester.tap(find.widgetWithText(SelectableChip, 'Family Law'));
    await tester.pump();
    expect(find.text('Upgrade to add more'), findsNothing);
    expect(chosen(tester, 'Family Law'), isTrue);

    await tester.tap(find.widgetWithText(SelectableChip, 'Family Law matter B'));
    await tester.pump();

    await tester.ensureVisible(find.text('Save changes'));
    await tester.runAsync(() async {
      await tester.tap(find.text('Save changes'));
      await tester.pump();
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });
    await tester.pump();

    final put = _adapter.seen.lastWhere((o) => o.method == 'PUT' && o.path == '/api/dashboard/profile');
    final body = put.data as Map;
    expect(body['services'], ['Civil Law', 'Criminal Law', 'Family Law']);
    expect(body['subServices'], ['Civil Law matter A', 'Criminal Law matter B', 'Family Law matter B']);
    expect(body['practiceCities'], ['Alwar']);
  });
}
