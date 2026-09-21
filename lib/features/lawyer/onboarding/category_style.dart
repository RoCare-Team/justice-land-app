import 'package:flutter/material.dart';

/// Keyword → icon. First match wins, so the more specific words ("real estate",
/// "intellectual") sit above the general ones ("property").
///
/// Colour is deliberately not part of this: every category is drawn in the app's
/// navy and gold, so the icon alone tells the areas apart and the screen stays in
/// the theme.
const List<(List<String>, IconData)> _rules = [
  (['real estate', 'rera', 'builder', 'housing'], Icons.apartment_rounded),
  (['intellectual', 'patent', 'trademark', 'copyright'], Icons.lightbulb_rounded),
  (['criminal', 'bail', 'cbi', 'police'], Icons.gavel_rounded),
  (['family', 'divorce', 'matrimon', 'marriage', 'custody'], Icons.family_restroom_rounded),
  (['property', 'land', 'revenue'], Icons.home_work_rounded),
  (['corporate', 'company', 'business', 'startup', 'commercial'], Icons.business_center_rounded),
  (['tax', 'gst', 'income'], Icons.receipt_long_rounded),
  (['labour', 'labor', 'employment', 'service law'], Icons.engineering_rounded),
  (['constitution', 'writ', 'public interest'], Icons.account_balance_rounded),
  (['consumer'], Icons.shopping_bag_rounded),
  (['immigration', 'visa', 'passport'], Icons.flight_takeoff_rounded),
  (['cyber', 'information technology', 'data protection'], Icons.shield_rounded),
  (['bank', 'loan', 'recovery', 'cheque', 'nclt', 'insolvency'], Icons.account_balance_wallet_rounded),
  (['arbitration', 'mediation', 'contract'], Icons.handshake_rounded),
  (['motor', 'accident', 'insurance'], Icons.car_crash_rounded),
  (['medical', 'health'], Icons.medical_services_rounded),
  (['education', 'university'], Icons.school_rounded),
  (['environment', 'forest'], Icons.eco_rounded),
];

/// The icon for a practice area. Anything the rules do not know gets the scales,
/// so a category added on the server tomorrow still looks intentional.
IconData categoryIconFor(String name) {
  final n = name.toLowerCase();
  for (final (words, icon) in _rules) {
    if (words.any(n.contains)) return icon;
  }
  return Icons.balance_rounded;
}
