import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:razorpay_flutter/razorpay_flutter.dart';

import '../core/network/api_exception.dart';
import '../models/marketplace.dart';
import '../services/marketplace_service.dart';
import 'auth_controller.dart';

/// How a purchase ended, in the terms the screen has to report it.
enum PurchaseOutcome { success, pending, cancelled, failed }

class PurchaseResult {
  const PurchaseResult(this.outcome, this.message, {this.order});

  final PurchaseOutcome outcome;
  final String message;
  final ServiceOrder? order;
}

/// The legal-services marketplace: catalogue, orders, and the purchase.
///
/// The payment steps are the wallet top-up's, unchanged, because they are the
/// steps that make a payment safe:
///
///   1. the server opens the order — the wallet share is held, nothing charged
///   2. Razorpay's sheet takes the rest
///   3. the server verifies the signature with Razorpay and marks it paid
///
/// The app never sends a price. It sends a slug, a coupon code and whether to
/// spend the wallet, and reads back what the server decided — a client that
/// could name its own total is a client that could buy an incorporation for a
/// rupee.
class MarketplaceController extends ChangeNotifier {
  MarketplaceController(this._service, this._auth);

  final MarketplaceService _service;
  final AuthController _auth;

  ServiceCatalogue _catalogue = ServiceCatalogue.empty;

  /// The catalogue with no filter applied.
  ///
  /// Kept apart from [_catalogue] because two screens read this controller and
  /// want different things: the landing page must always show every shelf and
  /// the most-bought services overall, while the all-services list shows what
  /// the current filter matched. Sharing one list meant that filtering to
  /// "Documentation" and then going back left the landing page claiming the
  /// whole catalogue was four documents.
  ServiceCatalogue _all = ServiceCatalogue.empty;

  String _category = '';
  String _query = '';
  bool _loading = false;
  String? _error;

  List<ServiceOrder> _orders = const [];
  bool _ordersLoading = false;

  bool _placing = false;
  Razorpay? _razorpay;
  Completer<PurchaseResult>? _pending;
  ServiceOrder? _placedOrder;

  ServiceCatalogue get catalogue => _catalogue;

  /// What the current filter matched — the all-services list.
  List<ServiceProduct> get services => _catalogue.services;

  /// The whole catalogue, whatever the filter — the landing page.
  List<ServiceProduct> get allServices => _all.services;

  /// Every shelf. Read from the unfiltered load, so narrowing to one category
  /// never makes the other categories disappear from the picker.
  List<ServiceCategory> get categories => _all.categories;
  String get category => _category;
  String get query => _query;
  bool get loading => _loading;
  String? get error => _error;

  List<ServiceOrder> get orders => _orders;
  bool get ordersLoading => _ordersLoading;
  bool get placing => _placing;

  /// Orders still being worked on, for the badge on the orders tab.
  int get openOrderCount => _orders.where((o) => o.isOpen).length;

  // ── Catalogue ────────────────────────────────────────────────────────────

  Future<void> load({bool silent = false}) async {
    if (!silent) {
      _loading = true;
      notifyListeners();
    }
    try {
      _catalogue = await _service.catalogue(category: _category, query: _query);
      // An unfiltered read is also the freshest picture of the whole
      // catalogue, so it doubles as the landing page's copy.
      if (_category.isEmpty && _query.isEmpty) _all = _catalogue;
      _error = null;
    } on ApiException catch (e) {
      _error = e.message;
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  /// Choose a shelf.
  ///
  /// Tapping the shelf that is already open clears it, so a chip row is a
  /// toggle and there is always a way back to the whole catalogue. Pass
  /// [replace] to set the value outright instead — that is what an explicit
  /// "All" chip does, and what arriving on the screen with a category already
  /// chosen does, neither of which should toggle.
  Future<void> setCategory(String value, {bool replace = false}) async {
    final next = (!replace && _category == value) ? '' : value;
    if (next == _category) return;
    _category = next;
    await load();
  }

  Future<void> search(String value) async {
    if (value.trim() == _query) return;
    _query = value.trim();
    await load();
  }

  /// Back to the whole catalogue.
  ///
  /// The landing page needs this on every visit: its job is to show every
  /// shelf, and a category left set from a previous visit would hide most of
  /// them behind a filter the reader never chose on this screen.
  Future<void> clearFilters() async {
    _category = '';
    _query = '';
    await load();
  }

  /// The full record for one service. Always fetched rather than read from the
  /// list: the list endpoint leaves out the description, the documents and the
  /// steps, and a detail screen built from a card would show empty sections.
  Future<ServiceProduct> detail(String slug) => _service.detail(slug);

  Future<ServiceQuote> quote({
    required String slug,
    String couponCode = '',
    bool useWallet = false,
  }) =>
      _service.quote(slug: slug, couponCode: couponCode, useWallet: useWallet);

  // ── Orders ───────────────────────────────────────────────────────────────

  Future<void> loadOrders({bool silent = false}) async {
    if (!silent) {
      _ordersLoading = true;
      notifyListeners();
    }
    try {
      _orders = await _service.myOrders();
      _error = null;
    } on ApiException catch (e) {
      _error = e.message;
    } finally {
      _ordersLoading = false;
      notifyListeners();
    }
  }

  // ── Buying ───────────────────────────────────────────────────────────────

  /// Places the order and runs checkout if there is anything left to collect.
  ///
  /// Resolves only once the server has had its say. [PurchaseOutcome.pending]
  /// means the payment is authorised but not captured — the money is held, not
  /// taken. Calling that a success would be a lie and calling it a failure
  /// would send someone to pay twice, so it gets its own answer.
  Future<PurchaseResult> buy({
    required String slug,
    required BillingAddress address,
    String couponCode = '',
    bool useWallet = false,
    String notes = '',
  }) async {
    if (_placing) {
      return const PurchaseResult(
        PurchaseOutcome.failed,
        'An order is already being placed.',
      );
    }

    _placing = true;
    _error = null;
    notifyListeners();

    PlacedOrder placed;
    try {
      placed = await _service.place(
        slug: slug,
        address: address,
        couponCode: couponCode,
        useWallet: useWallet,
        notes: notes,
      );
    } on ApiException catch (e) {
      _placing = false;
      _error = e.message;
      notifyListeners();
      return PurchaseResult(PurchaseOutcome.failed, e.message);
    }

    _placedOrder = placed.order;

    // The wallet covered it outright, so there is no sheet to open and nothing
    // left to verify — the server already marked it paid.
    if (placed.paid || placed.checkout == null) {
      await _afterPurchase();
      _placing = false;
      notifyListeners();
      return PurchaseResult(
        PurchaseOutcome.success,
        'Order ${placed.order.reference} confirmed.',
        order: placed.order,
      );
    }

    final completer = Completer<PurchaseResult>();
    _pending = completer;

    _razorpay?.clear();
    final razorpay = Razorpay();
    _razorpay = razorpay;
    razorpay.on(Razorpay.EVENT_PAYMENT_SUCCESS, _onPaymentSuccess);
    razorpay.on(Razorpay.EVENT_PAYMENT_ERROR, _onPaymentError);
    razorpay.on(Razorpay.EVENT_EXTERNAL_WALLET, _onExternalWallet);

    final checkout = placed.checkout!;
    try {
      razorpay.open({
        'key': checkout.keyId,
        'order_id': checkout.orderId,
        'amount': checkout.amountPaise,
        'currency': checkout.currency,
        'name': 'Justiceland',
        'description': placed.order.serviceTitle,
        'prefill': {
          'name': checkout.prefillName,
          'email': checkout.prefillEmail,
          'contact': checkout.prefillContact,
        },
        'theme': {'color': '#1E3A5F'},
        'retry': {'enabled': true, 'max_count': 1},
      });
    } catch (_) {
      // The sheet never opened, so the order is holding wallet money for a
      // payment that cannot happen. Release it now rather than leaving the
      // client short until the server's sweep.
      await _release();
      _finish(const PurchaseResult(
        PurchaseOutcome.failed,
        'Could not open the payment screen. Please try again.',
      ));
    }

    return completer.future;
  }

  Future<void> _onPaymentSuccess(PaymentSuccessResponse response) async {
    try {
      final result = await _service.verify(
        orderId: response.orderId ?? '',
        paymentId: response.paymentId ?? '',
        signature: response.signature ?? '',
      );

      if (result.pending) {
        _finish(PurchaseResult(
          PurchaseOutcome.pending,
          result.message.isNotEmpty
              ? result.message
              : 'Payment received. Your order will be confirmed shortly.',
          order: result.order ?? _placedOrder,
        ));
        return;
      }

      await _afterPurchase();
      final order = result.order ?? _placedOrder;
      _finish(PurchaseResult(
        PurchaseOutcome.success,
        order == null
            ? 'Order confirmed.'
            : 'Order ${order.reference} confirmed.',
        order: order,
      ));
    } on ApiException catch (e) {
      // The payment went through but we could not confirm it. Never call this
      // a failure — the webhook is the safety net and will settle the order.
      _finish(PurchaseResult(
        PurchaseOutcome.pending,
        e.message.isNotEmpty
            ? e.message
            : 'We could not confirm the payment. If money was deducted your order will be updated shortly.',
        order: _placedOrder,
      ));
    }
  }

  void _onPaymentError(PaymentFailureResponse response) {
    // Razorpay reports a closed sheet as an error too, and a cancellation is
    // not a failure. Either way the order goes unpaid, so the wallet hold has
    // to come back.
    final cancelled = response.code == Razorpay.PAYMENT_CANCELLED;
    unawaited(_release());
    _finish(PurchaseResult(
      cancelled ? PurchaseOutcome.cancelled : PurchaseOutcome.failed,
      cancelled
          ? 'Payment cancelled.'
          : (response.message?.isNotEmpty ?? false)
              ? response.message!
              : 'Payment failed. Please try again.',
    ));
  }

  void _onExternalWallet(ExternalWalletResponse response) {
    // The sheet handed off to a wallet app; the outcome still arrives on the
    // success or error handler, so nothing is resolved here.
  }

  /// Hand back the wallet hold on an order that will not be paid.
  Future<void> _release() async {
    final order = _placedOrder;
    if (order == null || order.amounts.walletUsed <= 0) return;
    try {
      await _service.cancel(order.id);
      await _auth.refresh();
    } catch (_) {
      // The server sweeps stale holds after half an hour, so a failure here
      // delays the refund rather than losing it. Not worth an error the client
      // can do nothing about.
    }
  }

  /// The wallet may have been spent and there is a new order to show.
  Future<void> _afterPurchase() async {
    await _auth.refresh();
    await loadOrders(silent: true);
  }

  void _finish(PurchaseResult result) {
    _placing = false;
    _placedOrder = null;
    if (result.outcome == PurchaseOutcome.failed) _error = result.message;
    _razorpay?.clear();
    _razorpay = null;
    notifyListeners();
    final pending = _pending;
    _pending = null;
    if (pending != null && !pending.isCompleted) pending.complete(result);
  }

  void clearError() {
    if (_error == null) return;
    _error = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _razorpay?.clear();
    super.dispose();
  }
}
