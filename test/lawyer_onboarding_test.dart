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
import 'package:flutter_legal_care/services/auth_service.dart';
import 'package:flutter_legal_care/services/content_service.dart';
import 'package:flutter_legal_care/services/dashboard_service.dart';
import 'package:flutter_legal_care/services/membership_service.dart';
import 'package:flutter_legal_care/state/auth_controller.dart';
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

    test('step 2 drops matters with a deselected area', () async {
      final c = await _controller();
      expect(c.canContinueAreas, isFalse);

      expect(c.toggleArea(c.services[0]), PickResult.ok);
      expect(c.toggleArea(c.services[1]), PickResult.ok);
      expect(c.canContinueAreas, isTrue);

      c.toggleMatter('Civil Law matter A');
      c.toggleMatter('Criminal Law matter A');
      expect(c.mattersIn(c.services[0]), 1);
      c.toggleArea(c.services[0]);
      expect(c.matters, ['Criminal Law matter A']);
    });

    test('Starter holds a lawyer to 2 areas, 4 matters and 2 cities, and asks them to upgrade past it', () async {
      final c = await _controller();
      expect(c.currentPlan?.id, 'free');

      expect(c.toggleArea(c.services[0]), PickResult.ok);
      expect(c.toggleArea(c.services[1]), PickResult.ok);
      expect(c.toggleArea(c.services[2]), PickResult.needsUpgrade);
      expect(c.areas.length, 2, reason: 'the third is not added until a plan covers it');
      expect(c.areaUpgradeReason('Family Law'), contains('Starter covers 2 practice areas'));

      for (final m in ['a', 'b', 'c', 'd']) {
        expect(c.toggleMatter(m), PickResult.ok);
      }
      expect(c.toggleMatter('e'), PickResult.needsUpgrade);
      expect(c.matters.length, 4);

      expect(c.toggleCity('Delhi'), PickResult.ok);
      expect(c.toggleCity('Mumbai'), PickResult.ok);
      expect(c.toggleCity('Pune'), PickResult.needsUpgrade);
      expect(c.cities, ['Delhi', 'Mumbai']);
      expect(c.cityUpgradeReason('Pune'), contains('Starter covers 2 other cities'));

      // Taking one away is never refused, and frees the slot.
      expect(c.toggleArea(c.services[0]), PickResult.ok);
      expect(c.toggleArea(c.services[2]), PickResult.ok);
    });

    test('Professional covers 5 areas, 10 matters and 5 cities; Premium has no limit', () async {
      _currentPlan = 'professional';
      final c = await _controller();
      for (var i = 0; i < 5; i++) {
        expect(c.toggleArea(c.services[i]), PickResult.ok);
      }
      expect(c.toggleArea(c.services[5]), PickResult.needsUpgrade);

      _currentPlan = 'premium';
      final p = await _controller();
      for (final s in p.services) {
        expect(p.toggleArea(s), PickResult.ok);
      }
      for (var i = 0; i < 30; i++) {
        expect(p.toggleMatter('matter $i'), PickResult.ok);
      }
      for (var i = 0; i < 30; i++) {
        expect(p.toggleCity('City $i'), PickResult.ok);
      }
      expect(p.areas.length, _serviceNames.length);
    });

    test('paying lifts the limit: the plans are re-read and the refused pick then goes through', () async {
      final c = await _controller();
      c.toggleArea(c.services[0]);
      c.toggleArea(c.services[1]);
      expect(c.toggleArea(c.services[2]), PickResult.needsUpgrade);

      _currentPlan = 'professional'; // the upgrade sheet bought it
      await c.reloadPlans();

      expect(c.currentPlan?.id, 'professional');
      expect(c.selectedPlan?.id, 'professional', reason: 'the last step opens on the plan just bought');
      expect(c.toggleArea(c.services[2]), PickResult.ok);
      expect(c.areas.length, 3);
    });

    test('continuing from step 2 saves the areas and matters, and moves on', () async {
      final c = await _controller();
      c.toggleArea(c.services[0]);
      c.toggleMatter('Civil Law matter A');
      await c.continueAreas();

      expect(c.step, 2);
      final body = _adapter.puts('/api/dashboard/profile').single.data as Map;
      expect(body['services'], ['Civil Law']);
      expect(body['subServices'], ['Civil Law matter A']);
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
      expect(_adapter.seen.any((o) => o.path == '/api/pincode' && o.queryParameters['code'] == '122001'), isTrue);
    });

    test('step 3 is ready only once name, email, title, experience and a placed PIN are in', () async {
      final c = await _controller();
      c.fullName.text = 'Asha Verma';
      c.title.text = 'Senior Advocate';
      c.experience.text = '12';
      c.pincode.text = '122001';
      await pumpEventQueue();
      expect(c.canContinueProfile, isFalse, reason: 'the email is asked for here, not at sign-in');
      c.email.text = 'not an email';
      expect(c.canContinueProfile, isFalse);
      c.email.text = 'asha@example.com';
      expect(c.canContinueProfile, isTrue);

      c.toggleCity('Delhi');
      await c.continueProfile();
      expect(c.step, 3);
      final body = _adapter.puts('/api/dashboard/profile').single.data as Map;
      expect(body['fullName'], 'Asha Verma');
      expect(body['email'], 'asha@example.com');
      expect(body['practiceCities'], ['Delhi']);
      expect(body['tagline'], 'Senior Advocate');
      expect(body['experience'], 12);
      expect(body['pincode'], '122001');
      expect(body['city'], 'Gurgaon');
      expect(body['state'], 'Haryana');
      expect(body.containsKey('photo'), isFalse);
    });

    test('step 4 asks how they consult, and prices only what they offer', () async {
      final c = await _controller();
      expect(c.canContinueConsultations, isFalse, reason: 'no channel chosen yet');

      c.setOffersVideo(true);
      expect(c.canContinueConsultations, isFalse, reason: 'video needs a price');
      c.videoRate.text = '99999';
      expect(c.canContinueConsultations, isFalse, reason: 'outside the allowed range');
      c.videoRate.text = '50';
      expect(c.canContinueConsultations, isTrue);

      c.setOffersChat(true);
      c.chatRate.text = '20';
      c.setOffersInPerson(true);
      expect(c.canContinueConsultations, isFalse, reason: 'an in-person visit needs a fee');
      c.inPersonFee.text = '1000';
      expect(c.canContinueConsultations, isTrue);

      await c.continueConsultations();
      final body = _adapter.puts('/api/dashboard/profile').single.data as Map;
      expect(body['chatRate'], '20');
      expect(body['videoRate'], '50');
      expect(body['audioRate'], '0', reason: 'not offered');
      expect(body['fee'], '1000');
      expect(c.step, 4);
    });

    test('switching a channel off clears its price', () async {
      final c = await _controller();
      c.setOffersVideo(true);
      c.videoRate.text = '50';
      c.setOffersVideo(false);
      expect(c.videoRate.text, isEmpty);
      expect(c.canContinueConsultations, isFalse);
    });

    test('step 5 sends the bank details with the PAN, and can be skipped', () async {
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
      expect(c.step, 5);
    });

    test('Skip for now moves on without saving anything', () async {
      final c = await _controller();
      c.skipEarnings();
      expect(c.step, 5);
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

    test('confirming Starter, which already covers the choices, finishes without another save', () async {
      final done = <String>[];
      final c = await chosen(done: done);
      await c.confirmPlan();

      expect(c.stage, OnboardingStage.done);
      expect(done, ['done']);
      expect(_adapter.puts('/api/dashboard/profile'), isEmpty, reason: 'each step saved as it was completed');
    });

    test('choosing a smaller plan than the choices need is refused with a way forward', () async {
      _currentPlan = 'professional';
      final c = await _controller();
      for (var i = 0; i < 3; i++) {
        c.toggleArea(c.services[i]);
      }
      c.selectPlan('free'); // three areas > Starter's two
      await c.confirmPlan();

      expect(c.stage, OnboardingStage.idle);
      expect(c.error, contains('Starter'));

      c.editChoices();
      expect(c.step, 1);
    });

    test('a paid plan is bought, then onboarding finishes', () async {
      final checkoutResults = [const PlanPurchaseResult(PlanPurchaseOutcome.success, 'ok', planName: 'Professional')];
      final done = <String>[];
      final c = await chosen(purchases: checkoutResults, done: done);
      c.selectPlan('professional');
      _currentPlan = 'professional';

      await c.confirmPlan();

      expect(c.stage, OnboardingStage.done);
      expect(_checkout.bought, ['professional']);
      expect(done, ['done']);
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

    Widget host(OnboardingController c, Widget child) => MultiProvider(
          providers: [
            Provider<MembershipService>.value(value: c.membership),
            ChangeNotifierProvider(create: (_) => AuthController(AuthService(_api))),
          ],
          child: MaterialApp(
            theme: AppTheme.light(),
            home: ChangeNotifierProvider<OnboardingController>.value(value: c, child: child),
          ),
        );

    testWidgets('categories: the counter shows the plan, and a third area on Starter opens the upgrade sheet', (tester) async {
      await tester.binding.setSurfaceSize(const Size(420, 2600));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final c = await loaded(tester);
      await tester.pumpWidget(host(c, const StepSpecializations()));
      await tester.pump();

      expect(find.text('Civil Law'), findsOneWidget);
      expect(find.text('0/2'), findsOneWidget);
      expect(find.textContaining('Starter plan covers 2 practice areas'), findsOneWidget);

      await tester.tap(find.text('Civil Law'));
      await tester.pump();
      expect(find.text('1/2'), findsOneWidget);
      expect(find.text('Choose matters'), findsOneWidget);

      await tester.tap(find.text('Criminal Law'));
      await tester.pump();
      expect(find.text('2/2'), findsOneWidget);
      expect(find.text('Upgrade to add more'), findsNothing);

      await tester.tap(find.text('Family Law'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.text('Upgrade to add more'), findsOneWidget);
      expect(find.textContaining('Starter covers 2 practice areas'), findsOneWidget);
      expect(find.text('Professional'), findsOneWidget);
      expect(find.text('Premium'), findsOneWidget);
      expect(c.areas, ['Civil Law', 'Criminal Law'], reason: 'nothing is added until a plan covers it');

      // Closing the sheet without paying leaves the selection as it was.
      await tester.tap(find.byIcon(Icons.close_rounded).last);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Upgrade to add more'), findsNothing);
      expect(find.text('2/2'), findsOneWidget);
    });

    testWidgets('categories: Premium shows no limit and takes every area', (tester) async {
      await tester.binding.setSurfaceSize(const Size(420, 2600));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      _currentPlan = 'premium';
      final c = await loaded(tester);
      await tester.pumpWidget(host(c, const StepSpecializations()));
      await tester.pump();

      expect(find.text('0/∞'), findsOneWidget);
      for (final n in ['Civil Law', 'Criminal Law', 'Family Law']) {
        await tester.tap(find.text(n));
        await tester.pump();
      }
      expect(find.text('3/∞'), findsOneWidget);
      expect(find.text('Upgrade to add more'), findsNothing);
    });

    testWidgets('plans: shows ours, warns when the plan is too small, then unlocks with a bigger one', (tester) async {
      await tester.binding.setSurfaceSize(const Size(420, 2600));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      _currentPlan = 'professional';
      final c = await loaded(tester);
      for (var i = 0; i < 3; i++) {
        c.toggleArea(c.services[i]);
      }
      c.selectPlan('free');
      await tester.pumpWidget(host(c, const StepPlan()));
      await tester.pump();

      expect(find.text('Starter'), findsOneWidget);
      expect(find.text('Professional'), findsOneWidget);
      expect(find.text('Premium'), findsOneWidget);
      expect(find.text('Confirm plan selection'), findsNothing);

      // Starter is selected and covers 2 of the 3 areas: Continue is locked.
      expect(find.text('Continue with Starter'), findsOneWidget);
      final button = tester.widget<FilledButton>(find.byType(FilledButton));
      expect(button.onPressed, isNull);

      await tester.tap(find.text('Premium'));
      await tester.pump();
      expect(find.textContaining('Pay '), findsOneWidget);
      expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed, isNotNull);
    });
  });
}
