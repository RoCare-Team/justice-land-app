import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/states.dart';
import '../../state/lawyer_controller.dart';
import 'lawyer_widgets.dart';

/// "My Cases": every client, with the state of their latest consultation.
/// Active is anyone waiting or in session; the rest are completed.
class LawyerCasesScreen extends StatefulWidget {
  const LawyerCasesScreen({super.key});

  @override
  State<LawyerCasesScreen> createState() => _LawyerCasesScreenState();
}

class _LawyerCasesScreenState extends State<LawyerCasesScreen> {
  bool _active = true;

  @override
  Widget build(BuildContext context) {
    final lawyer = context.watch<LawyerController>();
    final clients = lawyer.clients;
    final active = clients.where((c) => c.isLive || c.isWaiting).toList();
    final done = clients.where((c) => !(c.isLive || c.isWaiting)).toList();
    final shown = _active ? active : done;

    return Scaffold(
      backgroundColor: AppColors.muted,
      appBar: AppBar(title: const Text('My Consultations'), automaticallyImplyLeading: false),
      body: Column(
        children: [
          Container(
            color: AppColors.surface,
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
            child: Row(
              children: [
                Expanded(child: _pill('Active (${active.length})', _active, () => setState(() => _active = true))),
                const SizedBox(width: 8),
                Expanded(child: _pill('Completed (${done.length})', !_active, () => setState(() => _active = false))),
              ],
            ),
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: lawyer.refreshAll,
              child: !lawyer.historyLoaded && clients.isEmpty
                  ? const SkeletonList(count: 4, height: 90)
                  : shown.isEmpty
                      ? ListView(
                          padding: const EdgeInsets.all(16),
                          children: [
                            EmptyCard(
                              icon: _active ? Icons.forum_outlined : Icons.task_alt_rounded,
                              title: _active ? 'No active consultations' : 'No completed consultations yet',
                              message: _active
                                  ? 'Clients waiting for you or in a session appear here.'
                                  : 'Clients you have consulted are kept here with what each earned.',
                            ),
                          ],
                        )
                      : ListView.separated(
                          padding: EdgeInsets.fromLTRB(16, 16, 16, bottomGutter(context)),
                          itemCount: shown.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 10),
                          itemBuilder: (context, i) => _ClientRow(thread: shown[i]),
                        ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _pill(String label, bool selected, VoidCallback onTap) {
    return Material(
      color: selected ? AppColors.primary : AppColors.muted,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: SizedBox(
          height: 38,
          child: Center(
            child: Text(
              label,
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: selected ? Colors.white : AppColors.inkMuted),
            ),
          ),
        ),
      ),
    );
  }
}

class _ClientRow extends StatelessWidget {
  const _ClientRow({required this.thread});

  final ClientThread thread;

  @override
  Widget build(BuildContext context) {
    final latest = thread.latest;
    final (label, tone) = thread.isLive
        ? ('Live', ChipTone.success)
        : thread.isWaiting
            ? ('Pending', ChipTone.warning)
            : ('Completed', ChipTone.neutral);

    return LCard(
      padding: const EdgeInsets.all(14),
      onTap: () => context.push('/lawyer/client/${thread.userId}'),
      child: Row(
        children: [
          Avatar(name: thread.userName, size: 50, online: thread.isLive ? true : null),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  thread.userName.isEmpty ? 'Client' : thread.userName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 2),
                TypePill(type: latest.type, suffix: '· ${Fmt.pluralize(thread.sessions.length, 'session')}'),
                const SizedBox(height: 2),
                Text(
                  'Last consultation: ${Fmt.dateTime(thread.lastAt)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 11.5, color: AppColors.inkFaint),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              StatusChip(label: label, tone: tone),
              if (thread.earned > 0) ...[
                const SizedBox(height: 6),
                Text(
                  Fmt.money(thread.earned),
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFF15803D)),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}
