import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/network/api_exception.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/states.dart';
import '../../models/marketplace.dart';
import '../../state/auth_controller.dart';
import '../../state/marketplace_controller.dart';

/// The order summary: what you are buying, where it goes, and what it costs.
///
/// Every figure on this screen is re-fetched from the server whenever anything
/// that could change it changes — the coupon, the wallet switch. Nothing here
/// adds up a total locally, because a total the phone computed is a total that
/// can disagree with the one actually charged, and the client would be right
/// to trust the screen over the receipt.
class OrderSummaryScreen extends StatefulWidget {
  const OrderSummaryScreen({super.key, required this.slug});

  final String slug;

  @override
  State<OrderSummaryScreen> createState() => _OrderSummaryScreenState();
}

class _OrderSummaryScreenState extends State<OrderSummaryScreen> {
  final _coupon = TextEditingController();
  final _notes = TextEditingController();

  ServiceProduct? _service;
  ServiceQuote? _quote;
  BillingAddress _address = BillingAddress.empty;

  bool _loading = true;
  bool _repricing = false;
  bool _useWallet = false;
  String? _error;
  String _couponError = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _coupon.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final auth = context.read<AuthController>();
    final market = context.read<MarketplaceController>();

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final service = await market.detail(widget.slug);
      final quote = await market.quote(slug: widget.slug);
      if (!mounted) return;

      // Prefill from the saved address, falling back to the account's own name
      // and number so a first-time buyer is not typing in what we already know.
      final saved = auth.user?.billingAddress ?? BillingAddress.empty;
      setState(() {
        _service = service;
        _quote = quote;
        _address = saved.copyWith(
          name: saved.name.isNotEmpty ? saved.name : (auth.user?.name ?? ''),
          phone: saved.phone.isNotEmpty ? saved.phone : (auth.user?.phone ?? ''),
          email: saved.email.isNotEmpty ? saved.email : (auth.user?.email ?? ''),
        );
        _loading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _loading = false;
      });
    }
  }

  /// Ask the server for the price again. Called on every change that could
  /// move it, so the breakdown on screen is never one edit out of date.
  Future<void> _reprice() async {
    if (_service == null) return;
    setState(() => _repricing = true);
    try {
      final quote = await context.read<MarketplaceController>().quote(
            slug: widget.slug,
            couponCode: _coupon.text,
            useWallet: _useWallet,
          );
      if (!mounted) return;
      setState(() {
        _quote = quote;
        _couponError = quote.couponError;
        _repricing = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _repricing = false);
      Toast.error(context, e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthController>();
    final market = context.watch<MarketplaceController>();
    final service = _service;
    final quote = _quote;

    return Scaffold(
      backgroundColor: AppColors.muted,
      appBar: AppBar(title: const Text('Order summary')),
      body: _loading
          ? const LoadingView(label: 'Preparing your order…')
          : service == null || quote == null
              ? ErrorView(
                  message: _error ?? 'This order could not be prepared.',
                  onRetry: _load,
                )
              : ListView(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
                  children: [
                    _serviceRow(service),
                    const SizedBox(height: 16),
                    // Three different situations, and they used to be one
                    // error screen. A visitor needs a sign-in link; a lawyer
                    // needs telling that ordering takes a client account,
                    // because signing in again as themselves will not help;
                    // a client needs nothing here at all.
                    if (auth.isAdvocate) ...[
                      const NoticeBanner(
                        message:
                            'You are signed in as a lawyer. Legal services are '
                            'bought from a client account — sign out and sign in '
                            'with a client number to order this.',
                        tone: ChipTone.warning,
                        icon: Icons.info_outline_rounded,
                      ),
                      const SizedBox(height: 16),
                    ] else if (!auth.isUser) ...[
                      NoticeBanner(
                        message:
                            'Sign in to place this order. Your details and wallet '
                            'balance come with your account.',
                        tone: ChipTone.info,
                        icon: Icons.lock_outline_rounded,
                        action: TextButton(
                          onPressed: () => context.push(
                            '/login?redirect=/services/${service.slug}/order',
                          ),
                          child: const Text('Sign in'),
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],
                    // No point collecting an address from someone who cannot
                    // order yet — and nowhere to save it to.
                    if (auth.isUser) ...[
                      _addressCard(),
                      const SizedBox(height: 16),
                    ],
                    _couponCard(quote),
                    const SizedBox(height: 16),
                    if (auth.isUser) ...[
                      _walletCard(quote),
                      const SizedBox(height: 16),
                    ],
                    if (auth.isUser) ...[
                      _notesCard(),
                      const SizedBox(height: 16),
                    ],
                    _breakdown(quote),
                  ],
                ),
      bottomNavigationBar: service == null || quote == null
          ? null
          : _payBar(quote, market, auth),
    );
  }

  Widget _serviceRow(ServiceProduct service) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: _cardDecoration,
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.07),
              borderRadius: BorderRadius.circular(11),
            ),
            child: Icon(Icons.description_outlined,
                size: 21, color: AppColors.primary.withValues(alpha: 0.6)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  service.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w700,
                    height: 1.25,
                  ),
                ),
                if (service.turnaround.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(
                    service.turnaround,
                    style: TextStyle(
                      fontSize: 12,
                      color: AppColors.ink.withValues(alpha: 0.55),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _addressCard() {
    final complete = _address.isComplete;
    // The number came from OTP at sign-in, so it is the one field on this card
    // that is proven rather than typed. Saying so is worth a badge: it tells
    // the client which detail they do not need to check.
    final verified = context.read<AuthController>().user?.phone ?? '';
    final phoneIsVerified =
        verified.isNotEmpty && _address.phone.replaceAll(' ', '').endsWith(verified);

    // An invoice needs a name and an email to go to. Missing either is not
    // worth blocking the order over — the work still gets done — but it is
    // worth saying now rather than after they have paid.
    final missingInvoice = complete &&
        (_address.name.trim().isEmpty || _address.email.trim().isEmpty);

    return Container(
      decoration: _cardDecoration,
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 8, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Billing details',
                        style: TextStyle(
                            fontSize: 14.5, fontWeight: FontWeight.w700),
                      ),
                    ),
                    TextButton.icon(
                      onPressed: _editAddress,
                      icon: const Icon(Icons.edit_outlined, size: 15),
                      label: Text(complete ? 'Edit' : 'Add'),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                if (!complete)
                  Text(
                    'We need a name, mobile number and address before this can '
                    'be ordered.',
                    style: TextStyle(
                      fontSize: 12.5,
                      height: 1.45,
                      color: AppColors.ink.withValues(alpha: 0.55),
                    ),
                  )
                else ...[
                  Text(
                    _address.name.trim().isEmpty ? 'Name not set' : _address.name,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: _address.name.trim().isEmpty
                          ? AppColors.warning
                          : AppColors.ink,
                    ),
                  ),
                  const SizedBox(height: 6),
                  _line(
                    Icons.mail_outline_rounded,
                    _address.email.trim().isEmpty
                        ? 'Email not added'
                        : _address.email,
                    muted: _address.email.trim().isEmpty,
                  ),
                  _line(
                    Icons.phone_outlined,
                    _address.phone,
                    trailing: phoneIsVerified ? const _VerifiedPill() : null,
                  ),
                  _line(Icons.location_on_outlined, _address.oneLine),
                  if (_address.gstin.isNotEmpty)
                    _line(Icons.receipt_long_outlined, 'GSTIN ${_address.gstin}'),
                ],
              ],
            ),
          ),
          if (missingInvoice)
            InkWell(
              onTap: _editAddress,
              child: Container(
                width: double.infinity,
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                color: AppColors.warningSoft,
                child: Row(
                  children: [
                    const Icon(Icons.info_outline_rounded,
                        size: 16, color: AppColors.warning),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                        'Add your name & email to receive your invoice',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: AppColors.warning,
                        ),
                      ),
                    ),
                    const Text(
                      'Add →',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: AppColors.warning,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// One line of the address block: icon, text, optional badge.
  Widget _line(
    IconData icon,
    String text, {
    bool muted = false,
    Widget? trailing,
  }) {
    if (text.trim().isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon,
              size: 14,
              color: muted
                  ? AppColors.warning
                  : AppColors.ink.withValues(alpha: 0.45)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 12.5,
                height: 1.4,
                color: muted
                    ? AppColors.warning
                    : AppColors.ink.withValues(alpha: 0.72),
              ),
            ),
          ),
          if (trailing != null) ...[const SizedBox(width: 8), trailing],
        ],
      ),
    );
  }

  Future<void> _editAddress() async {
    final updated = await showModalBottomSheet<BillingAddress>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _AddressSheet(initial: _address),
    );
    if (updated == null || !mounted) return;

    setState(() => _address = updated);

    // Saved to the account as well, so the next order prefills from it. A
    // failure here is not fatal — the order carries its own copy either way.
    final auth = context.read<AuthController>();
    if (auth.isUser) {
      final ok = await auth.setBillingAddress(updated);
      if (!ok && mounted && auth.error != null) {
        Toast.error(context, auth.error!);
      }
    }
  }

  Widget _couponCard(ServiceQuote quote) {
    final applied = quote.coupon;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: _cardDecoration,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.local_offer_outlined,
                  size: 17, color: AppColors.accent),
              const SizedBox(width: 8),
              const Text(
                'Coupon',
                style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700),
              ),
              const Spacer(),
              if (applied != null)
                TextButton(
                  onPressed: () {
                    _coupon.clear();
                    _reprice();
                  },
                  child: const Text('Remove'),
                ),
            ],
          ),
          const SizedBox(height: 8),
          if (applied != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: AppColors.successSoft,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                    color: AppColors.success.withValues(alpha: 0.25)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.check_circle_rounded,
                      size: 17, color: AppColors.success),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          applied.code,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: AppColors.success,
                          ),
                        ),
                        if (applied.label.isNotEmpty)
                          Text(
                            applied.label,
                            style: TextStyle(
                              fontSize: 11.5,
                              color: AppColors.ink.withValues(alpha: 0.6),
                            ),
                          ),
                      ],
                    ),
                  ),
                  Text(
                    '− ${Fmt.money(quote.amounts.discount)}',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: AppColors.success,
                    ),
                  ),
                ],
              ),
            )
          else
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _coupon,
                    textCapitalization: TextCapitalization.characters,
                    inputFormatters: [
                      // The server matches upper-case, and a phone keyboard
                      // that autocapitalises inconsistently should not be the
                      // reason a valid code is refused.
                      UpperCaseTextFormatter(),
                    ],
                    decoration: const InputDecoration(
                      hintText: 'Enter code',
                      isDense: true,
                    ),
                    onSubmitted: (_) => _reprice(),
                  ),
                ),
                const SizedBox(width: 10),
                OutlinedButton(
                  onPressed: _repricing ? null : _reprice,
                  child: const Text('Apply'),
                ),
              ],
            ),
          if (_couponError.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              _couponError,
              style: const TextStyle(fontSize: 12, color: AppColors.danger),
            ),
          ],
        ],
      ),
    );
  }

  Widget _walletCard(ServiceQuote quote) {
    final balance = quote.walletBalance;

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 4, 8, 4),
      decoration: _cardDecoration,
      child: SwitchListTile.adaptive(
        contentPadding: EdgeInsets.zero,
        value: _useWallet,
        onChanged: balance <= 0
            ? null
            : (value) {
                setState(() => _useWallet = value);
                _reprice();
              },
        title: const Text(
          'Use wallet balance',
          style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700),
        ),
        subtitle: Text(
          balance <= 0
              ? 'Your wallet is empty'
              : _useWallet && quote.amounts.walletUsed > 0
                  ? '${Fmt.money(quote.amounts.walletUsed)} of ${Fmt.money(balance)} will be used'
                  : 'Available: ${Fmt.money(balance)}',
          style: TextStyle(
            fontSize: 12.5,
            color: AppColors.ink.withValues(alpha: 0.6),
          ),
        ),
      ),
    );
  }

  Widget _notesCard() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: _cardDecoration,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Anything we should know?',
            style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _notes,
            maxLines: 3,
            maxLength: 500,
            decoration: const InputDecoration(
              hintText: 'Optional — details about your matter',
              isDense: true,
              counterText: '',
            ),
          ),
        ],
      ),
    );
  }

  /// The bill, line by line, exactly as the server sent it.
  Widget _breakdown(ServiceQuote quote) {
    final a = quote.amounts;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: _cardDecoration,
      child: Column(
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Price details',
                  style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700),
                ),
              ),
              if (_repricing)
                const SizedBox(
                  height: 14,
                  width: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
            ],
          ),
          const SizedBox(height: 12),
          _amountLine('Service fee', Fmt.money(a.base)),
          if (a.discount > 0)
            _amountLine(
              'Coupon discount',
              '− ${Fmt.money(a.discount)}',
              tone: AppColors.success,
            ),
          _amountLine('GST (${a.gstPercent}%)', Fmt.money(a.gst)),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 10),
            child: Divider(height: 1),
          ),
          _amountLine('Total', Fmt.money(a.payable), bold: true),
          if (a.walletUsed > 0) ...[
            const SizedBox(height: 6),
            _amountLine(
              'Paid from wallet',
              '− ${Fmt.money(a.walletUsed)}',
              tone: AppColors.success,
            ),
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 10),
              child: Divider(height: 1),
            ),
            _amountLine('To pay now', Fmt.money(a.razorpayAmount), bold: true),
          ],
        ],
      ),
    );
  }

  Widget _amountLine(String label, String value,
      {bool bold = false, Color? tone}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: bold ? 14.5 : 13,
                fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
                color: tone ?? AppColors.ink.withValues(alpha: bold ? 1 : 0.7),
              ),
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: bold ? 15.5 : 13,
              fontWeight: bold ? FontWeight.w800 : FontWeight.w600,
              color: tone ?? (bold ? AppColors.primary : AppColors.ink),
            ),
          ),
        ],
      ),
    );
  }

  Widget _payBar(
    ServiceQuote quote,
    MarketplaceController market,
    AuthController auth,
  ) {
    // Signed out there is no wallet, so the payable total is the whole bill;
    // `razorpayAmount` already equals it, but naming the intent keeps the bar
    // honest if that ever stops being true.
    final due = quote.amounts.razorpayAmount;
    final walletOnly = due <= 0 && quote.amounts.walletUsed > 0;

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        boxShadow: [
          BoxShadow(
            color: AppColors.ink.withValues(alpha: 0.08),
            blurRadius: 16,
            offset: const Offset(0, -3),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  walletOnly ? 'Wallet' : Fmt.money(due),
                  style: const TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.w800,
                    color: AppColors.primary,
                  ),
                ),
                Text(
                  walletOnly ? 'Covered in full' : 'Payable now',
                  style: TextStyle(
                    fontSize: 11,
                    color: AppColors.ink.withValues(alpha: 0.5),
                  ),
                ),
              ],
            ),
            const SizedBox(width: 16),
            Expanded(
              child: PrimaryButton(
                label: auth.isAdvocate
                    ? 'Client account needed'
                    : !auth.isUser
                        ? 'Sign in to order'
                        : walletOnly
                            ? 'Confirm order'
                            : 'Pay securely',
                busy: market.placing,
                icon: auth.isAdvocate ? null : Icons.lock_rounded,
                // Disabled rather than hidden: the price above is real and the
                // button explains what is missing. A lawyer tapping it would
                // only be sent to a sign-in they have already completed.
                onPressed: auth.isAdvocate
                    ? null
                    : auth.isUser
                        ? _placeOrder
                        : _signIn,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _signIn() {
    context.push('/login?redirect=/services/${widget.slug}/order');
  }

  Future<void> _placeOrder() async {
    if (!_address.isComplete) {
      Toast.error(context, 'Add your billing details before ordering.');
      await _editAddress();
      return;
    }

    final result = await context.read<MarketplaceController>().buy(
          slug: widget.slug,
          address: _address,
          couponCode: _coupon.text,
          useWallet: _useWallet,
          notes: _notes.text,
        );

    if (!mounted) return;

    switch (result.outcome) {
      case PurchaseOutcome.success:
        context.pushReplacement('/orders?placed=${result.order?.id ?? ''}');
        Toast.success(context, result.message);
      case PurchaseOutcome.pending:
        // The money is held, not taken. Sending them to their orders is
        // honest: the row is there, and it will turn confirmed on its own.
        context.pushReplacement('/orders');
        Toast.show(context, result.message);
      case PurchaseOutcome.cancelled:
        Toast.show(context, result.message);
      case PurchaseOutcome.failed:
        Toast.error(context, result.message);
    }
  }

  static final _cardDecoration = BoxDecoration(
    color: AppColors.surface,
    borderRadius: BorderRadius.circular(14),
    border: Border.all(color: AppColors.ink.withValues(alpha: 0.07)),
  );
}

/// "Verified", for the mobile number the account was created with.
class _VerifiedPill extends StatelessWidget {
  const _VerifiedPill();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: AppColors.successSoft,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.success.withValues(alpha: 0.3)),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.check_circle_rounded, size: 11, color: AppColors.success),
          SizedBox(width: 3),
          Text(
            'Verified',
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
              color: AppColors.success,
            ),
          ),
        ],
      ),
    );
  }
}

/// Upper-cases as you type, so a coupon matches however the keyboard behaved.
class UpperCaseTextFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) =>
      TextEditingValue(
        text: newValue.text.toUpperCase(),
        selection: newValue.selection,
      );
}

/// The billing-details form.
///
/// It collects only what the paperwork needs. There is no document upload
/// here: the server has nowhere to put one, and a field that quietly discards
/// what a client attaches is worse than no field at all.
class _AddressSheet extends StatefulWidget {
  const _AddressSheet({required this.initial});

  final BillingAddress initial;

  @override
  State<_AddressSheet> createState() => _AddressSheetState();
}

class _AddressSheetState extends State<_AddressSheet> {
  final _form = GlobalKey<FormState>();
  late final Map<String, TextEditingController> _fields;

  @override
  void initState() {
    super.initState();
    final a = widget.initial;
    _fields = {
      'name': TextEditingController(text: a.name),
      'phone': TextEditingController(text: a.phone),
      'email': TextEditingController(text: a.email),
      'line1': TextEditingController(text: a.line1),
      'line2': TextEditingController(text: a.line2),
      'city': TextEditingController(text: a.city),
      'state': TextEditingController(text: a.state),
      'pincode': TextEditingController(text: a.pincode),
      'gstin': TextEditingController(text: a.gstin),
    };
  }

  @override
  void dispose() {
    for (final c in _fields.values) {
      c.dispose();
    }
    super.dispose();
  }

  String _v(String key) => _fields[key]!.text.trim();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Container(
        decoration: const BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: const EdgeInsets.fromLTRB(18, 10, 18, 18),
        child: SingleChildScrollView(
          child: Form(
            key: _form,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: AppColors.ink.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Billing details',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 14),
                _field('name', 'Full name', required: true),
                _field(
                  'phone',
                  'Mobile number',
                  required: true,
                  keyboard: TextInputType.phone,
                  validator: (v) => v.length < 10 ? 'Enter a valid number' : null,
                ),
                _field('email', 'Email (optional)',
                    keyboard: TextInputType.emailAddress),
                _field('line1', 'Address line 1', required: true),
                _field('line2', 'Address line 2 (optional)'),
                Row(
                  children: [
                    Expanded(child: _field('city', 'City', required: true)),
                    const SizedBox(width: 12),
                    Expanded(child: _field('state', 'State', required: true)),
                  ],
                ),
                _field(
                  'pincode',
                  'PIN code',
                  required: true,
                  keyboard: TextInputType.number,
                  validator: (v) =>
                      RegExp(r'^\d{6}$').hasMatch(v) ? null : 'Six digits',
                ),
                _field(
                  'gstin',
                  'GSTIN (optional)',
                  upperCase: true,
                  // Blank is fine; a partly-typed one is not, because it goes
                  // on an invoice a business will try to claim credit against.
                  validator: (v) => v.isEmpty || v.length == 15
                      ? null
                      : 'A GSTIN is 15 characters',
                ),
                const SizedBox(height: 8),
                PrimaryButton(
                  label: 'Save details',
                  onPressed: () {
                    if (!(_form.currentState?.validate() ?? false)) return;
                    Navigator.of(context).pop(
                      BillingAddress(
                        name: _v('name'),
                        phone: _v('phone'),
                        email: _v('email'),
                        line1: _v('line1'),
                        line2: _v('line2'),
                        city: _v('city'),
                        state: _v('state'),
                        pincode: _v('pincode'),
                        gstin: _v('gstin').toUpperCase(),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _field(
    String key,
    String label, {
    bool required = false,
    bool upperCase = false,
    TextInputType? keyboard,
    String? Function(String)? validator,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextFormField(
        controller: _fields[key],
        keyboardType: keyboard,
        textCapitalization: upperCase
            ? TextCapitalization.characters
            : TextCapitalization.words,
        inputFormatters: upperCase ? [UpperCaseTextFormatter()] : null,
        decoration: InputDecoration(labelText: label, isDense: true),
        validator: (raw) {
          final value = (raw ?? '').trim();
          if (required && value.isEmpty) return 'Required';
          if (validator != null && (required || value.isNotEmpty)) {
            return validator(value);
          }
          return null;
        },
      ),
    );
  }
}
