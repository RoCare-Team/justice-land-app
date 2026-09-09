import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/states.dart';
import '../../models/marketplace.dart';
import '../../state/auth_controller.dart';
import '../../state/marketplace_controller.dart';

/// The client's service orders.
///
/// Separate from the consultations list on purpose. A consultation is a
/// session that happened; an order is a job being done, and the only thing a
/// client wants from this screen is where each one has got to.
class MyOrdersScreen extends StatefulWidget {
  const MyOrdersScreen({super.key, this.highlightId = ''});

  /// The order just placed, lifted to the top with its receipt open — so the
  /// screen answers "did it go through?" before anything has to be tapped.
  final String highlightId;

  @override
  State<MyOrdersScreen> createState() => _MyOrdersScreenState();
}

class _MyOrdersScreenState extends State<MyOrdersScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (context.read<AuthController>().isUser) {
        context.read<MarketplaceController>().loadOrders();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthController>();
    final market = context.watch<MarketplaceController>();

    return Scaffold(
      backgroundColor: AppColors.muted,
      appBar: AppBar(title: const Text('My orders')),
      body: !auth.isUser
          ? EmptyView(
              icon: Icons.lock_outline_rounded,
              title: 'Sign in to see your orders',
              message:
                  'Your service orders are tied to your account, so they follow your number rather than this phone.',
              action: FilledButton(
                onPressed: () => context.push('/login?redirect=/orders'),
                child: const Text('Sign in'),
              ),
            )
          : market.ordersLoading && market.orders.isEmpty
              ? const LoadingView(label: 'Loading your orders…')
              : market.orders.isEmpty
                  ? EmptyView(
                      icon: Icons.receipt_long_outlined,
                      title: 'No orders yet',
                      message:
                          'Fixed-price services you buy will show up here, with where each one has got to.',
                      action: FilledButton(
                        onPressed: () => context.go('/services'),
                        child: const Text('Browse services'),
                      ),
                    )
                  : RefreshIndicator(
                      onRefresh: () => market.loadOrders(silent: true),
                      child: ListView.separated(
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
                        itemCount: market.orders.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 12),
                        itemBuilder: (context, i) => _OrderCard(
                          order: market.orders[i],
                          startExpanded:
                              market.orders[i].id == widget.highlightId,
                        ),
                      ),
                    ),
    );
  }
}

class _OrderCard extends StatefulWidget {
  const _OrderCard({required this.order, this.startExpanded = false});

  final ServiceOrder order;
  final bool startExpanded;

  @override
  State<_OrderCard> createState() => _OrderCardState();
}

class _OrderCardState extends State<_OrderCard> {
  late bool _open = widget.startExpanded;

  @override
  Widget build(BuildContext context) {
    final order = widget.order;
    final a = order.amounts;

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.ink.withValues(alpha: 0.07)),
      ),
      child: Column(
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: () => setState(() => _open = !_open),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          order.serviceTitle,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 14.5,
                            fontWeight: FontWeight.w700,
                            height: 1.25,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${order.reference} · ${Fmt.date(order.createdAt)}',
                          style: TextStyle(
                            fontSize: 12,
                            color: AppColors.ink.withValues(alpha: 0.55),
                          ),
                        ),
                        const SizedBox(height: 9),
                        Row(
                          children: [
                            Tag(
                              label: order.statusLabel,
                              tone: _toneFor(order.status),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              Fmt.money(a.payable),
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w800,
                                color: AppColors.primary,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    _open
                        ? Icons.keyboard_arrow_up_rounded
                        : Icons.keyboard_arrow_down_rounded,
                    color: AppColors.ink.withValues(alpha: 0.4),
                  ),
                ],
              ),
            ),
          ),
          if (_open) ...[
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                children: [
                  _line('Service fee', Fmt.money(a.base)),
                  if (a.discount > 0)
                    _line(
                      order.couponCode.isEmpty
                          ? 'Discount'
                          : 'Coupon ${order.couponCode}',
                      '− ${Fmt.money(a.discount)}',
                      tone: AppColors.success,
                    ),
                  _line('GST (${a.gstPercent}%)', Fmt.money(a.gst)),
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 9),
                    child: Divider(height: 1),
                  ),
                  _line('Total paid', Fmt.money(a.payable), bold: true),
                  if (a.walletUsed > 0)
                    _line(
                      'From wallet',
                      Fmt.money(a.walletUsed),
                      tone: AppColors.success,
                    ),
                  if (order.address.oneLine.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Billed to',
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                          color: AppColors.ink.withValues(alpha: 0.5),
                        ),
                      ),
                    ),
                    const SizedBox(height: 3),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        '${order.address.name}\n${order.address.oneLine}',
                        style: TextStyle(
                          fontSize: 12.5,
                          height: 1.45,
                          color: AppColors.ink.withValues(alpha: 0.65),
                        ),
                      ),
                    ),
                  ],
                  if (order.notes.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Your note: ${order.notes}',
                        style: TextStyle(
                          fontSize: 12.5,
                          height: 1.45,
                          color: AppColors.ink.withValues(alpha: 0.65),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Color _toneFor(String status) => switch (status) {
        'completed' => AppColors.success,
        'inProgress' => AppColors.info,
        'paid' => AppColors.primary,
        'cancelled' || 'refunded' => AppColors.danger,
        _ => AppColors.warning,
      };

  Widget _line(String label, String value, {bool bold = false, Color? tone}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: bold ? 14 : 12.5,
                fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
                color: tone ?? AppColors.ink.withValues(alpha: bold ? 1 : 0.7),
              ),
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: bold ? 15 : 12.5,
              fontWeight: bold ? FontWeight.w800 : FontWeight.w600,
              color: tone ?? (bold ? AppColors.primary : AppColors.ink),
            ),
          ),
        ],
      ),
    );
  }
}
