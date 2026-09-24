import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/common.dart';
import '../../../core/widgets/states.dart';
import '../../../models/legal_query.dart';
import 'onboarding_controller.dart';
import 'onboarding_shell.dart';

/// Step 5 — the lawyer's plan, from the same catalogue the website sells.
///
/// Every plan shows how it measures up against the areas, matters and cities
/// chosen in the earlier steps, so the choice is made with the numbers in view.
/// Confirming pays (for a paid plan), saves those choices and finishes — with a
/// progress screen rather than a spinner, so the wait reads as work being done.
class StepPlan extends StatelessWidget {
  const StepPlan({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.watch<OnboardingController>();

    if (c.stage != OnboardingStage.idle) return _Processing(controller: c);

    final plan = c.selectedPlan;
    final catalog = c.catalog;
    final fits = plan != null && c.fitOf(plan).fits;
    final alreadyOn = plan != null && catalog != null && plan.id == catalog.currentPlanId;

    return OnboardingShell(
      step: 5,
      title: 'Choose Your Plan',
      subtitle: 'Select a plan to start receiving enquiries and clients.',
      onBack: c.canGoBack ? c.back : null,
      body: catalog == null || catalog.plans.isEmpty
          ? ErrorView(
              message: c.error.isNotEmpty ? c.error : 'The plans could not be loaded.',
              onRetry: c.reloadPlans,
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
              children: [
                _Summary(controller: c),
                const SizedBox(height: 14),
                for (final p in catalog.plans) ...[
                  _PlanCard(
                    plan: p,
                    selected: p.id == c.selectedPlanId,
                    isCurrent: p.id == catalog.currentPlanId,
                    fits: c.fitOf(p).fits,
                    fitText: c.describeFitOf(p),
                    onTap: () => c.selectPlan(p.id),
                  ),
                  const SizedBox(height: 12),
                ],
                if (plan != null && !fits) ...[
                  NoticeBanner(
                    tone: ChipTone.warning,
                    icon: Icons.tune_rounded,
                    message: '${plan.name} ${c.describeFitOf(plan).toLowerCase()}. Pick a bigger plan, '
                        'or trim your choices.',
                    action: TextButton(
                      onPressed: c.editChoices,
                      child: const Text('Trim'),
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                OnbMessages(controller: c),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: Text(
                    'Paid plans run for twelve months and the price includes 18% GST. '
                    'Chat, audio and video consultations work the same on every plan — '
                    'a plan decides how much of your practice you list and where you rank.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 12.5, height: 1.5, color: AppColors.inkFaint),
                  ),
                ),
              ],
            ),
      primaryLabel: plan == null
          ? 'Confirm plan selection'
          : plan.isFree || alreadyOn
              ? 'Continue with ${plan.name}'
              : 'Pay ${Fmt.money(plan.yearTotal)} and continue',
      primaryIcon: Icons.arrow_forward_rounded,
      onPrimary: plan != null && fits ? c.confirmPlan : null,
    );
  }
}

/// What the earlier steps added up to — the numbers each plan is judged against.
class _Summary extends StatelessWidget {
  const _Summary({required this.controller});

  final OnboardingController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    String n(int count, String one, String many) => '$count ${count == 1 ? one : many}';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
      decoration: BoxDecoration(
        color: AppColors.accentSoft,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.accent.withValues(alpha: 0.45)),
      ),
      child: Row(
        children: [
          const Icon(Icons.fact_check_outlined, size: 20, color: AppColors.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'You chose ${n(c.areas.length, 'practice area', 'practice areas')}, '
              '${n(c.matters.length, 'matter', 'matters')} and '
              '${n(c.cities.length, 'extra city', 'extra cities')}.',
              style: const TextStyle(fontSize: 13.5, height: 1.4, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

class _PlanCard extends StatelessWidget {
  const _PlanCard({
    required this.plan,
    required this.selected,
    required this.isCurrent,
    required this.fits,
    required this.fitText,
    required this.onTap,
  });

  final MembershipPlan plan;
  final bool selected;
  final bool isCurrent;
  final bool fits;
  final String fitText;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: selected ? AppColors.accent : AppColors.border, width: selected ? 2 : 1),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      margin: const EdgeInsets.only(top: 2),
                      height: 26,
                      width: 26,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: selected ? AppColors.primary : Colors.transparent,
                        border: Border.all(color: selected ? AppColors.primary : AppColors.border, width: 1.8),
                      ),
                      child: selected ? const Icon(Icons.check_rounded, size: 17, color: Colors.white) : null,
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Flexible(
                                child: Text(
                                  plan.name,
                                  style: const TextStyle(fontFamily: AppText.display, fontSize: 21, fontWeight: FontWeight.w700),
                                ),
                              ),
                              if (isCurrent) ...[
                                const SizedBox(width: 8),
                                const Tag(label: 'Current'),
                              ],
                            ],
                          ),
                          const SizedBox(height: 3),
                          Text(
                            plan.tagline,
                            style: TextStyle(fontSize: 13, height: 1.35, color: AppColors.inkMuted),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          plan.isFree ? 'Free' : Fmt.money(plan.monthly),
                          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: AppColors.primary),
                        ),
                        Text(
                          plan.isFree ? 'forever' : 'per month',
                          style: TextStyle(fontSize: 12, color: AppColors.inkFaint),
                        ),
                      ],
                    ),
                  ],
                ),
                if (!plan.isFree) ...[
                  const SizedBox(height: 8),
                  Padding(
                    padding: const EdgeInsets.only(left: 40),
                    child: Text(
                      'Billed yearly · ${Fmt.money(plan.yearTotal)} incl. GST',
                      style: TextStyle(fontSize: 12.5, color: AppColors.inkFaint),
                    ),
                  ),
                ],
                const SizedBox(height: 14),
                Divider(height: 1, color: AppColors.border),
                const SizedBox(height: 14),
                for (final f in plan.features)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 9),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          margin: const EdgeInsets.only(top: 1),
                          height: 20,
                          width: 20,
                          decoration: BoxDecoration(
                            color: AppColors.primary.withValues(alpha: 0.08),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.check_rounded, size: 13, color: AppColors.primary),
                        ),
                        const SizedBox(width: 10),
                        Expanded(child: Text(f, style: const TextStyle(fontSize: 14, height: 1.35))),
                      ],
                    ),
                  ),
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                  decoration: BoxDecoration(
                    color: fits ? AppColors.successSoft : AppColors.warningSoft,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        fits ? Icons.check_circle_rounded : Icons.error_outline_rounded,
                        size: 17,
                        color: fits ? AppColors.success : AppColors.warning,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          fitText,
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                            color: fits ? AppColors.ink : AppColors.warning,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The wait after "Confirm": paying, saving, and finally the success screen.
class _Processing extends StatelessWidget {
  const _Processing({required this.controller});

  final OnboardingController controller;

  @override
  Widget build(BuildContext context) {
    final stage = controller.stage;
    final paid = controller.selectedPlan?.isFree == false;

    return Scaffold(
      body: AnnotatedRegion<SystemUiOverlayStyle>(
        // A navy screen: light status-bar icons, as on the app's other dark headers.
        value: SystemUiOverlayStyle.light,
        child: Container(
          width: double.infinity,
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [AppColors.primaryLight, AppColors.primary, AppColors.primaryDark],
            ),
          ),
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(28, 24, 28, 24),
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 350),
                child: stage == OnboardingStage.done
                    ? const _Done(key: ValueKey('done'))
                    : _Progress(key: const ValueKey('progress'), stage: stage, paid: paid),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Progress extends StatelessWidget {
  const _Progress({super.key, required this.stage, required this.paid});

  final OnboardingStage stage;
  final bool paid;

  @override
  Widget build(BuildContext context) {
    final paying = stage == OnboardingStage.paying;
    final rows = <(String, _RowState)>[
      if (paid) ('Payment', paying ? _RowState.active : _RowState.done),
      ('Saving your practice details', paying ? _RowState.waiting : _RowState.active),
      ('Getting your dashboard ready', _RowState.waiting),
    ];

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Center(
          child: SizedBox(
            height: 64,
            width: 64,
            child: CircularProgressIndicator(strokeWidth: 3.5, color: AppColors.accent),
          ),
        ),
        const SizedBox(height: 28),
        Text(
          paying ? 'Complete your payment' : 'Setting up your profile',
          textAlign: TextAlign.center,
          style: const TextStyle(fontFamily: AppText.display, fontSize: 26, fontWeight: FontWeight.w700, color: Colors.white),
        ),
        const SizedBox(height: 8),
        Text(
          paying
              ? 'Finish the payment in the secure window. Please do not close the app.'
              : 'This takes a few seconds. Please keep the app open.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 14.5, height: 1.45, color: Colors.white.withValues(alpha: 0.75)),
        ),
        const SizedBox(height: 32),
        for (final (label, state) in rows)
          Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: Row(
              children: [
                SizedBox(
                  height: 26,
                  width: 26,
                  child: switch (state) {
                    _RowState.done => const Icon(Icons.check_circle_rounded, color: AppColors.accent, size: 26),
                    _RowState.active => const Padding(
                        padding: EdgeInsets.all(3),
                        child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white),
                      ),
                    _RowState.waiting => Icon(Icons.circle_outlined, color: Colors.white.withValues(alpha: 0.35), size: 24),
                  },
                ),
                const SizedBox(width: 14),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 15.5,
                    fontWeight: state == _RowState.active ? FontWeight.w700 : FontWeight.w500,
                    color: Colors.white.withValues(alpha: state == _RowState.waiting ? 0.5 : 1),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

enum _RowState { done, active, waiting }

class _Done extends StatelessWidget {
  const _Done({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const Spacer(),
        TweenAnimationBuilder<double>(
          tween: Tween(begin: 0.4, end: 1),
          duration: const Duration(milliseconds: 550),
          curve: Curves.elasticOut,
          builder: (context, scale, child) => Transform.scale(scale: scale, child: child),
          child: Container(
            height: 104,
            width: 104,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.accent,
              boxShadow: [
                BoxShadow(color: AppColors.accent.withValues(alpha: 0.4), blurRadius: 30, spreadRadius: 4),
              ],
            ),
            child: const Icon(Icons.check_rounded, size: 58, color: AppColors.primaryDark),
          ),
        ),
        const SizedBox(height: 30),
        const Text(
          'You\'re all set!',
          style: TextStyle(fontFamily: AppText.display, fontSize: 30, fontWeight: FontWeight.w700, color: Colors.white),
        ),
        const SizedBox(height: 10),
        Text(
          'Your profile is ready. We\'ll verify your documents within 24–48 hours and let you know '
          'as soon as you\'re approved.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 15, height: 1.5, color: Colors.white.withValues(alpha: 0.78)),
        ),
        const Spacer(),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.accent,
              foregroundColor: AppColors.primaryDark,
            ),
            onPressed: () {
              Toast.success(context, 'Welcome to Justiceland.');
              context.go('/lawyer');
            },
            child: const Text('Go to dashboard'),
          ),
        ),
      ],
    );
  }
}
