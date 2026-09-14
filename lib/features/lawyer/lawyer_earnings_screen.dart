import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/common.dart';
import '../../state/auth_controller.dart';
import '../../state/lawyer_controller.dart';
import 'lawyer_home_screen.dart' show WeekBars;
import 'lawyer_widgets.dart';

/// Earnings: the wallet balance, the chosen period against the one before,
/// the week as bars, earnings per channel, and every wallet transaction.
///
/// There is no withdraw button because the platform has no payout route —
/// a button that could not pay anyone out would be worse than none.
class LawyerEarningsScreen extends StatefulWidget {
  const LawyerEarningsScreen({super.key});

  @override
  State<LawyerEarningsScreen> createState() => _LawyerEarningsScreenState();
}

class _LawyerEarningsScreenState extends State<LawyerEarningsScreen> {
  static const _periods = [
    (days: 1, label: 'Today', compare: 'yesterday'),
    (days: 7, label: 'Last 7 days', compare: 'the previous 7 days'),
    (days: 30, label: 'Last 30 days', compare: 'the previous 30 days'),
  ];
  int _period = 1;

  @override
  Widget build(BuildContext context) {
    final lawyer = context.watch<LawyerController>();
    final advocate = context.watch<AuthController>().advocate;
    final p = _periods[_period];
    final now = lawyer.totalsFor(p.days);
    final before = lawyer.totalsFor(p.days, offset: p.days);
    final change = before.earned > 0 ? ((now.earned - before.earned) / before.earned * 100).round() : null;
    final transactions = [...lawyer.earnings.transactions]
      ..sort((a, b) => (b.createdAt ?? DateTime(0)).compareTo(a.createdAt ?? DateTime(0)));

    final byType = {
      for (final t in ['chat', 'audio', 'video'])
        t: lawyer.paid.where((c) => c.type.wire == t).fold<int>(0, (sum, c) => sum + c.price),
    };
    final best = byType.values.fold<int>(0, (m, v) => v > m ? v : m);

    return LawyerPage(
      title: 'Earnings',
      body: RefreshIndicator(
        onRefresh: lawyer.refreshAll,
        child: ListView(
          padding: EdgeInsets.fromLTRB(16, 16, 16, bottomGutter(context)),
          children: [
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(22),
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [AppColors.primaryLight, AppColors.primaryDark],
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Wallet Balance', style: TextStyle(color: Colors.white70, fontSize: 13)),
                        const SizedBox(height: 4),
                        Text(
                          Fmt.money(lawyer.earnings.balance),
                          style: const TextStyle(color: Colors.white, fontSize: 30, fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          'Credited when each paid consultation ends.',
                          style: TextStyle(color: Colors.white60, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  const CircleAvatar(
                    radius: 26,
                    backgroundColor: Colors.white12,
                    child: Icon(Icons.account_balance_wallet_rounded, color: AppColors.accent, size: 26),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            LCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Expanded(
                        child: Text('Total Earnings', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                      ),
                      DropdownButton<int>(
                        value: _period,
                        underline: const SizedBox.shrink(),
                        borderRadius: BorderRadius.circular(12),
                        items: [
                          for (var i = 0; i < _periods.length; i++)
                            DropdownMenuItem(value: i, child: Text(_periods[i].label, style: const TextStyle(fontSize: 13))),
                        ],
                        onChanged: (v) => setState(() => _period = v ?? _period),
                      ),
                    ],
                  ),
                  Text(Fmt.money(now.earned), style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 2),
                  if (change == null)
                    Text('No earnings in ${p.compare} to compare', style: TextStyle(fontSize: 12.5, color: AppColors.inkFaint))
                  else
                    Text(
                      '${change >= 0 ? '↑' : '↓'} ${change.abs()}% from ${p.compare}',
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: change >= 0 ? const Color(0xFF15803D) : AppColors.danger,
                      ),
                    ),
                  const SizedBox(height: 18),
                  Text('Last 7 days', style: TextStyle(fontSize: 12, color: AppColors.inkFaint)),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: WeekBars(days: lawyer.week, height: 110),
                    ),
                  ),
                  const SizedBox(height: 14),
                  const Divider(height: 1),
                  _row('Completed sessions', '${now.sessions}'),
                  _row('Minutes talked', '${now.minutes}'),
                  _row('Wallet balance', Fmt.money(lawyer.earnings.balance)),
                ],
              ),
            ),
            const SizedBox(height: 14),
            LCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('By channel', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 12),
                  for (final (key, label, icon, rate) in [
                    ('chat', 'Chat', Icons.chat_bubble_outline_rounded, advocate?.chatRate ?? 0),
                    ('audio', 'Audio Call', Icons.call_outlined, advocate?.audioRate ?? 0),
                    ('video', 'Video Call', Icons.videocam_outlined, advocate?.videoRate ?? 0),
                  ])
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Row(
                        children: [
                          Icon(icon, size: 20, color: AppColors.primary),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(child: Text(label, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600))),
                                    Text(Fmt.money(byType[key]), style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700)),
                                  ],
                                ),
                                const SizedBox(height: 5),
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(4),
                                  child: LinearProgressIndicator(
                                    value: best == 0 ? 0 : (byType[key] ?? 0) / best,
                                    minHeight: 6,
                                    backgroundColor: AppColors.ink.withValues(alpha: 0.06),
                                    color: AppColors.accent,
                                  ),
                                ),
                                const SizedBox(height: 3),
                                Text(rate > 0 ? 'Your rate ${Fmt.rate(rate)}' : 'Not offered',
                                    style: TextStyle(fontSize: 11, color: AppColors.inkFaint)),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            const SectionTitle(title: 'Recent Transactions', icon: Icons.receipt_long_outlined),
            if (!lawyer.earningsLoaded)
              const Center(child: Padding(padding: EdgeInsets.all(20), child: CircularProgressIndicator()))
            else if (transactions.isEmpty)
              const EmptyCard(
                icon: Icons.receipt_long_outlined,
                title: 'No transactions yet',
                message: 'Your first paid consultation will show up here.',
              )
            else
              LCard(
                padding: EdgeInsets.zero,
                child: Column(
                  children: [
                    for (var i = 0; i < transactions.length; i++) ...[
                      if (i > 0) Divider(height: 1, indent: 64, color: AppColors.border),
                      ListTile(
                        leading: CircleAvatar(
                          backgroundColor: transactions[i].isCredit ? AppColors.successSoft : AppColors.dangerSoft,
                          child: Icon(
                            transactions[i].isCredit ? Icons.south_west_rounded : Icons.north_east_rounded,
                            color: transactions[i].isCredit ? AppColors.success : AppColors.danger,
                            size: 20,
                          ),
                        ),
                        title: Text(
                          transactions[i].note.isEmpty ? 'Consultation earning' : transactions[i].note,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600),
                        ),
                        subtitle: Text(Fmt.dateTime(transactions[i].createdAt), style: TextStyle(fontSize: 11.5, color: AppColors.inkFaint)),
                        trailing: Text(
                          '${transactions[i].isCredit ? '+' : '−'}${Fmt.money(transactions[i].amount)}',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: transactions[i].isCredit ? const Color(0xFF15803D) : AppColors.danger,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _row(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Row(
        children: [
          Expanded(child: Text(label, style: TextStyle(fontSize: 13.5, color: AppColors.inkMuted))),
          Text(value, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}
