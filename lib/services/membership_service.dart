import '../core/network/api_client.dart';
import '../core/network/endpoints.dart';
import '../models/json.dart';
import '../models/legal_query.dart';

/// A Razorpay order opened for a year of a plan.
class MembershipOrder {
  const MembershipOrder({
    required this.orderId,
    required this.amountPaise,
    required this.currency,
    required this.keyId,
    required this.planName,
    required this.prefillName,
    required this.prefillEmail,
    required this.prefillContact,
  });

  final String orderId;
  final int amountPaise;
  final String currency;
  final String keyId;
  final String planName;
  final String prefillName;
  final String prefillEmail;
  final String prefillContact;

  factory MembershipOrder.fromJson(Map<String, dynamic> j) {
    final prefill = J.map(j['prefill']);
    return MembershipOrder(
      orderId: J.str(j['orderId']),
      amountPaise: J.int$(j['amount']),
      currency: J.str(j['currency'], 'INR'),
      keyId: J.str(j['keyId']),
      planName: J.str(J.map(j['plan'])['name']),
      prefillName: J.str(prefill['name']),
      prefillEmail: J.str(prefill['email']),
      prefillContact: J.str(prefill['contact']),
    );
  }
}

/// Lawyer membership plans: the catalogue, and the three-step purchase the
/// website uses — open an order, pay in Razorpay, let the server verify.
/// The app sends a plan id and never a price.
class MembershipService {
  MembershipService(this._api);

  final ApiClient _api;

  Future<PlanCatalog> catalog() async {
    final data = await _api.get(Endpoints.membershipPlans);
    return PlanCatalog.fromJson(J.map(data));
  }

  Future<MembershipOrder> createOrder(String planId) async {
    final data = await _api.post(Endpoints.membershipOrder, body: {'planId': planId});
    return MembershipOrder.fromJson(J.map(data));
  }

  /// Returns the plan name the server granted.
  Future<String> verify({
    required String orderId,
    required String paymentId,
    required String signature,
  }) async {
    final data = await _api.post(Endpoints.membershipVerify, body: {
      'razorpay_order_id': orderId,
      'razorpay_payment_id': paymentId,
      'razorpay_signature': signature,
    });
    return J.str(J.map(data)['planName']);
  }
}
