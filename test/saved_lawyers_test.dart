// The heart and the plan badge on a lawyer's card.
//
// Both were reported missing from the app: the badge never drawn at all, and
// the heart drawn but dead because every call site left its callback null.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flutter_legal_care/core/widgets/plan_tier_badge.dart';
import 'package:flutter_legal_care/features/lawyers/advocate_card.dart';
import 'package:flutter_legal_care/models/advocate.dart';
import 'package:flutter_legal_care/state/saved_lawyers_controller.dart';

Advocate lawyer({
  String id = 'a1',
  String name = 'Adv. Robin Sharma',
  String planId = 'free',
  bool verified = false,
  DateTime? expires,
}) =>
    Advocate.fromJson({
      'id': id,
      'name': name,
      'slug': 'robin-sharma',
      'profilePath': 'advocate-robin-sharma-jusld07',
      'city': 'Lucknow',
      'chatRate': 20,
      'audioRate': 25,
      'videoRate': 40,
      'planId': planId,
      'verified': verified,
      if (expires != null) 'planExpiresAt': expires.toIso8601String(),
    });

Future<void> pumpCard(WidgetTester tester, Advocate advocate,
    SavedLawyersController saved, {double width = 380}) async {
  await tester.pumpWidget(
    ChangeNotifierProvider.value(
      value: saved,
      child: MaterialApp(
        home: Scaffold(
          body: SizedBox(width: width, child: AdvocateCard(advocate: advocate)),
        ),
      ),
    ),
  );
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('plan badge', () {
    test('a paid plan counts only until the day it expires', () {
      final tomorrow = DateTime.now().add(const Duration(days: 1));
      final yesterday = DateTime.now().subtract(const Duration(days: 1));

      expect(lawyer(planId: 'premium', expires: tomorrow).paidPlanId, 'premium');
      expect(lawyer(planId: 'professional', expires: tomorrow).paidPlanId,
          'professional');
      // Lapsed reads as Starter, exactly as the website's activePlan does.
      expect(lawyer(planId: 'premium', expires: yesterday).paidPlanId, '');
      expect(lawyer(planId: 'free').paidPlanId, '');
      // Granted by an admin with no end date: still a paid plan.
      expect(lawyer(planId: 'premium').paidPlanId, 'premium');
    });

    testWidgets('₹499 shows Gold, ₹199 shows Silver, Starter shows neither',
        (tester) async {
      final saved = SavedLawyersController();
      final until = DateTime.now().add(const Duration(days: 30));

      await pumpCard(tester, lawyer(planId: 'premium', expires: until), saved);
      expect(find.text('Gold'), findsOneWidget);

      await pumpCard(
          tester, lawyer(planId: 'professional', expires: until), saved);
      expect(find.text('Silver'), findsOneWidget);
      expect(find.text('Gold'), findsNothing);

      await pumpCard(tester, lawyer(), saved);
      expect(find.byType(PlanTierBadge), findsNothing);
    });

    testWidgets('both badges and a long name fit a narrow phone',
        (tester) async {
      // The name row now carries the verified pill, the plan badge and the
      // heart. On a 320-wide screen that is the tightest it ever gets, and an
      // overflow here would fail this test rather than reach a handset.
      await pumpCard(
        tester,
        lawyer(
          name: 'Adv. Gajendra Prasad Sharma Chaturvedi',
          planId: 'premium',
          verified: true,
          expires: DateTime.now().add(const Duration(days: 30)),
        ),
        SavedLawyersController(),
        width: 320,
      );
      expect(find.text('Gold'), findsOneWidget);
      expect(find.text('Verified'), findsOneWidget);
    });
  });

  group('the heart', () {
    testWidgets('saves on the first tap and unsaves on the second',
        (tester) async {
      final saved = SavedLawyersController();
      await saved.load();
      await pumpCard(tester, lawyer(), saved);

      expect(find.byIcon(Icons.favorite_border_rounded), findsOneWidget);

      await tester.tap(find.byIcon(Icons.favorite_border_rounded));
      await tester.pump();
      expect(find.byIcon(Icons.favorite_rounded), findsOneWidget);
      expect(saved.isSaved('a1'), isTrue);

      await tester.tap(find.byIcon(Icons.favorite_rounded));
      await tester.pump();
      expect(find.byIcon(Icons.favorite_border_rounded), findsOneWidget);
      expect(saved.isSaved('a1'), isFalse);
    });

    testWidgets('what was saved is still there on the next launch',
        (tester) async {
      final first = SavedLawyersController();
      await first.load();
      await first.toggle(lawyer(name: 'Adv. Gajender Sharma'));

      // A fresh controller reads the same device storage.
      final next = SavedLawyersController();
      await next.load();
      expect(next.count, 1);
      expect(next.items.single.name, 'Adv. Gajender Sharma');
      expect(next.items.single.path, 'advocate-robin-sharma-jusld07');

      await pumpCard(tester, lawyer(), next);
      expect(find.byIcon(Icons.favorite_rounded), findsOneWidget);
    });

    test('the newest save is first, and saving twice does not duplicate', () async {
      final saved = SavedLawyersController();
      await saved.load();
      await saved.toggle(lawyer(id: 'a1', name: 'First'));
      await saved.toggle(lawyer(id: 'a2', name: 'Second'));

      expect(saved.items.map((s) => s.id).toList(), ['a2', 'a1']);

      await saved.toggle(lawyer(id: 'a1', name: 'First'));
      expect(saved.count, 1);
      await saved.toggle(lawyer(id: 'a1', name: 'First'));
      expect(saved.count, 2);
      expect(saved.items.first.id, 'a1');
    });
  });
}
