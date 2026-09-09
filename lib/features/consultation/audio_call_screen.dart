import 'dart:ui' show FontFeature;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/states.dart';
import '../../models/consultation.dart';
import '../../services/consultation_service.dart';
import '../../state/auth_controller.dart';
import '../../state/session_controller.dart';
import 'session_shell.dart';

/// An audio consultation.
///
/// This one is different from the other two: the call itself happens on the
/// phone network, not in the app. The backend bridges the two numbers through
/// the telephony provider — neither side ever sees the other's number — so
/// this screen is a status board, not a call UI.
///
/// The polling is what makes it work. Nothing on the phone network reports
/// back on its own, so every poll asks the provider where the call actually is
/// and the server moves the session to match: answered starts the clock,
/// declined closes it with no charge at all, and a hang-up ends it, leaving the
/// unused minutes claimable free for 24 hours.
class AudioCallScreen extends StatelessWidget {
  const AudioCallScreen({super.key, required this.consultationId});

  final String consultationId;

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (context) =>
          SessionController(context.read<ConsultationService>(), consultationId)
            ..start(),
      child: const _AudioCallView(),
    );
  }
}

class _AudioCallView extends StatelessWidget {
  const _AudioCallView();

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<SessionController>();
    final auth = context.watch<AuthController>();
    final session = controller.session;
    final isAdvocate = auth.isAdvocate;

    if (controller.loading && session == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Audio consultation')),
        body: const LoadingView(label: 'Placing the call…'),
      );
    }

    if (session == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Audio consultation')),
        body: ErrorView(
          message: controller.error ?? 'This consultation could not be opened.',
          onRetry: controller.reload,
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Audio consultation'),
        actions: [
          if (session.status.isLive)
            TextButton.icon(
              onPressed: controller.sending
                  ? null
                  : () async {
                      if (await confirmEndSession(context, session)) {
                        await controller.end();
                      }
                    },
              icon: const Icon(Icons.call_end_rounded, size: 18),
              label: const Text('End'),
              style: TextButton.styleFrom(foregroundColor: AppColors.danger),
            ),
        ],
      ),
      body: Column(
        children: [
          SessionHeader(session: session, viewerIsAdvocate: isAdvocate),
          Expanded(
            child: switch (session.status) {
              ConsultationStatus.pending => _ringing(context, session, isAdvocate, controller),
              ConsultationStatus.active => _onCall(context, session, isAdvocate, controller),
              _ => EndedPanel(session: session, viewerIsAdvocate: isAdvocate),
            },
          ),
        ],
      ),
    );
  }

  Widget _ringing(
    BuildContext context,
    Consultation session,
    bool isAdvocate,
    SessionController controller,
  ) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _pulse(),
          const SizedBox(height: 28),
          Text(
            isAdvocate ? 'Your phone is ringing' : 'Connecting your call',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const SizedBox(height: 10),
          Text(
            isAdvocate
                ? '${session.userName} booked an audio consultation. Answer the '
                    'call on your phone to start — declining it costs them nothing.'
                : 'We are ringing your registered number first, then '
                    '${session.advocateName}. Neither of you sees the other\'s '
                    'number.\n\nNothing is charged unless the call is answered.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 14, height: 1.6, color: AppColors.inkMuted),
          ),
          const SizedBox(height: 30),
          if (!isAdvocate)
            OutlinedButton.icon(
              onPressed: controller.sending
                  ? null
                  : () async {
                      await controller.cancel();
                      if (context.mounted) context.pop();
                    },
              icon: const Icon(Icons.close_rounded, size: 18),
              label: const Text('Cancel call'),
            ),
          const SizedBox(height: 18),
          Text(
            'Keep this screen open — it is what tracks the call.',
            style: TextStyle(fontSize: 12, color: AppColors.inkFaint),
          ),
        ],
      ),
    );
  }

  Widget _onCall(
    BuildContext context,
    Consultation session,
    bool isAdvocate,
    SessionController controller,
  ) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Avatar(
            name: isAdvocate ? session.userName : session.advocateName,
            size: 96,
          ),
          const SizedBox(height: 20),
          Text(
            isAdvocate ? session.userName : session.advocateName,
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const SizedBox(height: 6),
          StatusChip(
            label: 'On call',
            tone: ChipTone.success,
            icon: Icons.phone_in_talk_rounded,
          ),
          const SizedBox(height: 26),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 16),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.border),
            ),
            child: Column(
              children: [
                Text(
                  Fmt.clock(session.remaining),
                  style: const TextStyle(
                    fontSize: 34,
                    fontWeight: FontWeight.w700,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
                Text(
                  'remaining',
                  style: TextStyle(fontSize: 12, color: AppColors.inkFaint),
                ),
                const Divider(height: 22),
                Text(
                  session.isResume
                      ? 'Free resume — nothing is being charged'
                      : '${Fmt.money(session.runningCost)} so far at ${Fmt.rate(session.rate)}',
                  style: TextStyle(fontSize: 13, color: AppColors.inkMuted),
                ),
              ],
            ),
          ),
          const SizedBox(height: 26),
          Text(
            'The call is on your phone. Hanging up there ends the session too — '
            'whatever time you have not used stays claimable, free, for 24 hours.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12.5, height: 1.5, color: AppColors.inkFaint),
          ),
          const SizedBox(height: 22),
          FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: controller.sending
                ? null
                : () async {
                    if (await confirmEndSession(context, session)) {
                      await controller.end();
                    }
                  },
            icon: const Icon(Icons.call_end_rounded),
            label: const Text('End consultation'),
          ),
        ],
      ),
    );
  }

  Widget _pulse() {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.85, end: 1.05),
      duration: const Duration(milliseconds: 900),
      curve: Curves.easeInOut,
      builder: (context, scale, child) => Transform.scale(scale: scale, child: child),
      onEnd: () {},
      child: Container(
        height: 96,
        width: 96,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: AppColors.primary.withOpacity(0.10),
        ),
        child: const Icon(Icons.phone_in_talk_rounded, size: 42, color: AppColors.primary),
      ),
    );
  }
}
