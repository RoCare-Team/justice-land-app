import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/validators.dart';
import 'onboarding_controller.dart';
import 'onboarding_shell.dart';

/// Step 4 — how this lawyer will consult, and what each way costs.
///
/// One switch per channel, and a price only once it is switched on: a lawyer
/// who does not do video should never be asked to price it. Live channels are
/// billed by the minute (the first 10 seconds of every session are free, and
/// after that the client pays for the seconds they actually talk), while an
/// in-person visit is one fixed fee.
///
/// A channel left off is saved as 0, which is how the website reads "not
/// offered" — its button then does not appear on the lawyer's card.
class StepConsultations extends StatelessWidget {
  const StepConsultations({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.watch<OnboardingController>();

    return OnboardingShell(
      step: 3,
      title: 'Consultations & Fees',
      subtitle: 'How will you consult, and what do you charge?',
      onBack: c.canGoBack ? c.back : null,
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
        children: [
          _ChannelCard(
            icon: Icons.chat_bubble_outline_rounded,
            title: 'Live Chat',
            blurb: 'Typed messages with a client, billed by the minute.',
            on: c.offersChat,
            onChanged: c.setOffersChat,
            controller: c.chatRate,
            label: 'Chat rate *',
            hint: 'E.g., 20',
            suffix: 'per minute',
            saving: c.saving,
          ),
          _ChannelCard(
            icon: Icons.call_outlined,
            title: 'Audio Call',
            blurb: 'A voice call through the app.',
            on: c.offersAudio,
            onChanged: c.setOffersAudio,
            controller: c.audioRate,
            label: 'Audio rate *',
            hint: 'E.g., 30',
            suffix: 'per minute',
            saving: c.saving,
          ),
          _ChannelCard(
            icon: Icons.videocam_outlined,
            title: 'Video Call',
            blurb: 'Are you ready to take video consultations?',
            on: c.offersVideo,
            onChanged: c.setOffersVideo,
            controller: c.videoRate,
            label: 'Video rate *',
            hint: 'E.g., 50',
            suffix: 'per minute',
            saving: c.saving,
          ),
          _ChannelCard(
            icon: Icons.meeting_room_outlined,
            title: 'In-person Consultation',
            blurb: 'Meeting a client at your office.',
            on: c.offersInPerson,
            onChanged: c.setOffersInPerson,
            controller: c.inPersonFee,
            label: 'In-person fee *',
            hint: 'E.g., 1000',
            suffix: 'per visit',
            perMinute: false,
            saving: c.saving,
          ),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.muted,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.info_outline_rounded, size: 18, color: AppColors.inkMuted),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'The first 10 seconds of every chat and call are free. After that the '
                    'client pays for the seconds they actually talk, so a 90-second call at '
                    '₹20/min costs ₹26.67 — never a full minute more.',
                    style: TextStyle(fontSize: 13, height: 1.45, color: AppColors.inkMuted),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          OnbMessages(controller: c),
        ],
      ),
      primaryLabel: 'SAVE & CONTINUE',
      busy: c.saving,
      onPrimary: c.canContinueConsultations ? c.continueConsultations : null,
    );
  }
}

/// One way of consulting: a switch, and its price once it is on.
class _ChannelCard extends StatelessWidget {
  const _ChannelCard({
    required this.icon,
    required this.title,
    required this.blurb,
    required this.on,
    required this.onChanged,
    required this.controller,
    required this.label,
    required this.hint,
    required this.suffix,
    required this.saving,
    this.perMinute = true,
  });

  final IconData icon;
  final String title;
  final String blurb;
  final bool on;
  final ValueChanged<bool> onChanged;
  final TextEditingController controller;
  final String label;
  final String hint;
  final String suffix;
  final bool perMinute;
  final bool saving;

  @override
  Widget build(BuildContext context) {
    final amount = int.tryParse(controller.text.trim()) ?? 0;
    String? warn;
    if (on && controller.text.trim().isNotEmpty) {
      if (perMinute && (amount < Validators.minRate || amount > Validators.maxRate)) {
        warn = 'Enter a rate between ₹${Validators.minRate} and ₹${Validators.maxRate} per minute.';
      } else if (!perMinute && amount <= 0) {
        warn = 'Enter what one visit costs.';
      }
    }

    return OnbCard(
      children: [
        Row(
          children: [
            Container(
              height: 46,
              width: 46,
              decoration: BoxDecoration(
                color: on ? AppColors.primary.withValues(alpha: 0.08) : AppColors.muted,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(icon, color: on ? AppColors.primary : AppColors.inkFaint),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 2),
                  Text(blurb, style: TextStyle(fontSize: 13, height: 1.35, color: AppColors.inkMuted)),
                ],
              ),
            ),
            Switch.adaptive(
              value: on,
              onChanged: saving ? null : onChanged,
              activeTrackColor: AppColors.primary,
            ),
          ],
        ),
        if (on) ...[
          const SizedBox(height: 16),
          OnbField(
            label: label,
            controller: controller,
            hint: hint,
            keyboardType: TextInputType.number,
            digitsOnly: true,
            maxLength: 6,
            padBottom: 0,
            helper: warn ??
                (amount > 0 && perMinute
                    ? 'A 10-minute consultation costs about ₹${amount * 10}.'
                    : null),
            helperColor: warn == null ? null : AppColors.danger,
            suffix: Padding(
              padding: const EdgeInsets.only(right: 14),
              child: Align(
                alignment: Alignment.centerRight,
                widthFactor: 1,
                child: Text(
                  suffix,
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.inkFaint),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}
