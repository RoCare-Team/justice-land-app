import 'dart:async';

import 'package:razorpay_flutter/razorpay_flutter.dart';

import '../core/network/api_exception.dart';
import '../services/membership_service.dart';

enum PlanPurchaseOutcome { success, pending, cancelled, failed }

class PlanPurchaseResult {
  const PlanPurchaseResult(this.outcome, this.message, {this.planName = ''});

  final PlanPurchaseOutcome outcome;
  final String message;
  final String planName;

  bool get ok => outcome == PlanPurchaseOutcome.success;
}

/// Buying a membership plan: the website's three steps, in one place.
///
/// Used by the My Plan screen and by the upgrade sheet that opens when a
/// practice area will not tick — the money path must not have two copies.
///
///   1. the server opens a Razorpay order for the plan's yearly price
///   2. Razorpay's sheet takes the payment
///   3. the server verifies it with Razorpay before granting the plan
///
/// The app sends a plan id, never an amount.
class MembershipCheckout {
  MembershipCheckout(this._service);

  final MembershipService _service;
  Razorpay? _razorpay;
  Completer<PlanPurchaseResult>? _pending;
  MembershipOrder? _order;

  bool get busy => _pending != null;

  Future<PlanPurchaseResult> buy(String planId, {String planLabel = ''}) async {
    if (_pending != null) {
      return const PlanPurchaseResult(PlanPurchaseOutcome.failed, 'A payment is already in progress.');
    }
    final completer = Completer<PlanPurchaseResult>();
    _pending = completer;

    try {
      _order = await _service.createOrder(planId);
    } on ApiException catch (e) {
      _finish(PlanPurchaseResult(PlanPurchaseOutcome.failed, e.message));
      return completer.future;
    }

    _razorpay?.clear();
    final razorpay = Razorpay();
    _razorpay = razorpay;
    razorpay.on(Razorpay.EVENT_PAYMENT_SUCCESS, _onSuccess);
    razorpay.on(Razorpay.EVENT_PAYMENT_ERROR, _onError);
    razorpay.on(Razorpay.EVENT_EXTERNAL_WALLET, (_) {});

    final order = _order!;
    try {
      razorpay.open({
        'key': order.keyId,
        'order_id': order.orderId,
        'amount': order.amountPaise,
        'currency': order.currency,
        'name': 'Justiceland',
        'description': '${order.planName.isEmpty ? planLabel : order.planName} — 12 months',
        'prefill': {
          'name': order.prefillName,
          'email': order.prefillEmail,
          'contact': order.prefillContact,
        },
        'theme': {'color': '#1E3A5F'},
      });
    } catch (_) {
      _finish(const PlanPurchaseResult(
        PlanPurchaseOutcome.failed,
        'Could not open the payment screen. Please try again.',
      ));
    }
    return completer.future;
  }

  Future<void> _onSuccess(PaymentSuccessResponse response) async {
    try {
      final planName = await _service.verify(
        orderId: response.orderId ?? _order?.orderId ?? '',
        paymentId: response.paymentId ?? '',
        signature: response.signature ?? '',
      );
      _finish(PlanPurchaseResult(
        PlanPurchaseOutcome.success,
        'You are on ${planName.isEmpty ? 'your new plan' : planName} now.',
        planName: planName,
      ));
    } on ApiException catch (e) {
      // Paid but not confirmed here: the webhook grants it. Never "failed".
      _finish(PlanPurchaseResult(
        PlanPurchaseOutcome.pending,
        e.message.isNotEmpty ? e.message : 'Payment received. Your plan will update shortly.',
      ));
    }
  }

  void _onError(PaymentFailureResponse response) {
    final cancelled = response.code == Razorpay.PAYMENT_CANCELLED;
    _finish(PlanPurchaseResult(
      cancelled ? PlanPurchaseOutcome.cancelled : PlanPurchaseOutcome.failed,
      cancelled
          ? 'Payment cancelled.'
          : (response.message?.isNotEmpty ?? false)
              ? response.message!
              : 'Payment failed. Please try again.',
    ));
  }

  void _finish(PlanPurchaseResult result) {
    _razorpay?.clear();
    _razorpay = null;
    _order = null;
    final pending = _pending;
    _pending = null;
    if (pending != null && !pending.isCompleted) pending.complete(result);
  }

  void dispose() {
    _razorpay?.clear();
    _razorpay = null;
  }
}
