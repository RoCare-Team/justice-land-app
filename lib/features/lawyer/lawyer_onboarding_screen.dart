import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/widgets/states.dart';
import '../../services/content_service.dart';
import '../../services/dashboard_service.dart';
import '../../services/membership_service.dart';
import '../../state/auth_controller.dart';
import 'onboarding/onboarding_controller.dart';
import 'onboarding/step_earnings.dart';
import 'onboarding/step_plan.dart';
import 'onboarding/step_profile.dart';
import 'onboarding/step_specializations.dart';
import 'onboarding/step_verification.dart';

/// A new lawyer's setup, straight after they sign up with their number.
///
///   1. Professional Verification — Bar Council ID and two documents
///   2. Your Specializations      — practice areas (and their matters), 1–6
///   3. Professional Profile      — photo, name, title, experience, PIN code,
///                                  and the cities they practise in
///   4. Earnings Setup            — bank account and PAN (can be skipped)
///   5. Choose Your Plan          — Starter, Professional or Premium
///
/// Basic details (name, email, city) are already done at signup. The steps live
/// in `onboarding/`; this screen only provides their shared state and switches
/// between them. Finishing (or "Later") clears `lawyerOnboardingPending`, which is
/// what stops the router sending the lawyer back here.
class LawyerOnboardingScreen extends StatelessWidget {
  const LawyerOnboardingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<OnboardingController>(
      create: (context) {
        final auth = context.read<AuthController>();
        return OnboardingController(
          dashboard: context.read<DashboardService>(),
          content: context.read<ContentService>(),
          membership: context.read<MembershipService>(),
          advocate: auth.advocate,
          refreshAuth: auth.refresh,
          onCompleted: () => auth.setLawyerOnboardingPending(false),
        )..load();
      },
      child: const _OnboardingHost(),
    );
  }
}

class _OnboardingHost extends StatelessWidget {
  const _OnboardingHost();

  @override
  Widget build(BuildContext context) {
    final c = context.watch<OnboardingController>();

    if (c.loading) {
      return const Scaffold(body: LoadingView(label: 'Getting things ready…'));
    }

    final Widget page = switch (c.step) {
      0 => const StepVerification(),
      1 => const StepSpecializations(),
      2 => const StepProfile(),
      3 => const StepEarnings(),
      _ => const StepPlan(),
    };

    // The system back button steps back through the flow; it never leaves it.
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) c.back();
      },
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 260),
        child: KeyedSubtree(key: ValueKey(c.step), child: page),
      ),
    );
  }
}
