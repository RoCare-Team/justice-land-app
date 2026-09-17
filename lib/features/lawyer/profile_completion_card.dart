import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/network/api_exception.dart';
import '../../core/theme/app_theme.dart';
import '../../services/dashboard_service.dart';
import 'lawyer_widgets.dart';

/// "Profile 64% complete" — the same score the web dashboard shows, with the
/// next few things to add. Tapping opens the profile editor.
///
/// [hideWhenComplete] is for the home screen, where a finished profile needs
/// no reminder; the Profile tab always shows the score.
class ProfileCompletionCard extends StatefulWidget {
  const ProfileCompletionCard({super.key, this.hideWhenComplete = false});

  final bool hideWhenComplete;

  @override
  State<ProfileCompletionCard> createState() => ProfileCompletionCardState();
}

class ProfileCompletionCardState extends State<ProfileCompletionCard> {
  ProfileCompletion? _completion;

  @override
  void initState() {
    super.initState();
    reload();
  }

  /// Re-reads the score — call after the profile may have changed.
  Future<void> reload() async {
    try {
      final c = await context.read<DashboardService>().completion();
      if (mounted) setState(() => _completion = c);
    } on ApiException {
      // Leave the last known score; the card is a nudge, not a gate.
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = _completion;
    if (c == null || (widget.hideWhenComplete && c.percent >= 100)) {
      return const SizedBox.shrink();
    }
    final complete = c.percent >= 100;
    final color = complete
        ? AppColors.success
        : c.percent >= 60
            ? AppColors.info
            : AppColors.warning;

    return LCard(
      onTap: () async {
        await context.push('/dashboard/profile');
        reload();
      },
      child: Row(
        children: [
          SizedBox(
            height: 58,
            width: 58,
            child: Stack(
              alignment: Alignment.center,
              children: [
                SizedBox.expand(
                  child: CircularProgressIndicator(
                    value: c.percent / 100,
                    strokeWidth: 6,
                    backgroundColor: AppColors.ink.withValues(alpha: 0.08),
                    color: color,
                  ),
                ),
                Text('${c.percent}%', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800)),
              ],
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  complete ? 'Profile complete' : 'Profile ${c.percent}% complete',
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 3),
                Text(
                  complete
                      ? 'All ${c.total} sections filled — clients see your full profile.'
                      : '${c.done} of ${c.total} done. Add: ${c.missing.take(2).map((m) => m.label.toLowerCase()).join(', ')}'
                          '${c.missing.length > 2 ? ' +${c.missing.length - 2} more' : ''}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12.5, height: 1.35, color: AppColors.inkMuted),
                ),
              ],
            ),
          ),
          Icon(Icons.chevron_right_rounded, color: AppColors.inkFaint),
        ],
      ),
    );
  }
}
