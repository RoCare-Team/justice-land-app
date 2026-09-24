import 'package:flutter/material.dart';

import '../../models/advocate.dart';

/// The Silver / Gold badge a paid membership buys.
///
/// Both plans are sold on it — "Silver badge on your profile", "Gold badge on
/// your profile" — so it has to appear everywhere a lawyer is shown publicly,
/// which on the website means the directory cards and the profile header. The
/// app was showing neither, so a lawyer paying ₹499 looked exactly like one on
/// the free plan.
///
/// Gold for the ₹499 plan, silver for the ₹199 one: the same ladder the
/// pricing page sells, so a client reads the same ranking in both places.
/// Starter shows nothing — a badge everyone has is not a badge — and a lapsed
/// plan reads as Starter through [Advocate.paidPlanId], so the badge goes the
/// day the membership does.
class PlanTierBadge extends StatelessWidget {
  const PlanTierBadge({super.key, required this.advocate, this.compact = false});

  final Advocate advocate;

  /// For directory cards, where the name beside it needs the room.
  final bool compact;

  static const Color _goldInk = Color(0xFF8A6D1E);
  static const Color _goldIcon = Color(0xFFB8901F);
  static const Color _goldEdge = Color(0xFFD4AF37);
  static const Color _silverInk = Color(0xFF475569);
  static const Color _silverEdge = Color(0xFFCBD5E1);

  @override
  Widget build(BuildContext context) {
    final tier = advocate.paidPlanId;
    if (tier.isEmpty) return const SizedBox.shrink();

    final gold = tier == 'premium';
    final ink = gold ? _goldInk : _silverInk;

    return Container(
      padding: EdgeInsets.symmetric(horizontal: compact ? 6 : 9, vertical: compact ? 2 : 4),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: gold
              ? const [Color(0xFFF7EDCB), Color(0xFFE8D28A)]
              : const [Color(0xFFF1F5F9), Color(0xFFE2E8F0)],
        ),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: (gold ? _goldEdge : _silverEdge).withValues(alpha: 0.6)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            gold ? Icons.workspace_premium_rounded : Icons.auto_awesome_rounded,
            size: compact ? 11 : 14,
            color: gold ? _goldIcon : _silverInk,
          ),
          const SizedBox(width: 3),
          Text(
            gold ? 'Gold' : 'Silver',
            style: TextStyle(
              fontSize: compact ? 10.5 : 12,
              fontWeight: FontWeight.w700,
              color: ink,
            ),
          ),
        ],
      ),
    );
  }
}
