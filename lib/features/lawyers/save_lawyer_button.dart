import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../core/widgets/states.dart';
import '../../models/advocate.dart';
import '../../state/saved_lawyers_controller.dart';

/// The heart, wherever a lawyer is shown.
///
/// It carries its own state rather than taking a flag and a callback, because
/// it appears on three different lists and a profile header, and every one of
/// those call sites used to pass nothing at all — which left the heart drawn
/// but dead under the finger.
class SaveLawyerButton extends StatelessWidget {
  const SaveLawyerButton({
    super.key,
    required this.advocate,
    this.size = 18,
    this.onDark = false,
  });

  final Advocate advocate;
  final double size;

  /// For the navy profile header, where an outline in ink would vanish.
  final bool onDark;

  @override
  Widget build(BuildContext context) {
    final saved = context.select<SavedLawyersController, bool>(
      (c) => c.isSaved(advocate.id),
    );

    return IconButton(
      padding: EdgeInsets.zero,
      iconSize: size,
      visualDensity: VisualDensity.compact,
      tooltip: saved ? 'Remove from saved' : 'Save this lawyer',
      onPressed: () async {
        final nowSaved =
            await context.read<SavedLawyersController>().toggle(advocate);
        if (!context.mounted) return;
        Toast.show(
          context,
          nowSaved ? 'Saved to your list.' : 'Removed from your saved list.',
        );
      },
      icon: Icon(
        saved ? Icons.favorite_rounded : Icons.favorite_border_rounded,
        color: saved
            ? const Color(0xFFEF4444)
            : onDark
                ? Colors.white.withValues(alpha: 0.85)
                : AppColors.ink.withValues(alpha: 0.28),
      ),
    );
  }
}
