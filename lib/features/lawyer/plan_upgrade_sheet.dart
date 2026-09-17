import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/states.dart';
import '../../models/legal_query.dart';
import '../../services/membership_service.dart';
import '../../state/auth_controller.dart';
import '../../state/membership_checkout.dart';

/// The plans, over the form the lawyer was filling in — the app's version of
/// the website's PlanUpgradeModal.
///
/// It opens the moment a practice area or matter will not tick because the
/// plan does not cover it. Only upgrades are offered, and paying happens right
/// here: the sheet closes with `true` once the server has granted the plan, and
/// the caller widens its limits in place so the chip that refused simply works.
class PlanUpgradeSheet extends StatefulWidget {
  const PlanUpgradeSheet({super.key, required this.catalog, required this.reason});

  final PlanCatalog catalog;

  /// What they were trying to do, e.g. "Your Starter plan covers 2 practice areas."
  final String reason;

  static Future<bool> open(
    BuildContext context, {
    required PlanCatalog catalog,
    required String reason,
  }) async {
    final upgraded = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useRootNavigator: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => PlanUpgradeSheet(catalog: catalog, reason: reason),
    );
    return upgraded ?? false;
  }

  @override
  State<PlanUpgradeSheet> createState() => _PlanUpgradeSheetState();
}

class _PlanUpgradeSheetState extends State<PlanUpgradeSheet> {
  late final MembershipCheckout _checkout;
  String _buying = '';
  String _error = '';

  @override
  void initState() {
    super.initState();
    _checkout = MembershipCheckout(context.read<MembershipService>());
  }

  @override
  void dispose() {
    _checkout.dispose();
    super.dispose();
  }

  Future<void> _buy(MembershipPlan plan) async {
    if (_buying.isNotEmpty) return;
    setState(() {
      _buying = plan.id;
      _error = '';
    });
    final result = await _checkout.buy(plan.id, planLabel: plan.name);
    if (!mounted) return;
    setState(() => _buying = '');
    switch (result.outcome) {
      case PlanPurchaseOutcome.success:
        await context.read<AuthController>().refresh();
        if (!mounted) return;
        Toast.success(context, result.message);
        Navigator.of(context).pop(true);
      case PlanPurchaseOutcome.pending:
        Toast.show(context, result.message);
        Navigator.of(context).pop(false);
      case PlanPurchaseOutcome.cancelled:
        break;
      case PlanPurchaseOutcome.failed:
        setState(() => _error = result.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final plans = widget.catalog.plans;
    final currentIndex = plans.indexWhere((p) => p.id == widget.catalog.currentPlanId);
    final upgrades = [
      for (var i = 0; i < plans.length; i++)
        if (i > currentIndex && !plans[i].isFree) plans[i],
    ];

    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                height: 4,
                width: 40,
                decoration: BoxDecoration(color: AppColors.ink.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(4)),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Container(
                  height: 44,
                  width: 44,
                  decoration: BoxDecoration(color: AppColors.accentSoft, borderRadius: BorderRadius.circular(12)),
                  child: const Icon(Icons.lock_open_rounded, color: AppColors.primary),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    'Upgrade to add more',
                    style: TextStyle(fontFamily: AppText.display, fontSize: 20, fontWeight: FontWeight.w700),
                  ),
                ),
                IconButton(
                  onPressed: _buying.isEmpty ? () => Navigator.of(context).pop(false) : null,
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(widget.reason, style: TextStyle(fontSize: 14, height: 1.45, color: AppColors.inkMuted)),
            const SizedBox(height: 16),
            if (upgrades.isEmpty)
              const NoticeBanner(
                tone: ChipTone.info,
                message: 'You are already on the top plan.',
              )
            else
              for (final plan in upgrades) ...[
                _planCard(plan),
                const SizedBox(height: 12),
              ],
            if (_error.isNotEmpty) ...[
              NoticeBanner(tone: ChipTone.danger, icon: Icons.error_outline_rounded, message: _error),
              const SizedBox(height: 12),
            ],
            Text(
              'Prices include 18% GST and cover twelve months. Your selections stay as they are while you pay.',
              style: TextStyle(fontSize: 12, height: 1.45, color: AppColors.inkFaint),
            ),
          ],
        ),
      ),
    );
  }

  Widget _planCard(MembershipPlan plan) {
    final top = plan.id == 'premium';
    String limit(int? n, String word) => n == null ? 'Unlimited $word' : '$n $word';

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: top ? AppColors.accent : AppColors.border, width: top ? 1.6 : 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(top ? Icons.workspace_premium_rounded : Icons.auto_awesome_rounded,
                  color: top ? AppColors.accent : AppColors.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(plan.name, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
              ),
              Text.rich(
                TextSpan(children: [
                  TextSpan(text: Fmt.money(plan.monthly), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                  TextSpan(text: '/mo', style: TextStyle(fontSize: 12, color: AppColors.inkFaint)),
                ]),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              Tag(label: limit(plan.areas, 'practice areas')),
              Tag(label: limit(plan.matters, 'matters')),
              if (plan.queryCredits > 0) Tag(label: '${plan.queryCredits} query credits/month', tone: AppColors.success),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Billed yearly: ${Fmt.money(plan.yearTotal)}',
            style: TextStyle(fontSize: 12, color: AppColors.inkFaint),
          ),
          const SizedBox(height: 10),
          PrimaryButton(
            label: 'Upgrade to ${plan.name}',
            busy: _buying == plan.id,
            onPressed: _buying.isEmpty ? () => _buy(plan) : null,
          ),
        ],
      ),
    );
  }
}
