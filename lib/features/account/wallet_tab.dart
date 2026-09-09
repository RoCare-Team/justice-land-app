import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/config/app_config.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../core/utils/validators.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/states.dart';
import '../../models/account.dart';
import '../../state/wallet_controller.dart';

/// The wallet: balance, top-up and the ledger.
///
/// Money only enters through a Razorpay payment the server has verified. The
/// app opens an order, runs checkout, and hands the signed result back — it
/// never tells the server an amount to credit.
class WalletTab extends StatefulWidget {
  const WalletTab({super.key});

  @override
  State<WalletTab> createState() => _WalletTabState();
}

class _WalletTabState extends State<WalletTab> {
  final _amount = TextEditingController();
  String _error = '';
  String _notice = '';

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  Future<void> _topUp() async {
    final error = Validators.topUp(
      _amount.text,
      min: AppConfig.minTopUp,
      max: AppConfig.maxTopUp,
    );
    if (error != null) {
      setState(() {
        _error = error;
        _notice = '';
      });
      return;
    }

    setState(() {
      _error = '';
      _notice = '';
    });

    final amount = num.parse(_amount.text.trim()).round();
    final result = await context.read<WalletController>().topUp(amount);

    if (!mounted) return;
    switch (result.outcome) {
      case TopUpOutcome.success:
        _amount.clear();
        setState(() => _notice = result.message);
        Toast.success(context, result.message);
      case TopUpOutcome.pending:
        // Authorised but not captured — the money is held, not taken. Saying
        // "done" would be a lie; saying "failed" would make someone pay twice.
        _amount.clear();
        setState(() => _notice = result.message);
        Toast.show(context, result.message);
      case TopUpOutcome.cancelled:
        setState(() => _notice = result.message);
      case TopUpOutcome.failed:
        setState(() => _error = result.message);
        Toast.error(context, result.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final wallet = context.watch<WalletController>();

    if (wallet.loading && wallet.transactions.isEmpty) {
      return const SkeletonList(count: 4, height: 84);
    }

    return RefreshIndicator(
      onRefresh: () => wallet.load(silent: true),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
        children: [
          _balanceCard(wallet.balance),
          const SizedBox(height: 16),
          _addMoneyCard(wallet),
          const SizedBox(height: 22),
          Text('Transaction history',
              style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 10),
          if (wallet.transactions.isEmpty)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 34),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: AppColors.border,
                  style: BorderStyle.solid,
                ),
              ),
              child: Column(
                children: [
                  Icon(Icons.receipt_long_outlined, size: 26, color: AppColors.inkFaint),
                  const SizedBox(height: 10),
                  Text(
                    'No transactions yet',
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                      color: AppColors.inkMuted,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    'Money you add will show up here.',
                    style: TextStyle(fontSize: 12, color: AppColors.inkFaint),
                  ),
                ],
              ),
            )
          else
            for (final txn in wallet.transactions)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _transactionTile(txn),
              ),
        ],
      ),
    );
  }

  Widget _balanceCard(int balance) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.primary, AppColors.secondary],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.account_balance_wallet_outlined,
                  size: 16, color: Colors.white70),
              const SizedBox(width: 7),
              Text(
                'AVAILABLE BALANCE',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.1,
                  color: Colors.white.withOpacity(0.75),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            Fmt.money(balance),
            style: const TextStyle(
              fontSize: 36,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  Widget _addMoneyCard(WalletController wallet) {
    return SectionCard(
      title: 'Add money',
      icon: Icons.add_circle_outline_rounded,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final amount in AppConfig.quickTopUps)
                SelectableChip(
                  label: Fmt.money(amount),
                  selected: _amount.text == '$amount',
                  onTap: () => setState(() {
                    _amount.text = '$amount';
                    _error = '';
                  }),
                ),
            ],
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _amount,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            onChanged: (_) => setState(() => _error = ''),
            decoration: InputDecoration(
              labelText: 'Enter amount',
              hintText: 'Minimum ${Fmt.money(AppConfig.minTopUp)}',
              prefixText: '₹  ',
              errorText: _error.isEmpty ? null : _error,
            ),
          ),
          const SizedBox(height: 14),
          PrimaryButton(
            label: 'Add money',
            icon: Icons.add_rounded,
            busy: wallet.paying,
            onPressed: _topUp,
          ),
          if (_notice.isNotEmpty) ...[
            const SizedBox(height: 12),
            NoticeBanner(
              message: _notice,
              tone: ChipTone.success,
              icon: Icons.check_circle_outline_rounded,
            ),
          ],
          const SizedBox(height: 12),
          Text(
            'Payments are handled by Razorpay — cards, UPI, net banking and wallets.',
            style: TextStyle(fontSize: 11.5, height: 1.4, color: AppColors.inkFaint),
          ),
        ],
      ),
    );
  }

  Widget _transactionTile(WalletTransaction txn) {
    final credit = txn.isCredit;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Container(
            height: 36,
            width: 36,
            decoration: BoxDecoration(
              color: (credit ? AppColors.success : AppColors.danger).withOpacity(0.10),
              borderRadius: BorderRadius.circular(11),
            ),
            child: Icon(
              credit ? Icons.south_west_rounded : Icons.north_east_rounded,
              size: 17,
              color: credit ? AppColors.success : AppColors.danger,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  txn.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                ),
                Text(
                  Fmt.date(txn.createdAt),
                  style: TextStyle(fontSize: 12, color: AppColors.inkFaint),
                ),
              ],
            ),
          ),
          Text(
            '${credit ? '+' : '−'}${Fmt.money(txn.amount)}',
            style: TextStyle(
              fontSize: 14.5,
              fontWeight: FontWeight.w700,
              color: credit ? AppColors.success : AppColors.danger,
            ),
          ),
        ],
      ),
    );
  }
}
