import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:razorpay_flutter/razorpay_flutter.dart';

import '../core/network/api_exception.dart';
import '../models/account.dart';
import '../services/wallet_service.dart';
import 'auth_controller.dart';

/// The outcome of a top-up attempt, as the wallet screen needs to report it.
enum TopUpOutcome { success, pending, cancelled, failed }

class TopUpResult {
  const TopUpResult(this.outcome, this.message);

  final TopUpOutcome outcome;
  final String message;
}

/// Balance, ledger, and the Razorpay top-up.
///
/// The three steps are the web app's, unchanged, and the order matters:
///
///   1. the server opens an order — nothing charged, nothing credited
///   2. Razorpay's sheet takes the payment
///   3. the server verifies the signature with Razorpay and credits
///
/// The app never tells the server how much to credit. It hands back what
/// Razorpay signed and lets the server decide, because a client that can name
/// the amount is a client that can mint balance.
class WalletController extends ChangeNotifier {
  WalletController(this._service, this._auth);

  final WalletService _service;
  final AuthController _auth;

  Wallet _wallet = Wallet.empty;
  bool _loading = false;
  bool _paying = false;
  String? _error;

  Razorpay? _razorpay;
  Completer<TopUpResult>? _pending;
  WalletOrder? _order;

  Wallet get wallet => _wallet;
  int get balance => _wallet.balance;
  List<WalletTransaction> get transactions => _wallet.transactions;
  bool get loading => _loading;
  bool get paying => _paying;
  String? get error => _error;

  Future<void> load({bool silent = false}) async {
    if (!silent) {
      _loading = true;
      notifyListeners();
    }
    try {
      _wallet = await _service.read();
      _auth.applyWallet(_wallet);
      _error = null;
    } on ApiException catch (e) {
      _error = e.message;
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  /// Runs the whole top-up and resolves once the server has had its say.
  ///
  /// Returns [TopUpOutcome.pending] when the payment is authorised but not yet
  /// captured — the money is held, not taken. Saying "done" there would be a
  /// lie, and saying "failed" would send someone to pay twice.
  Future<TopUpResult> topUp(int amountRupees) async {
    if (_paying) {
      return const TopUpResult(
        TopUpOutcome.failed,
        'A payment is already in progress.',
      );
    }

    _paying = true;
    _error = null;
    notifyListeners();

    try {
      _order = await _service.createOrder(amountRupees);
    } on ApiException catch (e) {
      _paying = false;
      _error = e.message;
      notifyListeners();
      return TopUpResult(TopUpOutcome.failed, e.message);
    }

    final completer = Completer<TopUpResult>();
    _pending = completer;

    _razorpay?.clear();
    final razorpay = Razorpay();
    _razorpay = razorpay;
    razorpay.on(Razorpay.EVENT_PAYMENT_SUCCESS, _onPaymentSuccess);
    razorpay.on(Razorpay.EVENT_PAYMENT_ERROR, _onPaymentError);
    razorpay.on(Razorpay.EVENT_EXTERNAL_WALLET, _onExternalWallet);

    final order = _order!;
    try {
      razorpay.open({
        'key': order.keyId,
        'order_id': order.orderId,
        'amount': order.amountPaise,
        'currency': order.currency,
        'name': 'Justiceland',
        'description': 'Add ₹$amountRupees to wallet',
        'prefill': {
          'name': order.prefillName,
          'email': order.prefillEmail,
          'contact': order.prefillContact,
        },
        'theme': {'color': '#1E3A5F'},
        'retry': {'enabled': true, 'max_count': 1},
      });
    } catch (e) {
      _finish(TopUpResult(
        TopUpOutcome.failed,
        'Could not open the payment screen. Please try again.',
      ));
    }

    return completer.future;
  }

  Future<void> _onPaymentSuccess(PaymentSuccessResponse response) async {
    try {
      final result = await _service.verify(
        orderId: response.orderId ?? _order?.orderId ?? '',
        paymentId: response.paymentId ?? '',
        signature: response.signature ?? '',
      );

      if (result.pending) {
        _finish(TopUpResult(
          TopUpOutcome.pending,
          result.message.isNotEmpty
              ? result.message
              : 'Payment received. Your balance will update shortly.',
        ));
        return;
      }

      _wallet = result.wallet;
      _auth.applyWallet(_wallet);
      _finish(const TopUpResult(
        TopUpOutcome.success,
        'Money added to your wallet.',
      ));
    } on ApiException catch (e) {
      // The payment went through but we could not confirm it. Never call this
      // a failure — the webhook is the safety net and will credit it.
      _finish(TopUpResult(
        TopUpOutcome.pending,
        e.message.isNotEmpty
            ? e.message
            : 'We could not confirm the payment. If money was deducted it will be credited shortly.',
      ));
    }
  }

  void _onPaymentError(PaymentFailureResponse response) {
    // Razorpay reports a closed sheet as an error too; a cancellation is not a
    // failure and should not be shouted about in red.
    final cancelled = response.code == Razorpay.PAYMENT_CANCELLED;
    _finish(TopUpResult(
      cancelled ? TopUpOutcome.cancelled : TopUpOutcome.failed,
      cancelled
          ? 'Payment cancelled.'
          : (response.message?.isNotEmpty ?? false)
              ? response.message!
              : 'Payment failed. Please try again.',
    ));
  }

  void _onExternalWallet(ExternalWalletResponse response) {
    // The sheet handed off to a wallet app; the result still arrives on the
    // success or error handler, so nothing is resolved here.
  }

  void _finish(TopUpResult result) {
    _paying = false;
    _order = null;
    if (result.outcome == TopUpOutcome.failed) _error = result.message;
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
