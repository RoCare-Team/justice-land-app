// The lawyer onboarding flow: the plan maths, category styling, validators, the
// controller's gating and save/pay flows against a stubbed server, and the two
// screens whose behaviour is worth pinning (categories and plans).

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:provider/provider.dart';

import 'package:flutter_legal_care/core/network/api_client.dart';
import 'package:flutter_legal_care/core/theme/app_theme.dart';
import 'package:flutter_legal_care/core/utils/validators.dart';
import 'package:flutter_legal_care/features/lawyer/onboarding/category_style.dart';
import 'package:flutter_legal_care/features/lawyer/onboarding/onboarding_controller.dart';
import 'package:flutter_legal_care/features/lawyer/onboarding/plan_fit.dart';
import 'package:flutter_legal_care/features/lawyer/onboarding/step_plan.dart';
import 'package:flutter_legal_care/features/lawyer/onboarding/step_specializations.dart';
import 'package:flutter_legal_care/models/legal_query.dart';
import 'package:flutter_legal_care/services/content_service.dart';
import 'package:flutter_legal_care/services/dashboard_service.dart';
import 'package:flutter_legal_care/services/membership_service.dart';
import 'package:flutter_legal_care/state/membership_checkout.dart';

class _FakePathProvider extends PathProviderPlatform with MockPlatformInterfaceMixin {
  @override
  Future<String?> getApplicationDocumentsPath() async => '.dart_tool/test_docs';
}

/// Answers from [handler] and remembers every request, so a test can check what
/// the app actually sent.
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

  List<RequestOptions> puts(String path) =>
      seen.where((o) => o.method == 'PUT' && o.path == path).toList();
}

class _FakeCheckout extends MembershipCheckout {
  _FakeCheckout(super.service, this.results);

  final List<PlanPurchaseResult> results;
  final List<String> bought = [];

  @override
  Future<PlanPurchaseResult> buy(String planId, {String planLabel = ''}) async {
    bought.add(planId);
    return results.removeAt(0);
  }

  @override
  void dispose() {}
}

Map<String, dynamic> _plan(
  String id,
  String name,
  int monthly, {
  int? areas,
  int? matters,
  int? cities,
  int total = 0,
}) =>
    {
      'id': id,
      'name': name,
      'tagline': '$name tagline',
      'monthly': monthly,
      'queryCredits': 0,
      'areas': areas,
      'matters': matters,
      'cities': cities,
      'placement': 'placement',
      'features': ['$name feature'],
      'price': {'base': total, 'gst': 0, 'total': total, 'monthly': monthly},
    };

Map<String, dynamic> _service(String name, List<String> matters) => {
      'name': name,
      'slug': name.toLowerCase().replaceAll(' ', '-'),
      'description': '',
      'count': 0,
      'subServices': [
        for (final m in matters) {'name': m, 'slug': m.toLowerCase().replaceAll(' ', '-')},
      ],
    };

const _serviceNames = [
  'Civil Law',
  'Criminal Law',
  'Family Law',
  'Property Law',
  'Corporate Law',
  'Tax Law',
  'Labour & Employment',
];

late ApiClient _api;
late _Adapter _adapter;
late _FakeCheckout _checkout;
late String _currentPlan;
late Map<String, dynamic> _pincodeAnswer;

(int, Object) _server(RequestOptions o) {
  final key = '${o.method} ${o.path}';
  switch (key) {
    case 'GET /api/dashboard/verification-documents':
      return (200, {'documents': <dynamic>[]});
    case 'GET /api/services':
      return (
        200,
        {
          'services': [for (final n in _serviceNames) _service(n, ['$n matter A', '$n matter B'])],
        }
      );
    case 'GET /api/cities':
      return (
        200,
        {
          'cities': [
            for (final c in ['Delhi', 'Mumbai', 'Gurgaon', 'Pune'])
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
            _plan('professional', 'Professional', 199, areas: 5, matters: 10, cities: 5, total: 2818),
            _plan('premium', 'Premium', 499, total: 7068),
          ],
          'current': {
            'planId': _currentPlan,
            'planName': _currentPlan,
            'expiresAt': null,
            'credits': <String, dynamic>{},
          },
        }
      );
    case 'GET /api/dashboard/payouts':
      return (200, {'bankAccounts': <dynamic>[]});
    case 'GET /api/pincode':
      return (200, _pincodeAnswer);
    case 'PUT /api/dashboard/profile':
      return (200, {'advocate': <String, dynamic>{}});
    case 'POST /api/dashboard/bank-accounts':
      return (
        201,
        {
          'ok': true,
          'account': {
            'id': 'acc1',
            'holderName': 'Asha Verma',
            'bankName': 'HDFC Bank',
            'ifsc': 'HDFC0001234',
            'accountLast4': '3456',
            'panLast4': '234F',
            'isPrimary': true,
          },
        }
      );
  }
  return (404, {'error': 'unexpected $key'});
}

Future<OnboardingController> _controller({
  List<PlanPurchaseResult> purchases = const [],
  List<String>? completed,
}) async {
  final membership = MembershipService(_api);
  _checkout = _FakeCheckout(membership, [...purchases]);
  final c = OnboardingController(
    dashboard: DashboardService(_api),
    content: ContentService(_api),
    membership: membership,
    advocate: null,
    refreshAuth: () async {},
    onCompleted: () async => completed?.add('done'),
    checkout: _checkout,
  );
  await c.load();
  return c;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    PathProviderPlatform.instance = _FakePathProvider();
    _api = await ApiClient.init();
  });

  setUp(() {
    _currentPlan = 'free';
    _pincodeAnswer = {'pincode': '122001', 'city': 'Gurgaon', 'state': 'Haryana'};
    _adapter = _Adapter(_server);
    _api.raw.httpClientAdapter = _adapter;
  });

  group('plan fit', () {
    MembershipPlan plan(int? areas, int? matters, int? cities) => MembershipPlan.fromJson(
          _plan('p', 'P', 100, areas: areas, matters: matters, cities: cities),
        );

    test('fits at exactly the limit, and always when the limit is open', () {
      expect(planFit(plan(2, 4, 2), areas: 2, matters: 4, cities: 2).fits, isTrue);
      expect(planFit(plan(null, null, null), areas: 6, matters: 40, cities: 30).fits, isTrue);
    });

    test('reports how far each choice is over', () {
      final fit = planFit(plan(2, 4, 2), areas: 5, matters: 4, cities: 3);
      expect(fit.fits, isFalse);
      expect(fit.areasOver, 3);
      expect(fit.mattersOver, 0);
      expect(fit.citiesOver, 1);
    });

    test('describes what a plan covers', () {
      expect(describePlanFit(plan(2, 4, 2), areas: 2, matters: 1, cities: 0), 'Covers everything you chose');
      expect(
        describePlanFit(plan(2, 4, 2), areas: 5, matters: 9, cities: 0),
        'Covers 2 of your 5 areas · 4 of your 9 matters',
      );
    });
  });

  group('category style', () {
    test('every real category gets its own fitting icon', () {
      const expected = {
        'Civil Law': Icons.balance_rounded,
        'Criminal Law': Icons.gavel_rounded,
        'Family Law': Icons.family_restroom_rounded,
        'Property Law': Icons.home_work_rounded,
        'Corporate Law': Icons.business_center_rounded,
        'Tax Law': Icons.receipt_long_rounded,
        'Labour & Employment': Icons.engineering_rounded,
        'Constitutional Law': Icons.account_balance_rounded,
        'Consumer Law': Icons.shopping_bag_rounded,
        'Intellectual Property': Icons.lightbulb_rounded,
        'Real Estate / RERA': Icons.apartment_rounded,
        'Immigration Law': Icons.flight_takeoff_rounded,
      };
      expected.forEach((name, icon) {
        expect(categoryIconFor(name), icon, reason: name);
      });
    });

    test('an unknown category still gets an icon', () {
      expect(categoryIconFor('Something New'), Icons.balance_rounded);
      expect(() => categoryIconFor(''), returnsNormally);
    });
  });

  group('theme', () {
    test('the onboarding screens use only the app palette', () {
      final files = Directory('lib/features/lawyer/onboarding')
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'));
      expect(files, isNotEmpty);
      for (final f in files) {
        final source = f.readAsStringSync();
        expect(source.contains('Color(0x'), isFalse, reason: '${f.path} hard-codes a colour');
        expect(source.contains('AppColors.info'), isFalse, reason: '${f.path} uses the off-theme info blue');
        expect(source.contains('Colors.blue'), isFalse, reason: '${f.path} uses a stock blue');
      }
    });
  });

  group('validators', () {
    test('IFSC', () {
      expect(Validators.isIfsc('HDFC0001234'), isTrue);
      expect(Validators.isIfsc('hdfc0001234'), isTrue);
      expect(Validators.isIfsc('HDFC1001234'), isFalse);
      expect(Validators.isIfsc('HDFC000123'), isFalse);
    });

    test('PAN', () {
      expect(Validators.isPan('ABCDE1234F'), isTrue);
      expect(Validators.isPan('abcde1234f'), isTrue);
      expect(Validators.isPan('ABCD1234EF'), isFalse);
      expect(Validators.isPan('ABCDE12345'), isFalse);
    });

    test('account number', () {
      expect(Validators.isAccountNumber('123456789'), isTrue);
      expect(Validators.isAccountNumber('1234 5678 9012'), isTrue);
      expect(Validators.isAccountNumber('12345678'), isFalse);
      expect(Validators.isAccountNumber('1234567890123456789'), isFalse);
      expect(Validators.isAccountNumber('12345678A'), isFalse);
    });
  });

  group('controller', () {
    test('loads the categories, cities and plans, and starts on Starter', () async {
      final c = await _controller();
      expect(c.loading, isFalse);
      expect(c.services.length, _serviceNames.length);
      expect(c.cityOptions, isNotEmpty);
      expect(c.selectedPlan?.id, 'free');
    });

    test('step 1 needs the Bar Council ID and both documents', () async {
      final c = await _controller();
      expect(c.canContinueVerification, isFalse);
      c.barCouncil.text = 'D/1234/2015';
      expect(c.canContinueVerification, isFalse);
      c.docs = {
        for (final d in OnboardingController.docKinds)
          d.kind: const VerificationDocument(id: 'x', kind: 'k', fileName: 'f.pdf', size: 1),
      };
      expect(c.canContinueVerification, isTrue);
    });

    test('step 2 allows one to six areas and drops matters with a deselected area', () async {
      final c = await _controller();
      expect(c.canContinueAreas, isFalse);

      for (var i = 0; i < OnboardingController.maxAreas; i++) {
        expect(c.toggleArea(c.services[i]), isTrue);
      }
      expect(c.canContinueAreas, isTrue);
      expect(c.toggleArea(c.services[6]), isFalse, reason: 'the seventh is refused');
      expect(c.areas.length, OnboardingController.maxAreas);

      c.toggleMatter('Civil Law matter A');
      c.toggleMatter('Criminal Law matter A');
      expect(c.mattersIn(c.services[0]), 1);
      c.toggleArea(c.services[0]);
      expect(c.matters, ['Criminal Law matter A']);
    });

    test('a PIN code fills the base city and state, and a city is never both base and extra', () async {
      final c = await _controller();
      c.toggleCity('Gurgaon');
      expect(c.cities, ['Gurgaon']);

      c.pincode.text = '122001';
      await pumpEventQueue();

      expect(c.baseCity, 'Gurgaon');
      expect(c.state, 'Haryana');
      expect(c.pincodeOk, isTrue);
      expect(c.cities, isEmpty, reason: 'the base city is already included');
      expect(c.popularCities, isNot(contains('Gurgaon')));
      expect(_adapter.seen.any((o) => o.path == '/api/pincode' && o.queryParameters['code'] == '122001'), isTrue);
    });

    test('step 3 is ready only once name, title, experience and a placed PIN are in', () async {
      final c = await _controller();
      c.fullName.text = 'Asha Verma';
      c.title.text = 'Senior Advocate';
      c.experience.text = '12';
      expect(c.canContinueProfile, isFalse);
      c.pincode.text = '122001';
      await pumpEventQueue();
      expect(c.canContinueProfile, isTrue);

      await c.continueProfile();
      expect(c.step, 3);
      final body = _adapter.puts('/api/dashboard/profile').single.data as Map;
      expect(body['fullName'], 'Asha Verma');
      expect(body['tagline'], 'Senior Advocate');
      expect(body['experience'], 12);
      expect(body['pincode'], '122001');
      expect(body['city'], 'Gurgaon');
      expect(body['state'], 'Haryana');
      expect(body.containsKey('photo'), isFalse);
    });

    test('step 4 sends the bank details with the PAN, and can be skipped', () async {
      final c = await _controller();
      expect(c.canContinueEarnings, isFalse);
      c.holder.text = 'Asha Verma';
      c.bankName.text = 'HDFC Bank';
      c.accountNumber.text = '1234 5678 3456';
      c.ifsc.text = 'hdfc0001234';
      expect(c.canContinueEarnings, isFalse, reason: 'PAN is required');
      c.pan.text = 'abcde1234f';
      expect(c.canContinueEarnings, isTrue);

      await c.continueEarnings();
      final post = _adapter.seen.singleWhere((o) => o.method == 'POST' && o.path == '/api/dashboard/bank-accounts');
      final body = post.data as Map;
      expect(body['accountNumber'], '123456783456');
      expect(body['ifsc'], 'HDFC0001234');
      expect(body['pan'], 'ABCDE1234F');
      expect(c.savedAccount?.accountLast4, '3456');
      expect(c.step, 4);
    });

    test('Skip for now moves on without saving anything', () async {
      final c = await _controller();
      c.skipEarnings();
      expect(c.step, 4);
      expect(_adapter.seen.where((o) => o.path == '/api/dashboard/bank-accounts'), isEmpty);
    });

    Future<OnboardingController> chosen({List<PlanPurchaseResult> purchases = const [], List<String>? done}) async {
      final c = await _controller(purchases: purchases, completed: done);
      c.toggleArea(c.services[0]);
      c.toggleArea(c.services[1]);
      c.toggleMatter('Civil Law matter A');
      c.toggleCity('Delhi');
      return c;
    }

    test('Starter that covers the choices saves them in one call and finishes', () async {
      final done = <String>[];
      final c = await chosen(done: done);
      await c.confirmPlan();

      expect(c.stage, OnboardingStage.done);
      expect(done, ['done']);
      final body = _adapter.puts('/api/dashboard/profile').single.data as Map;
      expect(body['services'], ['Civil Law', 'Criminal Law']);
      expect(body['subServices'], ['Civil Law matter A']);
      expect(body['practiceCities'], ['Delhi']);
    });

    test('Starter that is too small is refused with a way forward, and nothing is saved', () async {
      final c = await chosen();
      c.toggleArea(c.services[2]); // three areas > Starter's two
      await c.confirmPlan();

      expect(c.stage, OnboardingStage.idle);
      expect(c.error, contains('Starter'));
      expect(_adapter.puts('/api/dashboard/profile'), isEmpty);

      c.editChoices();
      expect(c.step, 1);
    });

    test('a paid plan is bought first, then the choices are saved', () async {
      final checkoutResults = [const PlanPurchaseResult(PlanPurchaseOutcome.success, 'ok', planName: 'Professional')];
      final c = await chosen(purchases: checkoutResults);
      c.toggleArea(c.services[2]);
      c.selectPlan('professional');
      _currentPlan = 'professional';

      await c.confirmPlan();

      expect(c.stage, OnboardingStage.done);
      expect(_checkout.bought, ['professional']);
      expect(_adapter.puts('/api/dashboard/profile').single.data, isA<Map>());
    });

    test('a cancelled payment leaves them on the step with a calm note and saves nothing', () async {
      final c = await chosen(purchases: [const PlanPurchaseResult(PlanPurchaseOutcome.cancelled, 'Payment cancelled.')]);
      c.selectPlan('professional');
      await c.confirmPlan();

      expect(c.stage, OnboardingStage.idle);
      expect(c.notice, isNotEmpty);
      expect(c.error, isEmpty);
      expect(_adapter.puts('/api/dashboard/profile'), isEmpty);
    });

    test('a failed payment shows the reason', () async {
      final c = await chosen(purchases: [const PlanPurchaseResult(PlanPurchaseOutcome.failed, 'Card declined.')]);
      c.selectPlan('professional');
      await c.confirmPlan();

      expect(c.stage, OnboardingStage.idle);
      expect(c.error, 'Card declined.');
    });

    test('a payment still confirming is not charged twice: trying again continues once the plan lands', () async {
      final c = await chosen(purchases: [const PlanPurchaseResult(PlanPurchaseOutcome.pending, 'Payment received.')]);
      c.selectPlan('professional');
      await c.confirmPlan();
      expect(c.stage, OnboardingStage.idle);
      expect(c.error, contains('Payment received.'));

      _currentPlan = 'professional'; // the webhook granted it meanwhile
      await c.confirmPlan();

      expect(c.stage, OnboardingStage.done);
      expect(_checkout.bought, ['professional'], reason: 'only one payment was opened');
    });
  });

  group('screens', () {
    Future<OnboardingController> loaded(WidgetTester tester) async {
      final c = (await tester.runAsync(_controller))!;
      addTearDown(c.dispose);
      return c;
    }

    Widget host(OnboardingController c, Widget child) => MaterialApp(
          theme: AppTheme.light(),
          home: ChangeNotifierProvider<OnboardingController>.value(value: c, child: child),
        );

    testWidgets('categories: cards toggle, the counter follows, the seventh is refused', (tester) async {
      await tester.binding.setSurfaceSize(const Size(420, 2600));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final c = await loaded(tester);
      await tester.pumpWidget(host(c, const StepSpecializations()));
      await tester.pump();

      expect(find.text('Civil Law'), findsOneWidget);
      expect(find.text('0/6'), findsOneWidget);

      await tester.tap(find.text('Civil Law'));
      await tester.pump();
      expect(find.text('1/6'), findsOneWidget);
      expect(find.text('Choose matters'), findsOneWidget);

      for (final n in ['Criminal Law', 'Family Law', 'Property Law', 'Corporate Law', 'Tax Law']) {
        await tester.tap(find.text(n));
        await tester.pump();
      }
      expect(find.text('6/6'), findsOneWidget);

      await tester.tap(find.text('Labour & Employment'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('You can choose up to 6 practice areas.'), findsOneWidget);
      expect(find.text('6/6'), findsOneWidget);
    });

    testWidgets('plans: shows ours, warns when Starter is too small, then unlocks with a bigger plan', (tester) async {
      await tester.binding.setSurfaceSize(const Size(420, 2600));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final c = await loaded(tester);
      for (var i = 0; i < 3; i++) {
        c.toggleArea(c.services[i]);
      }
      await tester.pumpWidget(host(c, const StepPlan()));
      await tester.pump();

      expect(find.text('Starter'), findsOneWidget);
      expect(find.text('Professional'), findsOneWidget);
      expect(find.text('Premium'), findsOneWidget);
      expect(find.text('Confirm plan selection'), findsNothing);

      // Starter is preselected and covers 2 of the 3 areas: Continue is locked.
      expect(find.text('Continue with Starter'), findsOneWidget);
      final button = tester.widget<FilledButton>(find.byType(FilledButton));
      expect(button.onPressed, isNull);

      await tester.tap(find.text('Professional'));
      await tester.pump();
      expect(find.textContaining('Pay '), findsOneWidget);
      expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed, isNotNull);
    });
  });
}
