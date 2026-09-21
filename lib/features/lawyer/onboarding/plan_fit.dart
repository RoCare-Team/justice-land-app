import '../../../models/legal_query.dart';

/// How a plan measures up against what a lawyer has chosen in onboarding.
///
/// The plan is settled on the last step, after the areas, matters and cities are
/// picked — so the choices are never cut off while they are being made. This is
/// the check that closes the loop: it says how far each choice is over the plan's
/// ceiling (0 when it fits). The server holds the same limits on save.
class PlanFit {
  const PlanFit({
    required this.areasOver,
    required this.mattersOver,
    required this.citiesOver,
  });

  final int areasOver;
  final int mattersOver;
  final int citiesOver;

  bool get fits => areasOver == 0 && mattersOver == 0 && citiesOver == 0;
}

/// [cities] counts the cities *besides* the lawyer's own base city, which never
/// counts against the allowance (the server does it the same way).
PlanFit planFit(
  MembershipPlan plan, {
  required int areas,
  required int matters,
  required int cities,
}) {
  int over(int? limit, int n) => limit == null || n <= limit ? 0 : n - limit;
  return PlanFit(
    areasOver: over(plan.areas, areas),
    mattersOver: over(plan.matters, matters),
    citiesOver: over(plan.cities, cities),
  );
}

/// One line for a plan card: what it covers of the lawyer's choices.
String describePlanFit(
  MembershipPlan plan, {
  required int areas,
  required int matters,
  required int cities,
}) {
  final fit = planFit(plan, areas: areas, matters: matters, cities: cities);
  if (fit.fits) return 'Covers everything you chose';

  final parts = <String>[];
  if (fit.areasOver > 0) {
    parts.add('${plan.areas} of your $areas ${areas == 1 ? 'area' : 'areas'}');
  }
  if (fit.mattersOver > 0) {
    parts.add('${plan.matters} of your $matters ${matters == 1 ? 'matter' : 'matters'}');
  }
  if (fit.citiesOver > 0) {
    parts.add('${plan.cities} of your $cities ${cities == 1 ? 'city' : 'cities'}');
  }
  return 'Covers ${parts.join(' · ')}';
}
