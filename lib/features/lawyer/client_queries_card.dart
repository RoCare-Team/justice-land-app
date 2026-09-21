import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../state/queries_controller.dart';

/// Public legal problems waiting for a lawyer, as the loud card at the top of
/// Home: the count of clients waiting, the credits left (or what a plan would
/// open up, on Starter) and the newest problem in a line.
///
/// It is gold on navy — the theme's two colours — so it is the one thing on
/// Home that is not a white card. A tap anywhere opens the Queries tab.
class ClientQueriesCard extends StatelessWidget {
  const ClientQueriesCard({super.key});

  @override
  Widget build(BuildContext context) {
    final queries = context.watch<QueriesController>();
    final board = queries.board;
    final loaded = queries.loaded;
    final newest = loaded && !board.locked && board.open.isNotEmpty ? board.open.first : null;

    final String headline;
    final String detail;
    if (!loaded) {
      headline = 'Loading queries…';
      detail = 'Checking what clients are asking.';
    } else if (board.locked) {
      headline = board.openTotal > 0
          ? '${board.openTotal} ${board.openTotal == 1 ? 'client is' : 'clients are'} waiting for a lawyer'
          : 'Get client queries';
      detail = 'Professional gives 10 credits a month, Premium 25.';
    } else {
      headline = queries.openCount == 0
          ? 'No open queries right now'
          : '${queries.openCount} open ${queries.openCount == 1 ? 'query' : 'queries'} waiting';
      detail = '${board.credits.left} of ${board.credits.allowance} credits left this month';
    }

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color.lerp(AppColors.accent, Colors.white, 0.32)!,
            AppColors.accent,
          ],
        ),
        boxShadow: [
          BoxShadow(color: AppColors.accent.withValues(alpha: 0.32), blurRadius: 18, offset: const Offset(0, 8)),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(22),
        child: InkWell(
          borderRadius: BorderRadius.circular(22),
          onTap: () => context.go('/lawyer/queries'),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      height: 46,
                      width: 46,
                      decoration: const BoxDecoration(color: AppColors.primary, shape: BoxShape.circle),
                      child: const Icon(Icons.inbox_rounded, color: AppColors.accent, size: 24),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Client Queries',
                            style: TextStyle(
                              fontFamily: AppText.display,
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                              color: AppColors.primaryDark,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            headline,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 13.5,
                              height: 1.3,
                              fontWeight: FontWeight.w600,
                              color: AppColors.primaryDark,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (loaded && queries.openCount > 0) ...[
                      const SizedBox(width: 10),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(color: AppColors.primary, borderRadius: BorderRadius.circular(999)),
                        child: Text(
                          '${queries.openCount}',
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.accent),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 12),
                if (newest != null)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.55),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          newest.message,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 13.5, height: 1.4, color: AppColors.primaryDark),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          [
                            if (newest.category.isNotEmpty) newest.category,
                            if (newest.city.isNotEmpty) newest.city,
                            newest.age,
                          ].join(' · '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: AppColors.primaryDark.withValues(alpha: 0.7),
                          ),
                        ),
                      ],
                    ),
                  )
                else
                  Text(
                    detail,
                    style: TextStyle(fontSize: 12.5, color: AppColors.primaryDark.withValues(alpha: 0.75)),
                  ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    if (newest != null)
                      Expanded(
                        child: Text(
                          detail,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                            color: AppColors.primaryDark.withValues(alpha: 0.75),
                          ),
                        ),
                      )
                    else
                      const Spacer(),
                    const SizedBox(width: 10),
                    FilledButton.icon(
                      onPressed: () => context.go(loaded && board.locked ? '/lawyer/plan' : '/lawyer/queries'),
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: AppColors.accent,
                        minimumSize: const Size(0, 40),
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                      ),
                      icon: Icon(loaded && board.locked ? Icons.lock_open_rounded : Icons.arrow_forward_rounded, size: 18),
                      label: Text(loaded && board.locked ? 'Unlock' : 'View queries'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
