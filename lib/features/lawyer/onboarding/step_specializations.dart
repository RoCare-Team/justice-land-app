import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/common.dart';
import '../../../core/widgets/states.dart';
import '../../../models/account.dart';
import 'category_style.dart';
import 'onboarding_controller.dart';
import 'onboarding_shell.dart';
import 'pick_or_upgrade.dart';

/// Step 2 — the practice areas, drawn as cards. A selected card can open its
/// matters. How many can be chosen is the plan's: a tap past it opens the plans
/// right here, and paying lifts the limit.
class StepSpecializations extends StatefulWidget {
  const StepSpecializations({super.key});

  @override
  State<StepSpecializations> createState() => _StepSpecializationsState();
}

class _StepSpecializationsState extends State<StepSpecializations> {
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  /// A tap past the plan's limit opens the plans here; paying lifts it and the
  /// area is ticked.
  void _tap(OnboardingController c, LegalService service) => pickOrUpgrade(
        context,
        c,
        pick: () => c.toggleArea(service),
        reason: () => c.areaUpgradeReason(service.name),
      );

  void _openMatters(OnboardingController c, LegalService service) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => ChangeNotifierProvider<OnboardingController>.value(
        value: c,
        child: _MattersSheet(service: service),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.watch<OnboardingController>();
    final query = _search.text.trim().toLowerCase();
    final shown = [
      for (final s in c.services)
        if (query.isEmpty ||
            s.name.toLowerCase().contains(query) ||
            s.subServices.any((m) => m.name.toLowerCase().contains(query)))
          s,
    ];

    return OnboardingShell(
      step: 1,
      title: 'Your Specializations',
      subtitle: 'Select your areas of expertise',
      onBack: c.canGoBack ? c.back : null,
      headerAction: const OnbLaterButton(),
      body: c.services.isEmpty
          ? ErrorView(
              message: c.loadError.isNotEmpty ? c.loadError : 'No practice areas are available right now.',
              onRetry: c.load,
            )
          : CustomScrollView(
              slivers: [
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(20, 18, 20, 10),
                  sliver: SliverToBoxAdapter(
                    child: Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _search,
                            onChanged: (_) => setState(() {}),
                            textInputAction: TextInputAction.search,
                            decoration: InputDecoration(
                              hintText: 'Search practice areas',
                              prefixIcon: const Icon(Icons.search_rounded, size: 21),
                              suffixIcon: query.isEmpty
                                  ? null
                                  : IconButton(
                                      icon: const Icon(Icons.close_rounded, size: 19),
                                      onPressed: () => setState(_search.clear),
                                    ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        _Counter(count: c.areas.length, limit: c.currentPlan?.areas),
                      ],
                    ),
                  ),
                ),
                if (shown.isEmpty)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 36, 20, 0),
                      child: Center(
                        child: Text(
                          'Nothing matches "${_search.text.trim()}".',
                          style: TextStyle(color: AppColors.inkMuted),
                        ),
                      ),
                    ),
                  )
                else
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
                    sliver: SliverGrid.builder(
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 2,
                        mainAxisSpacing: 12,
                        crossAxisSpacing: 12,
                        mainAxisExtent: 168,
                      ),
                      itemCount: shown.length,
                      itemBuilder: (context, i) {
                        final s = shown[i];
                        return _CategoryCard(
                          service: s,
                          selected: c.areas.contains(s.name),
                          chosenMatters: c.mattersIn(s),
                          onTap: () => _tap(c, s),
                          onMatters: () => _openMatters(c, s),
                        );
                      },
                    ),
                  ),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
                    child: OnbMessages(controller: c),
                  ),
                ),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(24, 10, 24, 24),
                    child: Text(
                      _planNote(c),
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 12.5, height: 1.45, color: AppColors.inkFaint),
                    ),
                  ),
                ),
              ],
            ),
      primaryLabel: c.areas.isEmpty ? 'Continue' : 'Continue · ${c.areas.length} selected',
      busy: c.saving,
      onPrimary: c.canContinueAreas ? c.continueAreas : null,
    );
  }

  /// What the current plan covers, so the limit is never a surprise.
  String _planNote(OnboardingController c) {
    final plan = c.currentPlan;
    if (plan == null) return 'You can change these later from your profile.';
    final n = plan.areas;
    final covers = n == null ? 'any number of practice areas' : '$n practice ${n == 1 ? 'area' : 'areas'}';
    return 'Your ${plan.name} plan covers $covers. Choose more and you can upgrade right here. '
        'You can change these later from your profile.';
  }
}

/// "2/2" — how many areas are chosen against what the plan covers ("∞" when it
/// covers any number).
class _Counter extends StatelessWidget {
  const _Counter({required this.count, required this.limit});

  final int count;
  final int? limit;

  @override
  Widget build(BuildContext context) {
    final full = limit != null && count >= limit!;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 13),
      decoration: BoxDecoration(
        color: count == 0 ? AppColors.surface : AppColors.accentSoft,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: count == 0 ? AppColors.border : AppColors.accent.withValues(alpha: 0.6)),
      ),
      child: Text(
        '$count/${limit ?? '∞'}',
        style: TextStyle(
          fontSize: 14.5,
          fontWeight: FontWeight.w800,
          color: full ? AppColors.warning : AppColors.primary,
        ),
      ),
    );
  }
}

/// One practice area. Unselected it is a white card with a navy icon; selected it
/// takes the theme's gold — a gold border and tick, and the icon tile turns navy
/// with a gold icon. Only the theme's colours are used; the icon tells the areas
/// apart.
class _CategoryCard extends StatelessWidget {
  const _CategoryCard({
    required this.service,
    required this.selected,
    required this.chosenMatters,
    required this.onTap,
    required this.onMatters,
  });

  final LegalService service;
  final bool selected;
  final int chosenMatters;
  final VoidCallback onTap;
  final VoidCallback onMatters;

  @override
  Widget build(BuildContext context) {
    final matterCount = service.subServices.length;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      decoration: BoxDecoration(
        color: selected ? AppColors.accentSoft : AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: selected ? AppColors.accent : AppColors.border, width: selected ? 1.8 : 1),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 12, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      height: 46,
                      width: 46,
                      decoration: BoxDecoration(
                        color: selected ? AppColors.primary : AppColors.primary.withValues(alpha: 0.07),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Icon(
                        categoryIconFor(service.name),
                        color: selected ? AppColors.accent : AppColors.primary,
                        size: 25,
                      ),
                    ),
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      height: 24,
                      width: 24,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: selected ? AppColors.accent : Colors.transparent,
                        border: Border.all(color: selected ? AppColors.accent : AppColors.borderStrong, width: 1.6),
                      ),
                      child: selected
                          ? const Icon(Icons.check_rounded, size: 16, color: AppColors.primaryDark)
                          : null,
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  service.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 15.5, height: 1.2, fontWeight: FontWeight.w700),
                ),
                const Spacer(),
                if (selected && matterCount > 0)
                  InkWell(
                    borderRadius: BorderRadius.circular(10),
                    onTap: onMatters,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: AppColors.accent.withValues(alpha: 0.55)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Flexible(
                            child: Text(
                              chosenMatters == 0 ? 'Choose matters' : '$chosenMatters chosen',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: AppColors.primary),
                            ),
                          ),
                          const Icon(Icons.chevron_right_rounded, size: 16, color: AppColors.primary),
                        ],
                      ),
                    ),
                  )
                else
                  Text(
                    matterCount == 0 ? 'General practice' : '$matterCount matters',
                    style: TextStyle(fontSize: 12.5, color: AppColors.inkFaint),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The matters under one practice area — optional, and tapped like chips. Uses
/// the theme's bottom-sheet shape.
class _MattersSheet extends StatelessWidget {
  const _MattersSheet({required this.service});

  final LegalService service;

  @override
  Widget build(BuildContext context) {
    final c = context.watch<OnboardingController>();

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Center(
            child: Container(
              height: 4,
              width: 40,
              decoration: BoxDecoration(color: AppColors.ink.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(4)),
            ),
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Container(
                height: 44,
                width: 44,
                decoration: BoxDecoration(color: AppColors.primary, borderRadius: BorderRadius.circular(13)),
                child: Icon(categoryIconFor(service.name), color: AppColors.accent),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  service.name,
                  style: const TextStyle(fontFamily: AppText.display, fontSize: 20, fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Optional — tell clients which matters you handle most.',
            style: TextStyle(fontSize: 13.5, color: AppColors.inkMuted),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final m in service.subServices)
                SelectableChip(
                  label: m.name,
                  selected: c.matters.contains(m.name),
                  onTap: () => pickOrUpgrade(
                    context,
                    c,
                    pick: () => c.toggleMatter(m.name),
                    reason: () => c.matterUpgradeReason(m.name),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 20),
          PrimaryButton(label: 'Done', onPressed: () => Navigator.of(context).pop()),
        ],
      ),
    );
  }
}
