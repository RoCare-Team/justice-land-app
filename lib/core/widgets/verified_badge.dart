import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// "Verified" — shown beside a lawyer an admin has verified.
///
/// A labelled pill rather than a bare tick: clients read the word, and a tick
/// on its own is easy to miss or mistake for decoration. [onDark] is for the
/// navy headers, [compact] for directory cards where space is tight.
class VerifiedBadge extends StatelessWidget {
  const VerifiedBadge({super.key, this.compact = false, this.onDark = false});

  final bool compact;
  final bool onDark;

  static const Color _green = Color(0xFF059669);

  @override
  Widget build(BuildContext context) {
    final fg = onDark ? Colors.white : _green;
    final bg = onDark ? Colors.white.withValues(alpha: 0.16) : const Color(0xFFD1FAE5);
    return Container(
      padding: EdgeInsets.symmetric(horizontal: compact ? 6 : 8, vertical: compact ? 2 : 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: fg.withValues(alpha: onDark ? 0.35 : 0.25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.verified_rounded, size: compact ? 12 : 14, color: onDark ? AppColors.accent : fg),
          const SizedBox(width: 3),
          Text(
            'Verified',
            style: TextStyle(fontSize: compact ? 10.5 : 12, fontWeight: FontWeight.w700, color: fg),
          ),
        ],
      ),
    );
  }
}

/// The lawyer's own view of a profile not yet verified.
class VerificationPendingBadge extends StatelessWidget {
  const VerificationPendingBadge({super.key, this.onDark = false});

  final bool onDark;

  @override
  Widget build(BuildContext context) {
    final fg = onDark ? Colors.white70 : AppColors.warning;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: onDark ? Colors.white.withValues(alpha: 0.1) : AppColors.warningSoft,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.hourglass_top_rounded, size: 13, color: fg),
          const SizedBox(width: 3),
          Text('Verification pending', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: fg)),
        ],
      ),
    );
  }
}
