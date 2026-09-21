import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/network/api_exception.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/states.dart';
import '../../models/advocate.dart';
import '../../models/consultation.dart';
import '../../services/consultation_service.dart';
import '../../state/auth_controller.dart';

/// Booking a consultation on one channel.
///
/// The important thing this screen has to get across is that nothing is
/// charged now. The session bills the minutes it actually runs, and the wallet
/// balance only sets a ceiling on how long it can go — which is why the sheet
/// leads with "you can talk for about N minutes" rather than a price.
class BookingSheet extends StatefulWidget {
  const BookingSheet({
    super.key,
    required this.advocate,
    required this.type,
  });

  final Advocate advocate;
  final ConsultationType type;

  static Future<void> open(
    BuildContext context, {
    required Advocate advocate,
    required ConsultationType type,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      // Above the bottom tab bar: opened from a card on a tab, the nearest
      // navigator is the tab shell's, and the bar would cover the Start button.
      useRootNavigator: true,
      builder: (_) => BookingSheet(advocate: advocate, type: type),
    );
  }

  @override
  State<BookingSheet> createState() => _BookingSheetState();
}

class _BookingSheetState extends State<BookingSheet> {
  bool _checking = true;
  bool _booking = false;
  String _error = '';
  bool _insufficient = false;
  ResumableSession? _resumable;

  int get _rate => widget.advocate.rateFor(widget.type.wire);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkResumable());
  }

  /// Leftover time from an earlier session with this lawyer can be reconnected
  /// free for 24 hours. Each channel only sees its own leftover — phone minutes
  /// must not come back as a free chat.
  Future<void> _checkResumable() async {
    try {
      final found = await context.read<ConsultationService>().resumable(
            advocateId: widget.advocate.id,
            type: widget.type,
          );
      if (!mounted) return;
      setState(() {
        _resumable = found;
        _checking = false;
      });
    } on ApiException {
      if (!mounted) return;
      setState(() => _checking = false);
    }
  }

  Future<void> _book({bool resume = false}) async {
    setState(() {
      _booking = true;
      _error = '';
      _insufficient = false;
    });

    final service = context.read<ConsultationService>();
    try {
      final session = resume
          ? await service.resume(
              advocateId: widget.advocate.id,
              fromSessionId: _resumable!.id,
            )
          : await service.book(
              advocateId: widget.advocate.id,
              type: widget.type,
            );

      if (!mounted) return;
      Navigator.of(context).pop();
      _openSession(session);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _booking = false;
        _error = e.message;
        _insufficient = e.isInsufficientBalance;
      });
    }
  }

  void _openSession(Consultation session) {
    switch (session.type) {
      case ConsultationType.chat:
        context.push('/consultation/${session.id}/chat');
      case ConsultationType.video:
        context.push('/consultation/${session.id}/video');
      case ConsultationType.audio:
        context.push('/consultation/${session.id}/audio');
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthController>();
    final balance = auth.walletBalance;
    // What the wallet can cover, which becomes the session's ceiling.
    final affordableMinutes = _rate > 0 ? balance ~/ _rate : 0;
    final canAfford = affordableMinutes >= 1;

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  height: 4,
                  width: 40,
                  decoration: BoxDecoration(
                    color: AppColors.ink.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Avatar(
                    name: widget.advocate.name,
                    photo: widget.advocate.photo,
                    size: 46,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.type.label,
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        Text(
                          'with ${widget.advocate.name}',
                          style: TextStyle(fontSize: 13, color: AppColors.inkMuted),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              if (_checking)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 28),
                  child: LoadingView(label: 'Checking your session…'),
                )
              else if (_resumable != null)
                _resumeOffer()
              else
                _freshBooking(balance, affordableMinutes, canAfford),

              if (_error.isNotEmpty) ...[
                const SizedBox(height: 16),
                NoticeBanner(
                  message: _error,
                  tone: ChipTone.danger,
                  icon: Icons.error_outline_rounded,
                  action: _insufficient
                      ? TextButton(
                          onPressed: () {
                            Navigator.of(context).pop();
                            context.push('/wallet');
                          },
                          child: const Text('Add money'),
                        )
                      : null,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// Free reconnection of time already paid for.
  Widget _resumeOffer() {
    final leftover = _resumable!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        NoticeBanner(
          tone: ChipTone.success,
          icon: Icons.replay_rounded,
          message:
              'You have ${Fmt.leftover(leftover.seconds)} with ${widget.advocate.name} '
              'from an earlier session. Reconnect free — nothing is charged.',
        ),
        const SizedBox(height: 18),
        PrimaryButton(
          label: 'Resume free session',
          busy: _booking,
          icon: Icons.replay_rounded,
          onPressed: () => _book(resume: true),
        ),
        const SizedBox(height: 10),
        OutlinedButton(
          onPressed: _booking ? null : () => setState(() => _resumable = null),
          child: const Text('Start a new paid session instead'),
        ),
      ],
    );
  }

  Widget _freshBooking(int balance, int affordableMinutes, bool canAfford) {
    if (_rate <= 0) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          NoticeBanner(
            tone: ChipTone.warning,
            icon: Icons.info_outline_rounded,
            message:
                '${widget.advocate.name} does not offer ${widget.type.label.toLowerCase()}. '
                'Try another channel, or send an enquiry.',
          ),
          const SizedBox(height: 16),
          OutlinedButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.muted,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            children: [
              Row(
                children: [
                  Text('Rate', style: TextStyle(fontSize: 13.5, color: AppColors.inkMuted)),
                  const Spacer(),
                  Text(
                    Fmt.rate(_rate),
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Text('Wallet balance', style: TextStyle(fontSize: 13.5, color: AppColors.inkMuted)),
                  const Spacer(),
                  Text(
                    Fmt.money(balance),
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: canAfford ? AppColors.success : AppColors.danger,
                    ),
                  ),
                ],
              ),
              if (canAfford) ...[
                const Divider(height: 22),
                Row(
                  children: [
                    const Icon(Icons.schedule_rounded, size: 16, color: AppColors.primary),
                    const SizedBox(width: 7),
                    Expanded(
                      child: Text(
                        'You can talk for up to $affordableMinutes '
                        '${affordableMinutes == 1 ? 'minute' : 'minutes'}.',
                        style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 14),
        Text(
          'Nothing is charged now. You pay only for the minutes the session '
          'actually runs, settled when it ends — and any time you do not use '
          'stays claimable, free, for 24 hours.',
          style: TextStyle(fontSize: 12.5, height: 1.5, color: AppColors.inkMuted),
        ),
        const SizedBox(height: 18),
        if (canAfford)
          PrimaryButton(
            label: switch (widget.type) {
              ConsultationType.chat => 'Start chat',
              ConsultationType.audio => 'Call now',
              ConsultationType.video => 'Start video call',
            },
            busy: _booking,
            icon: switch (widget.type) {
              ConsultationType.chat => Icons.chat_bubble_rounded,
              ConsultationType.audio => Icons.call_rounded,
              ConsultationType.video => Icons.videocam_rounded,
            },
            onPressed: _book,
          )
        else ...[
          NoticeBanner(
            tone: ChipTone.warning,
            icon: Icons.account_balance_wallet_outlined,
            message:
                'This lawyer charges ${Fmt.rate(_rate)}. Add at least ₹$_rate to '
                'your wallet to start.',
          ),
          const SizedBox(height: 14),
          PrimaryButton(
            label: 'Add money to wallet',
            icon: Icons.add_rounded,
            onPressed: () {
              Navigator.of(context).pop();
              context.push('/wallet');
            },
          ),
        ],
        if (widget.type == ConsultationType.audio) ...[
          const SizedBox(height: 12),
          NoticeBanner(
            tone: ChipTone.neutral,
            icon: Icons.mic_rounded,
            message:
                'This is a voice call over the internet, inside the app — no '
                'phone numbers are shared. It connects once the lawyer accepts, '
                'and nothing is charged if they do not. Calls may be recorded.',
          ),
        ],
      ],
    );
  }
}
