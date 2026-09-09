import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/widgets/states.dart';
import '../../state/auth_controller.dart';
import 'wallet_tab.dart';

/// The wallet as a section of its own.
///
/// A thin frame around [WalletTab], which holds the balance, the top-up and the
/// ledger. The split is deliberate: the tab is also reachable from the account
/// screen, and the money handling should exist once however it is reached.
///
/// Only a client has a wallet. A lawyer earns rather than tops up, and their
/// earnings are on their dashboard — so this says so plainly instead of showing
/// them an empty balance they can never fill.
class WalletScreen extends StatelessWidget {
  const WalletScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthController>();

    final Widget body;
    if (auth.isUser) {
      body = const WalletTab();
    } else if (auth.isAdvocate) {
      body = EmptyView(
        icon: Icons.payments_outlined,
        title: 'Your earnings are on the dashboard',
        message: 'A wallet is a client’s prepaid balance. What you have earned '
            'from consultations is on your dashboard.',
        action: FilledButton(
          onPressed: () => context.go('/dashboard'),
          child: const Text('Open dashboard'),
        ),
      );
    } else {
      body = EmptyView(
        icon: Icons.account_balance_wallet_outlined,
        title: 'Sign in to use your wallet',
        message: 'Consultations are paid from a prepaid balance, billed by the '
            'minute. Nothing is charged until a lawyer accepts.',
        action: FilledButton(
          onPressed: () => context.push('/login?redirect=/wallet'),
          child: const Text('Sign in'),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Wallet')),
      body: body,
    );
  }
}
