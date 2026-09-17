import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/network/api_exception.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/states.dart';
import '../../models/legal_query.dart';
import '../../services/membership_service.dart';
import '../../state/auth_controller.dart';
import '../../state/membership_checkout.dart';
import '../../state/queries_controller.dart';
import 'lawyer_widgets.dart';

/// The lawyer's membership: what they are on, and buying a plan.
///
/// Purchase is the website's three steps, unchanged — the server opens an
/// order for the plan's yearly price, Razorpay takes the payment, and the
/// server verifies it with Razorpay before granting anything. The app sends a
/// plan id, never an amount.
class LawyerPlanScreen extends StatefulWidget {
  const LawyerPlanScreen({super.key});

  @override
  State<LawyerPlanScreen> createState() => _LawyerPlanScreenState();
}

class _LawyerPlanScreenState extends State<LawyerPlanScreen> {
  PlanCatalog? _catalog;
  ApiException? _error;
  bool _loading = true;

  String _buying = '';
  late final MembershipCheckout _checkout;

  @override
  void initState() {
    super.initState();
    _checkout = MembershipCheckout(context.read<MembershipService>());
    _load();
  }

  @override
  void dispose() {
    _checkout.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = _catalog == null;
      _error = null;
    });
    try {
      final catalog = await context.read<MembershipService>().catalog();
      if (!mounted) return;
      setState(() {
        _catalog = catalog;
        _loading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  Future<void> _buy(MembershipPlan plan) async {
    if (_buying.isNotEmpty) return;
    setState(() => _buying = plan.id);
    final result = await _checkout.buy(plan.id, planLabel: plan.name);
    if (!mounted) return;
    setState(() => _buying = '');
    switch (result.outcome) {
      case PlanPurchaseOutcome.success:
        // The plan changes credits, listing limits and placement — re-read all.
        unawaited(context.read<AuthController>().refresh());
        unawaited(context.read<QueriesController>().refresh(silent: true));
        await _load();
        if (mounted) Toast.success(context, result.message);
      case PlanPurchaseOutcome.pending:
      case PlanPurchaseOutcome.cancelled:
        Toast.show(context, result.message);
        unawaited(_load());
      case PlanPurchaseOutcome.failed:
        Toast.error(context, result.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final catalog = _catalog;
    return LawyerPage(
      title: 'My Plan',
      body: _loading
          ? const SkeletonList(count: 3, height: 200)
          : catalog == null
              ? ErrorView(message: _error?.message ?? 'Could not load plans.', isNetwork: _error?.isNetwork ?? false, onRetry: _load)
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: EdgeInsets.fromLTRB(16, 14, 16, bottomGutter(context)),
                    children: [
                      _current(catalog),
                      const SizedBox(height: 16),
                      for (final plan in catalog.plans) ...[
                        _planCard(catalog, plan),
                        const SizedBox(height: 12),
                      ],
                      Text(
                        'Prices include 18% GST. A plan runs for twelve months and does not renew on its own. '
                        'Consultations, rates and earnings are the same on every plan.',
                        style: TextStyle(fontSize: 12, height: 1.45, color: AppColors.inkFaint),
                      ),
                    ],
                  ),
                ),
    );
  }

  Widget _current(PlanCatalog c) {
    final paid = c.currentPlanId != 'free';
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.primaryLight, AppColors.primaryDark],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('You are on', style: TextStyle(fontSize: 12.5, color: Colors.white60)),
          const SizedBox(height: 2),
          Row(
            children: [
              Icon(_planIcon(c.currentPlanId), color: AppColors.accent, size: 24),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  c.currentPlanName,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontFamily: AppText.display, fontSize: 24, fontWeight: FontWeight.w700, color: Colors.white),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            paid && c.expiresAt != null ? 'Valid till ${Fmt.date(c.expiresAt)}' : 'Free plan — no client queries',
            style: const TextStyle(fontSize: 13, color: Colors.white70),
          ),
          if (c.credits.hasPlan) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(color: Colors.white12, borderRadius: BorderRadius.circular(12)),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.toll_rounded, size: 18, color: AppColors.accent),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      '${c.credits.left} of ${c.credits.allowance} query credits left this month',
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.white),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _planCard(PlanCatalog c, MembershipPlan plan) {
    final isCurrent = c.currentPlanId == plan.id;
    final currentRank = c.plans.indexWhere((p) => p.id == c.currentPlanId);
    final rank = c.plans.indexOf(plan);
    final isUpgrade = rank > currentRank;
    final top = plan.id == 'premium';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: isCurrent ? AppColors.primary : (top ? AppColors.accent : AppColors.border), width: isCurrent || top ? 1.6 : 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(_planIcon(plan.id), color: top ? AppColors.accent : AppColors.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(plan.name, style: const TextStyle(fontFamily: AppText.display, fontSize: 19, fontWeight: FontWeight.w700)),
              ),
              if (isCurrent)
                const StatusChip(label: 'Current', tone: ChipTone.info)
              else if (top)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(color: AppColors.accent, borderRadius: BorderRadius.circular(999)),
                  child: const Text('BEST', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, color: Color(0xFF241B02))),
                ),
            ],
          ),
          if (plan.tagline.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(plan.tagline, style: TextStyle(fontSize: 12.5, color: AppColors.inkMuted)),
          ],
          const SizedBox(height: 10),
          if (plan.isFree)
            const Text('Free', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800))
          else ...[
            Text.rich(
              TextSpan(children: [
                TextSpan(text: Fmt.money(plan.monthly), style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
                TextSpan(text: ' /month', style: TextStyle(fontSize: 13, color: AppColors.inkFaint)),
              ]),
            ),
            Text(
              'Billed yearly — ${Fmt.money(plan.yearBase)} + ${Fmt.money(plan.yearGst)} GST = ${Fmt.money(plan.yearTotal)}',
              style: TextStyle(fontSize: 12, color: AppColors.inkFaint),
            ),
          ],
          if (plan.queryCredits > 0) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(color: AppColors.successSoft, borderRadius: BorderRadius.circular(10)),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.toll_rounded, size: 16, color: Color(0xFF047857)),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      '${plan.queryCredits} client query credits every month',
                      style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: Color(0xFF047857)),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 10),
          for (final f in plan.features)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.check_rounded, size: 16, color: AppColors.success),
                  const SizedBox(width: 8),
                  Expanded(child: Text(f, style: const TextStyle(fontSize: 13, height: 1.35))),
                ],
              ),
            ),
          if (!plan.isFree) ...[
            const SizedBox(height: 12),
            PrimaryButton(
              label: isCurrent ? 'Renew for 12 months' : (isUpgrade ? 'Upgrade to ${plan.name}' : 'Switch to ${plan.name}'),
              busy: _buying == plan.id,
              onPressed: _buying.isEmpty ? () => _buy(plan) : null,
            ),
          ],
        ],
      ),
    );
  }

  IconData _planIcon(String id) => switch (id) {
        'premium' => Icons.workspace_premium_rounded,
        'professional' => Icons.auto_awesome_rounded,
        _ => Icons.shield_outlined,
      };
}
