import 'package:flutter/widgets.dart';

import '../plan_upgrade_sheet.dart';
import 'onboarding_controller.dart';

/// Runs a choice; if it is past what the lawyer's plan covers, opens the plans
/// right there over the screen, and once one is bought lifts the limit and tries
/// the choice again. The same behaviour the profile editor has always had — the
/// selections stay exactly as they are while the lawyer pays.
Future<void> pickOrUpgrade(
  BuildContext context,
  OnboardingController controller, {
  required PickResult Function() pick,
  required String Function() reason,
}) async {
  if (pick() == PickResult.ok) return;

  final catalog = controller.catalog;
  if (catalog == null) return;

  final upgraded = await PlanUpgradeSheet.open(context, catalog: catalog, reason: reason());
  if (!upgraded) return;

  await controller.reloadPlans();
  pick();
}
