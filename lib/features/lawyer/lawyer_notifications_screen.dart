import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/common.dart';
import '../../state/auth_controller.dart';
import '../../state/lawyer_controller.dart';
import 'lawyer_widgets.dart';

enum _Kind { consultation, payment, system }

typedef _Note = ({_Kind kind, IconData icon, Color color, String title, String body, DateTime? at, String? route});

/// Notifications, built from what actually happened on the account: requests
/// waiting, consultations completed, money credited, reviews left, and where
/// the profile stands. There is no separate notification store on the server,
/// so nothing here can say something the account itself does not.
class LawyerNotificationsScreen extends StatefulWidget {
  const LawyerNotificationsScreen({super.key});

  @override
  State<LawyerNotificationsScreen> createState() => _LawyerNotificationsScreenState();
}

class _LawyerNotificationsScreenState extends State<LawyerNotificationsScreen> {
  _Kind? _filter;

  @override
  Widget build(BuildContext context) {
    final lawyer = context.watch<LawyerController>();
    final advocate = context.watch<AuthController>().advocate;

    final notes = <_Note>[
      for (final s in lawyer.pending)
        (
          kind: _Kind.consultation,
          icon: Icons.notifications_active_rounded,
          color: AppColors.accent,
          title: 'New Consultation Request',
          body: '${s.userName.isEmpty ? 'A client' : s.userName} wants a ${s.type.label.toLowerCase()} with you.',
          at: s.createdAt,
          route: '/lawyer/client/${s.userId}',
        ),
      for (final s in lawyer.history.where((c) => c.charged).take(20))
        (
          kind: _Kind.consultation,
          icon: Icons.task_alt_rounded,
          color: AppColors.info,
          title: 'Consultation Completed',
          body: '${s.type.label} with ${s.userName.isEmpty ? 'a client' : s.userName} · ${s.talkedMinutes} mins',
          at: s.happenedAt,
          route: '/lawyer/client/${s.userId}',
        ),
      for (final t in lawyer.earnings.transactions.take(20))
        (
          kind: _Kind.payment,
          icon: t.isCredit ? Icons.currency_rupee_rounded : Icons.north_east_rounded,
          color: t.isCredit ? AppColors.success : AppColors.danger,
          title: t.isCredit ? 'Payment Received' : 'Wallet Debit',
          body: '${Fmt.money(t.amount)} ${t.isCredit ? 'credited to' : 'debited from'} your wallet${t.note.isEmpty ? '' : ' — ${t.note}'}',
          at: t.createdAt,
          route: '/lawyer/earnings',
        ),
      if (advocate != null)
        for (final r in advocate.reviewsList.take(10))
          (
            kind: _Kind.system,
            icon: Icons.star_rounded,
            color: const Color(0xFFF59E0B),
            title: 'New Review',
            body: '${r.author.isEmpty ? 'A client' : r.author} gave you ${r.rating} stars.',
            at: r.createdAt,
            route: null,
          ),
      if (advocate != null)
        (
          kind: _Kind.system,
          icon: advocate.isPublished ? Icons.verified_rounded : Icons.hourglass_top_rounded,
          color: advocate.isPublished ? AppColors.info : AppColors.warning,
          title: advocate.isPublished ? 'Profile Live' : 'Profile Under Review',
          body: advocate.isPublished
              ? 'Your profile is public and clients can find you.'
              : 'Our team is reviewing your profile. It goes live once approved.',
          at: null,
          route: '/dashboard/profile',
        ),
    ]..sort((a, b) {
        // Undated items (the profile status) sit at the top.
        if (a.at == null) return -1;
        if (b.at == null) return 1;
        return b.at!.compareTo(a.at!);
      });

    final shown = _filter == null ? notes : notes.where((n) => n.kind == _filter).toList();

    return LawyerPage(
      title: 'Notifications',
      body: Column(
        children: [
          Container(
            color: AppColors.surface,
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final (kind, label) in [
                    (null, 'All'),
                    (_Kind.consultation, 'Consultations'),
                    (_Kind.payment, 'Payments'),
                    (_Kind.system, 'System'),
                  ])
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: SelectableChip(
                        label: label,
                        selected: _filter == kind,
                        onTap: () => setState(() => _filter = kind),
                      ),
                    ),
                ],
              ),
            ),
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: lawyer.refreshAll,
              child: shown.isEmpty
                  ? ListView(
                      padding: const EdgeInsets.all(16),
                      children: const [
                        EmptyCard(icon: Icons.notifications_off_outlined, title: 'Nothing here yet'),
                      ],
                    )
                  : ListView.separated(
                      padding: EdgeInsets.fromLTRB(16, 14, 16, bottomGutter(context)),
                      itemCount: shown.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (context, i) {
                        final n = shown[i];
                        return LCard(
                          padding: const EdgeInsets.all(12),
                          onTap: n.route == null ? null : () => context.push(n.route!),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                height: 40,
                                width: 40,
                                decoration: BoxDecoration(color: n.color.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(12)),
                                child: Icon(n.icon, color: n.color, size: 21),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Expanded(
                                          child: Text(n.title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                                        ),
                                        if (n.at != null)
                                          Text(Fmt.timeAgo(n.at), style: TextStyle(fontSize: 11, color: AppColors.inkFaint)),
                                      ],
                                    ),
                                    const SizedBox(height: 2),
                                    Text(n.body, style: TextStyle(fontSize: 12.5, height: 1.35, color: AppColors.inkMuted)),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
            ),
          ),
        ],
      ),
    );
  }
}
