import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/states.dart';
import '../../state/lawyer_controller.dart';
import 'lawyer_widgets.dart';

/// One client: the request in front of the lawyer (if any), and everything
/// they have had together — sessions, minutes, what it earned, the chats.
///
/// Only what the platform actually records is shown. A client does not attach
/// a case description or documents to a consultation, so there is no such
/// section to fill with placeholders.
class ClientDetailsScreen extends StatelessWidget {
  const ClientDetailsScreen({super.key, required this.userId});

  final String userId;

  @override
  Widget build(BuildContext context) {
    final lawyer = context.watch<LawyerController>();
    final thread = lawyer.client(userId);

    if (thread == null) {
      return LawyerPage(
        title: 'Client Details',
        body: lawyer.historyLoaded
            ? const EmptyView(
                icon: Icons.person_search_outlined,
                title: 'Client not found',
                message: 'This client has no consultations with you.',
              )
            : const LoadingView(),
      );
    }

    final waiting = thread.sessions.where((s) => s.status.isWaiting).toList();
    final live = thread.sessions.where((s) => s.status.isLive).toList();
    // First time this client has come to this lawyer.
    final isNew = thread.sessions.length == 1;

    return LawyerPage(
      title: 'Client Details',
      body: ListView(
        padding: EdgeInsets.fromLTRB(16, 16, 16, bottomGutter(context)),
        children: [
          LCard(
            child: Row(
              children: [
                Avatar(name: thread.userName, size: 72, online: live.isNotEmpty ? true : null),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        thread.userName.isEmpty ? 'Client' : thread.userName,
                        style: const TextStyle(fontFamily: AppText.display, fontSize: 21, fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          if (isNew) const StatusChip(label: 'New client', tone: ChipTone.info),
                          if (live.isNotEmpty) const StatusChip(label: 'In session', tone: ChipTone.success),
                          if (waiting.isNotEmpty) const StatusChip(label: 'Waiting for you', tone: ChipTone.warning),
                          if (thread.userName == 'Anonymous')
                            const StatusChip(label: 'Anonymous', tone: ChipTone.neutral, icon: Icons.visibility_off_outlined),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _fact(context, '${thread.sessions.length}', 'Sessions'),
              const SizedBox(width: 10),
              _fact(context, '${thread.minutes}', 'Minutes'),
              const SizedBox(width: 10),
              _fact(context, Fmt.money(thread.earned), 'Earned'),
            ],
          ),

          for (final s in waiting) ...[
            const SizedBox(height: 18),
            const SectionTitle(title: 'Consultation Request', icon: Icons.notifications_active_outlined),
            RequestCard(session: s),
          ],
          for (final s in live) ...[
            const SizedBox(height: 18),
            const SectionTitle(title: 'Ongoing Consultation', icon: Icons.radio_button_checked_rounded),
            LiveSessionCard(session: s),
          ],

          if (thread.threadSession != null) ...[
            const SizedBox(height: 14),
            OutlinedButton.icon(
              onPressed: () => context.push(
                '/lawyer/transcript/${thread.threadSession!.id}?name=${Uri.encodeComponent(thread.userName)}',
              ),
              style: OutlinedButton.styleFrom(minimumSize: const Size(double.infinity, 46)),
              icon: const Icon(Icons.chat_outlined, size: 18),
              label: Text('Open conversation (${thread.messages} messages)'),
            ),
          ],

          const SizedBox(height: 18),
          const SectionTitle(title: 'Consultation History', icon: Icons.history_rounded),
          for (final s in thread.sessions)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: LCard(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    Container(
                      height: 38,
                      width: 38,
                      decoration: BoxDecoration(color: AppColors.primary.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(12)),
                      child: Icon(typeIcon(s.type), size: 19, color: AppColors.primary),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(s.type.label, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                          Text(
                            [
                              Fmt.dateTime(s.happenedAt),
                              if (s.talkedMinutes > 0) '${s.talkedMinutes} mins',
                              if (s.rate > 0) Fmt.rate(s.rate),
                            ].join(' · '),
                            style: TextStyle(fontSize: 11.5, color: AppColors.inkFaint),
                          ),
                        ],
                      ),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        sessionStatusChip(s),
                        if (s.charged) ...[
                          const SizedBox(height: 4),
                          Text('+${Fmt.money(s.price)}', style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: Color(0xFF15803D))),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _fact(BuildContext context, String value, String label) {
    return Expanded(
      child: LCard(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 6),
        child: Column(
          children: [
            Text(value, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
            const SizedBox(height: 2),
            Text(label, style: TextStyle(fontSize: 11.5, color: AppColors.inkMuted)),
          ],
        ),
      ),
    );
  }
}
