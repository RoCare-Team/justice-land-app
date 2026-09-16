import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/network/api_exception.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/states.dart';
import '../../models/consultation.dart';
import '../../state/lawyer_controller.dart';

/// Pieces every lawyer screen shares, so the lawyer app reads as one product.

/// The icon a consultation channel is drawn with.
IconData typeIcon(ConsultationType type) => switch (type) {
      ConsultationType.chat => Icons.chat_bubble_outline_rounded,
      ConsultationType.audio => Icons.call_outlined,
      ConsultationType.video => Icons.videocam_outlined,
    };

/// Opens the live screen for a session on its own channel.
void openSession(BuildContext context, Consultation session) {
  final route = switch (session.type) {
    ConsultationType.chat => '/consultation/${session.id}/chat',
    ConsultationType.video => '/consultation/${session.id}/video',
    ConsultationType.audio => '/consultation/${session.id}/audio',
  };
  context.push(route);
}

/// Accept, then go straight into the session — the client is already waiting.
Future<void> acceptAndOpen(BuildContext context, Consultation session) async {
  final lawyer = context.read<LawyerController>();
  try {
    final updated = await lawyer.accept(session.id);
    if (context.mounted) openSession(context, updated);
  } on ApiException catch (e) {
    if (context.mounted) Toast.error(context, e.message);
  }
}

Future<void> declineRequest(BuildContext context, Consultation session) async {
  final lawyer = context.read<LawyerController>();
  try {
    await lawyer.reject(session.id);
    if (context.mounted) Toast.show(context, 'Request declined. Nothing was charged.');
  } on ApiException catch (e) {
    if (context.mounted) Toast.error(context, e.message);
  }
}

/// A plain white rounded card, the lawyer app's basic surface.
class LCard extends StatelessWidget {
  const LCard({super.key, required this.child, this.padding = const EdgeInsets.all(16), this.onTap});

  final Widget child;
  final EdgeInsets padding;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: AppColors.border),
          ),
          child: child,
        ),
      ),
    );
  }
}

/// "Incoming Requests  (2)                See All"
class SectionTitle extends StatelessWidget {
  const SectionTitle({super.key, required this.title, this.count, this.action, this.onAction, this.icon});

  final String title;
  final int? count;
  final String? action;
  final VoidCallback? onAction;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          if (icon != null) ...[
            Icon(icon, size: 20, color: AppColors.primary),
            const SizedBox(width: 8),
          ],
          // Title and badge share one flexible slot, with the action outside
          // it. As a Flexible beside a Spacer they were two flex children of
          // equal weight, so the free space split evenly and "Active
          // Consultations" ellipsised at half the row with the other half
          // empty.
          Expanded(
            child: Row(
              children: [
                Flexible(
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontFamily: AppText.display,
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      color: AppColors.ink,
                    ),
                  ),
                ),
                if ((count ?? 0) > 0) ...[
                  const SizedBox(width: 8),
                  CountBadge(count: count!),
                ],
              ],
            ),
          ),
          if (action != null)
            TextButton(
              onPressed: onAction,
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                minimumSize: const Size(0, 32),
              ),
              child: Text(action!, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
            ),
        ],
      ),
    );
  }
}

class CountBadge extends StatelessWidget {
  const CountBadge({super.key, required this.count, this.color = AppColors.danger});

  final int count;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minWidth: 20),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(999)),
      child: Text(
        '$count',
        textAlign: TextAlign.center,
        style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700),
      ),
    );
  }
}

/// The small pill that says what kind of session it is.
class TypePill extends StatelessWidget {
  const TypePill({super.key, required this.type, this.suffix});

  final ConsultationType type;
  final String? suffix;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(typeIcon(type), size: 14, color: AppColors.primary),
        const SizedBox(width: 4),
        Flexible(
          child: Text(
            suffix == null ? type.label : '${type.label} $suffix',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 12.5, color: AppColors.inkMuted),
          ),
        ),
      ],
    );
  }
}

/// The request row with Decline and Accept, used on Home and Requests.
class RequestCard extends StatelessWidget {
  const RequestCard({super.key, required this.session, this.onTap});

  final Consultation session;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final lawyer = context.watch<LawyerController>();
    final busy = lawyer.isBusy(session.id);
    final phone = session.isAudio;
    // One live session at a time: a second accept would leave the first
    // client talking to nobody.
    final inSession = lawyer.live.isNotEmpty;

    return LCard(
      onTap: onTap,
      padding: const EdgeInsets.all(14),
      child: Column(
        children: [
          Row(
            children: [
              Avatar(name: session.userName, size: 48),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      session.userName.isEmpty ? 'Client' : session.userName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 3),
                    TypePill(type: session.type, suffix: session.isResume ? '· resume' : 'Request'),
                    const SizedBox(height: 3),
                    Text(
                      '${Fmt.rate(session.rate)} · ${Fmt.timeAgo(session.createdAt)}',
                      style: TextStyle(fontSize: 11.5, color: AppColors.inkFaint),
                    ),
                  ],
                ),
              ),
              if (onTap != null) Icon(Icons.chevron_right_rounded, color: AppColors.inkFaint),
            ],
          ),
          const SizedBox(height: 12),
          if (phone)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(
                color: AppColors.successSoft,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.phone_in_talk_rounded, size: 16, color: AppColors.success),
                  SizedBox(width: 6),
                  Text(
                    'Ringing on your registered phone',
                    style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: AppColors.success),
                  ),
                ],
              ),
            )
          else
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: busy ? null : () => declineRequest(context, session),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.danger,
                      side: BorderSide(color: AppColors.danger.withValues(alpha: 0.4)),
                      minimumSize: const Size(0, 42),
                    ),
                    icon: const Icon(Icons.close_rounded, size: 18),
                    label: const Text('Decline'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: busy || inSession ? null : () => acceptAndOpen(context, session),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.success,
                      minimumSize: const Size(0, 42),
                    ),
                    icon: busy
                        ? const SizedBox(
                            height: 16,
                            width: 16,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : Icon(typeIcon(session.type), size: 18),
                    label: const Text('Accept'),
                  ),
                ),
              ],
            ),
          if (!phone && inSession) ...[
            const SizedBox(height: 8),
            Text(
              'Finish your current consultation to accept this one.',
              style: TextStyle(fontSize: 11.5, color: AppColors.inkFaint),
            ),
          ],
        ],
      ),
    );
  }
}

/// A running session with a live clock and End.
class LiveSessionCard extends StatelessWidget {
  const LiveSessionCard({super.key, required this.session});

  final Consultation session;

  @override
  Widget build(BuildContext context) {
    return LCard(
      padding: const EdgeInsets.all(14),
      onTap: () => openSession(context, session),
      child: Row(
        children: [
          Avatar(name: session.userName, size: 50, online: true),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  session.userName.isEmpty ? 'Client' : session.userName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Container(
                      height: 8,
                      width: 8,
                      decoration: const BoxDecoration(color: AppColors.danger, shape: BoxShape.circle),
                    ),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        'Ongoing ${session.type.label}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: AppColors.danger),
                      ),
                    ),
                    const SizedBox(width: 6),
                    TickingClock(since: session.startedAt),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  '${Fmt.rate(session.rate)} · ${Fmt.clock(session.remaining)} of balance left',
                  style: TextStyle(fontSize: 11.5, color: AppColors.inkFaint),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          _RoundAction(
            icon: typeIcon(session.type),
            color: AppColors.primary,
            tooltip: 'Open',
            onTap: () => openSession(context, session),
          ),
          const SizedBox(width: 8),
          _RoundAction(
            icon: Icons.call_end_rounded,
            color: AppColors.danger,
            tooltip: 'End consultation',
            onTap: () => _confirmEnd(context),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmEnd(BuildContext context) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('End consultation?'),
        content: Text('This ends the session with ${session.userName.isEmpty ? 'the client' : session.userName} for both of you.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Keep talking')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('End now'),
          ),
        ],
      ),
    );
    if (yes != true || !context.mounted) return;
    try {
      await context.read<LawyerController>().end(session.id);
    } on ApiException catch (e) {
      if (context.mounted) Toast.error(context, e.message);
    }
  }
}

class _RoundAction extends StatelessWidget {
  const _RoundAction({required this.icon, required this.color, required this.onTap, required this.tooltip});

  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  final String tooltip;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: color,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: SizedBox(height: 44, width: 44, child: Icon(icon, color: Colors.white, size: 20)),
        ),
      ),
    );
  }
}

/// "12:34" counting up from [since], redrawn every second.
class TickingClock extends StatefulWidget {
  const TickingClock({super.key, required this.since, this.style});

  final DateTime? since;
  final TextStyle? style;

  @override
  State<TickingClock> createState() => _TickingClockState();
}

class _TickingClockState extends State<TickingClock> {
  late final Stream<int> _ticks = Stream.periodic(const Duration(seconds: 1), (i) => i);

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<int>(
      stream: _ticks,
      builder: (context, _) {
        final start = widget.since;
        final elapsed = start == null ? Duration.zero : DateTime.now().difference(start);
        return Text(
          Fmt.clock(elapsed),
          style: widget.style ??
              const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
        );
      },
    );
  }
}

/// A soft empty state inside a card.
class EmptyCard extends StatelessWidget {
  const EmptyCard({super.key, required this.icon, required this.title, this.message});

  final IconData icon;
  final String title;
  final String? message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 22),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          Container(
            height: 44,
            width: 44,
            decoration: BoxDecoration(color: AppColors.muted, shape: BoxShape.circle, border: Border.all(color: AppColors.border)),
            child: Icon(icon, color: AppColors.inkFaint, size: 22),
          ),
          const SizedBox(height: 10),
          Text(title, textAlign: TextAlign.center, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
          if (message != null) ...[
            const SizedBox(height: 4),
            Text(message!, textAlign: TextAlign.center, style: TextStyle(fontSize: 12.5, height: 1.4, color: AppColors.inkMuted)),
          ],
        ],
      ),
    );
  }
}

/// A plain white page with a centred title, the lawyer app's inner screens.
class LawyerPage extends StatelessWidget {
  const LawyerPage({super.key, required this.title, required this.body, this.actions});

  final String title;
  final Widget body;
  final List<Widget>? actions;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.muted,
      appBar: AppBar(
        title: Text(title),
        centerTitle: true,
        actions: actions,
      ),
      body: body,
    );
  }
}

/// The status chip for a finished or running session, in lawyer wording.
StatusChip sessionStatusChip(Consultation c) {
  final (label, tone) = switch (c.status) {
    ConsultationStatus.active => ('Live', ChipTone.success),
    ConsultationStatus.pending => ('Waiting', ChipTone.warning),
    ConsultationStatus.ended => ('Completed', ChipTone.info),
    ConsultationStatus.rejected => ('Declined', ChipTone.danger),
    ConsultationStatus.cancelled => ('Cancelled', ChipTone.neutral),
  };
  return StatusChip(label: label, tone: tone);
}
