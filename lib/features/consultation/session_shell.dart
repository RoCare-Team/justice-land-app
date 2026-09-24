import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/common.dart';
import '../../models/consultation.dart';
import '../../state/auth_controller.dart';

/// The live meter every consultation screen carries: who you are talking to,
/// how long it has run since the lawyer accepted, and what it has cost so far.
///
/// Showing the running cost is not decoration. The session bills by the minute
/// against a wallet, and a client who cannot see the meter cannot make an
/// informed decision about when to stop.
class SessionHeader extends StatelessWidget {
  const SessionHeader({
    super.key,
    required this.session,
    required this.viewerIsAdvocate,
  });

  final Consultation session;
  final bool viewerIsAdvocate;

  @override
  Widget build(BuildContext context) {
    final counterpart =
        viewerIsAdvocate ? session.userName : session.advocateName;
    final live = session.status.isLive;

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Avatar(name: counterpart, size: 38),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      counterpart.isEmpty ? 'Client' : counterpart,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      session.type.label,
                      style: TextStyle(fontSize: 12, color: AppColors.inkMuted),
                    ),
                  ],
                ),
              ),
              StatusChip(
                label: session.status.label,
                tone: switch (session.status) {
                  ConsultationStatus.active => ChipTone.success,
                  ConsultationStatus.pending => ChipTone.warning,
                  ConsultationStatus.ended => ChipTone.info,
                  _ => ChipTone.neutral,
                },
              ),
            ],
          ),
          if (live) ...[
            const SizedBox(height: 12),
            // Ticks every second between polls, so the timer moves like a
            // clock rather than jumping two seconds at a time.
            SessionTicker(
              builder: (context) => Column(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: AppColors.muted,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        // How long it has run since the lawyer accepted — the
                        // same count-up the website shows, starting at 00:00.
                        _meter(
                          Icons.timer_outlined,
                          'Duration',
                          Fmt.clock(session.elapsed),
                        ),
                        Container(
                          height: 26,
                          width: 1,
                          color: AppColors.border,
                          margin: const EdgeInsets.symmetric(horizontal: 14),
                        ),
                        _meter(
                          Icons.currency_rupee_rounded,
                          session.isResume ? 'Free resume' : 'Cost so far',
                          session.isResume ? '₹0' : Fmt.amount(session.runningCost),
                        ),
                        Container(
                          height: 26,
                          width: 1,
                          color: AppColors.border,
                          margin: const EdgeInsets.symmetric(horizontal: 14),
                        ),
                        _meter(
                          Icons.speed_rounded,
                          'Rate',
                          session.isResume ? '—' : '₹${session.rate}/min',
                        ),
                      ],
                    ),
                  ),
                  // The wallet ceiling only matters when it is close.
                  if (session.endsAt != null && session.remaining.inMinutes < 2) ...[
                    const SizedBox(height: 8),
                    NoticeBanner(
                      tone: ChipTone.danger,
                      icon: Icons.hourglass_bottom_rounded,
                      message: viewerIsAdvocate
                          ? 'The client\'s balance runs out in ${Fmt.clock(session.remaining)} — the session ends then.'
                          : 'Your balance runs out in ${Fmt.clock(session.remaining)} — the session ends then.',
                    ),
                  ],
                ],
              ),
            ),
          ],
          if (session.status.isOver && session.price > 0) ...[
            const SizedBox(height: 12),
            NoticeBanner(
              tone: ChipTone.info,
              icon: Icons.receipt_long_rounded,
              message:
                  'Billed ${Fmt.money(session.price)} for '
                  '${Fmt.pluralize(session.minutes, 'minute')}.',
            ),
          ],
        ],
      ),
    );
  }

  Widget _meter(IconData icon, String label, String value, {bool warn = false}) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 12, color: AppColors.inkFaint),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 10.5, color: AppColors.inkFaint),
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: warn ? AppColors.danger : AppColors.inkStrong,
            ),
          ),
        ],
      ),
    );
  }
}

/// Rebuilds its child once a second, for live timers that must keep moving
/// between the two-second session polls.
class SessionTicker extends StatefulWidget {
  const SessionTicker({super.key, required this.builder});

  final WidgetBuilder builder;

  @override
  State<SessionTicker> createState() => _SessionTickerState();
}

class _SessionTickerState extends State<SessionTicker> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(context);
}

/// What a screen shows while a request is still pending.
///
/// The two sides see different things because they can do different things:
/// the client waits and may withdraw, the lawyer decides.
class PendingPanel extends StatelessWidget {
  const PendingPanel({
    super.key,
    required this.session,
    required this.viewerIsAdvocate,
    required this.busy,
    required this.onAccept,
    required this.onReject,
    required this.onCancel,
  });

  final Consultation session;
  final bool viewerIsAdvocate;
  final bool busy;
  final VoidCallback onAccept;
  final VoidCallback onReject;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    if (viewerIsAdvocate) {
      return Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.notifications_active_rounded,
                size: 44, color: AppColors.accent),
            const SizedBox(height: 16),
            Text(
              '${session.userName} wants a ${session.type.label.toLowerCase()}',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(
              'They can talk for up to ${Fmt.pluralize(session.maxMinutes, 'minute')} '
              'at ${Fmt.rate(session.rate)}. The clock starts when you accept.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13.5, height: 1.5, color: AppColors.inkMuted),
            ),
            const SizedBox(height: 26),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: busy ? null : onReject,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.danger,
                      side: BorderSide(color: AppColors.danger.withOpacity(0.4)),
                    ),
                    icon: const Icon(Icons.close_rounded, size: 18),
                    label: const Text('Decline'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: PrimaryButton(
                    label: 'Accept',
                    busy: busy,
                    icon: Icons.check_rounded,
                    onPressed: onAccept,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              'Declining costs the client nothing.',
              style: TextStyle(fontSize: 12, color: AppColors.inkFaint),
            ),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const SizedBox(
            height: 42,
            width: 42,
            child: CircularProgressIndicator(strokeWidth: 3),
          ),
          const SizedBox(height: 22),
          Text(
            'Waiting for ${session.advocateName}',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          Text(
            'Your request has been sent. Nothing is charged until they accept.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13.5, height: 1.5, color: AppColors.inkMuted),
          ),
          const SizedBox(height: 26),
          OutlinedButton.icon(
            onPressed: busy ? null : onCancel,
            icon: const Icon(Icons.close_rounded, size: 18),
            label: const Text('Cancel request'),
          ),
        ],
      ),
    );
  }
}

/// What a screen shows once the session is over.
class EndedPanel extends StatelessWidget {
  const EndedPanel({
    super.key,
    required this.session,
    required this.viewerIsAdvocate,
  });

  final Consultation session;
  final bool viewerIsAdvocate;

  @override
  Widget build(BuildContext context) {
    final (icon, title, message) = switch (session.status) {
      ConsultationStatus.rejected => (
          Icons.call_end_rounded,
          'Not answered',
          viewerIsAdvocate
              ? 'You declined this request. Nothing was charged.'
              : '${session.advocateName} could not take this one. '
                  'Nothing was charged — try another lawyer, or send an enquiry.',
        ),
      ConsultationStatus.cancelled => (
          Icons.cancel_outlined,
          'Cancelled',
          'This request was withdrawn before it started. Nothing was charged.',
        ),
      _ => (
          Icons.check_circle_outline_rounded,
          'Consultation ended',
          session.price <= 0
              ? 'Nothing was charged for this session.'
              : viewerIsAdvocate
                  ? 'You earned ${Fmt.money(session.price)} for '
                      '${Fmt.pluralize(session.minutes, 'minute')}. It is credited to your wallet.'
                  : 'Billed ${Fmt.money(session.price)} for '
                      '${Fmt.pluralize(session.minutes, 'minute')}.',
        ),
    };

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          const SizedBox(height: 20),
          Icon(icon, size: 52, color: AppColors.inkFaint),
          const SizedBox(height: 18),
          Text(title, style: Theme.of(context).textTheme.headlineMedium),
          const SizedBox(height: 8),
          Text(
            message,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 14, height: 1.55, color: AppColors.inkMuted),
          ),
          if (!viewerIsAdvocate && session.hasClaimableLeftover) ...[
            const SizedBox(height: 22),
            NoticeBanner(
              tone: ChipTone.success,
              icon: Icons.replay_rounded,
              message:
                  '${Fmt.leftover(session.resumeLeftoverSeconds)} of the time you '
                  'paid for is unused. Reopen ${session.advocateName}\'s profile '
                  'within 24 hours to resume it free.',
            ),
          ],
          const SizedBox(height: 28),
          if (!viewerIsAdvocate)
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () => context.go('/consultations'),
                child: const Text('My consultations'),
              ),
            )
          else
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () => context.go('/lawyer'),
                child: const Text('Back to home'),
              ),
            ),
          // A lawyer's home is the button above; the client home is not theirs.
          if (!viewerIsAdvocate) ...[
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: () => context.go('/'),
                child: const Text('Home'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Confirms ending a live session, because it settles the bill and cannot be
/// undone — the leftover comes back as a free resume, but the minutes used are
/// charged either way.
Future<bool> confirmEndSession(BuildContext context, Consultation session) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('End this consultation?'),
      content: Text(
        session.isResume
            ? 'This is a free resume. Ending it now keeps whatever time is still '
                'left claimable for 24 hours.'
            : 'You will be billed ${Fmt.amount(session.runningCost)} for the '
                '${Fmt.pluralize(session.elapsedMinutes, 'minute')} used so far. '
                'Any time you have not used stays claimable, free, for 24 hours.',
        style: const TextStyle(height: 1.5),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Keep talking'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('End session'),
        ),
      ],
    ),
  );
  return result ?? false;
}

/// True when the signed-in viewer is the lawyer on this session.
bool viewerIsAdvocateFor(AuthController auth) => auth.isAdvocate;
