import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/states.dart';
import '../../models/consultation.dart';
import '../../state/lawyer_controller.dart';
import 'lawyer_widgets.dart';

/// Consultation requests: what is waiting, what was missed, what was answered.
/// A running session is not here — Home's "Active Consultations" carries it.
class LawyerRequestsScreen extends StatefulWidget {
  const LawyerRequestsScreen({super.key, this.initialTab});

  /// `missed` opens on the Missed tab — the missed-call notification's tap.
  final String? initialTab;

  @override
  State<LawyerRequestsScreen> createState() => _LawyerRequestsScreenState();
}

class _LawyerRequestsScreenState extends State<LawyerRequestsScreen> {
  static const _missedTab = 1;

  int _tab = 0;

  @override
  void initState() {
    super.initState();
    _openRequestedTab();
  }

  @override
  void didUpdateWidget(LawyerRequestsScreen old) {
    super.didUpdateWidget(old);
    // Already on this screen when the notification was tapped.
    if (widget.initialTab != old.initialTab) _openRequestedTab();
  }

  void _openRequestedTab() {
    if (widget.initialTab != 'missed') return;
    _tab = _missedTab;
    // The history is only re-read every 45 seconds; the call just missed
    // should be in the list when the tab opens.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<LawyerController>().refreshHistory();
    });
  }

  @override
  Widget build(BuildContext context) {
    final lawyer = context.watch<LawyerController>();
    final pending = lawyer.pending;
    // Newest first. A request that was withdrawn or ran out before it was
    // answered is a missed one; everything else over is answered.
    final over = lawyer.history.where((c) => c.status.isOver);
    final missed = over.where((c) => c.status == ConsultationStatus.cancelled).toList();
    final answered = over.where((c) => c.status != ConsultationStatus.cancelled).toList();

    final lists = [pending, missed, answered];
    final labels = ['Pending (${pending.length})', 'Missed', 'Answered'];
    final shown = lists[_tab];

    return Scaffold(
      backgroundColor: AppColors.muted,
      appBar: AppBar(title: const Text('Consultation Requests'), automaticallyImplyLeading: false),
      body: Column(
        children: [
          Container(
            color: AppColors.surface,
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
            child: Row(
              children: [
                for (var i = 0; i < labels.length; i++) ...[
                  if (i > 0) const SizedBox(width: 8),
                  Expanded(
                    child: _Segment(label: labels[i], selected: _tab == i, onTap: () => setState(() => _tab = i)),
                  ),
                ],
              ],
            ),
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: lawyer.refreshAll,
              child: !lawyer.inboxLoaded
                  ? const SkeletonList(count: 3, height: 150)
                  : shown.isEmpty
                      ? ListView(
                          padding: const EdgeInsets.all(16),
                          children: [
                            EmptyCard(
                              icon: [Icons.notifications_none_rounded, Icons.phone_missed_rounded, Icons.history_rounded][_tab],
                              title: ['No one is waiting', 'No missed requests', 'Nothing answered yet'][_tab],
                              message: [
                                lawyer.available
                                    ? 'You are online. New requests appear here — and ring — as they arrive.'
                                    : 'You are offline, so clients cannot send requests.',
                                'Requests the client withdrew, or that ran out before you answered, show here.',
                                'Completed and declined requests are kept here.',
                              ][_tab],
                            ),
                          ],
                        )
                      : ListView.separated(
                          padding: EdgeInsets.fromLTRB(16, 16, 16, bottomGutter(context)),
                          itemCount: shown.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 10),
                          itemBuilder: (context, i) {
                            final s = shown[i];
                            void open() => context.push('/lawyer/client/${s.userId}');
                            if (_tab == 0) return RequestCard(session: s, onTap: open);
                            return _AnsweredRow(session: s, onTap: open);
                          },
                        ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Segment extends StatelessWidget {
  const _Segment({required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? AppColors.primary : AppColors.muted,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          height: 38,
          alignment: Alignment.center,
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: selected ? Colors.white : AppColors.inkMuted,
            ),
          ),
        ),
      ),
    );
  }
}

class _AnsweredRow extends StatelessWidget {
  const _AnsweredRow({required this.session, required this.onTap});

  final Consultation session;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final s = session;
    return LCard(
      padding: const EdgeInsets.all(14),
      onTap: onTap,
      child: Row(
        children: [
          Avatar(name: s.userName, size: 44),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  s.userName.isEmpty ? 'Client' : s.userName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 2),
                TypePill(type: s.type, suffix: s.talkedMinutes > 0 ? '· ${s.talkedMinutes} mins' : null),
                const SizedBox(height: 2),
                Text(Fmt.dateTime(s.happenedAt), style: TextStyle(fontSize: 11.5, color: AppColors.inkFaint)),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              sessionStatusChip(s),
              const SizedBox(height: 6),
              Text(
                s.isResume ? 'Free' : (s.charged ? '+${Fmt.money(s.price)}' : '—'),
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: s.charged ? const Color(0xFF15803D) : AppColors.inkFaint,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
