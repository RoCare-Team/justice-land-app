import '../core/network/api_client.dart';
import '../core/network/endpoints.dart';
import '../models/json.dart';
import '../models/marketplace.dart';

/// The legal-services marketplace, as a set of calls.
///
/// The same shape as [WalletService] and for the same reason: the server opens
/// the order, Razorpay's sheet takes the payment, and the server verifies it
/// before anything is treated as bought. The app never sends an amount — it
/// sends what to buy, and the price is the server's to decide.
class MarketplaceService {
  MarketplaceService(this._api);

  final ApiClient _api;

  /// The catalogue and its categories, in one request.
  Future<ServiceCatalogue> catalogue({String category = '', String query = ''}) async {
    final data = await _api.get(Endpoints.marketplaceServices, query: {
      if (category.isNotEmpty) 'category': category,
      if (query.trim().isNotEmpty) 'q': query.trim(),
    });
    return ServiceCatalogue.fromJson(J.map(data));
  }

  /// One service with everything the detail screen shows.
  Future<ServiceProduct> detail(String slug) async {
    final data = await _api.get(Endpoints.marketplaceService(slug));
    return ServiceProduct.fromJson(J.map(J.map(data)['service']));
  }

  /// Price the order without placing it — what the summary screen prints.
  ///
  /// A rejected coupon comes back inside the quote as `couponError`, not as a
  /// thrown exception: the totals are still valid without it, and the summary
  /// has to keep rendering while the client fixes the code.
  Future<ServiceQuote> quote({
    required String slug,
    String couponCode = '',
    bool useWallet = false,
  }) async {
    final data = await _api.post(Endpoints.marketplaceQuote, body: {
      'slug': slug,
      if (couponCode.trim().isNotEmpty) 'couponCode': couponCode.trim(),
      'useWallet': useWallet,
    });
    return ServiceQuote.fromJson(J.map(data));
  }

  /// Place the order. The server prices it again from the catalogue, so the
  /// quote the client saw is a preview and never the authority.
  Future<PlacedOrder> place({
    required String slug,
    required BillingAddress address,
    String couponCode = '',
    bool useWallet = false,
    String notes = '',
  }) async {
    final data = await _api.post(Endpoints.marketplaceOrders, body: {
      'slug': slug,
      if (couponCode.trim().isNotEmpty) 'couponCode': couponCode.trim(),
      'useWallet': useWallet,
      'address': address.toJson(),
      if (notes.trim().isNotEmpty) 'notes': notes.trim(),
    });
    return PlacedOrder.fromJson(J.map(data));
  }

  /// Hand the checkout result back for verification.
  ///
  /// `applied` is false when the webhook confirmed the payment first. That is
  /// not an error — the order is paid, it just was not this call that recorded
  /// it.
  Future<OrderVerifyResult> verify({
    required String orderId,
    required String paymentId,
    required String signature,
  }) async {
    final data = await _api.post(Endpoints.marketplaceOrderVerify, body: {
      'razorpay_order_id': orderId,
      'razorpay_payment_id': paymentId,
      'razorpay_signature': signature,
    });
    final map = J.map(data);
    final order = J.map(map['order']);
    return OrderVerifyResult(
      ok: J.flag(map['ok'], true),
      applied: J.flag(map['applied'], true),
      pending: J.flag(map['pending']),
      order: order.isEmpty ? null : ServiceOrder.fromJson(order),
      message: J.str(map['message'] ?? map['error']),
    );
  }

  /// Give back an abandoned order's wallet hold straight away.
  ///
  /// Best-effort by design: the server sweeps stale holds on its own after
  /// half an hour, so a failure here delays the refund rather than losing it,
  /// and is not worth showing the client an error over.
  Future<void> cancel(String orderId) async {
    await _api.post(Endpoints.marketplaceOrderCancel(orderId));
  }

  /// The client's own orders, newest first.
  Future<List<ServiceOrder>> myOrders() async {
    final data = await _api.get(Endpoints.marketplaceOrders);
    return J.models(J.map(data)['orders'], ServiceOrder.fromJson);
  }
}

/// What came back from verifying a service payment.
class OrderVerifyResult {
  const OrderVerifyResult({
    required this.ok,
    required this.applied,
    required this.pending,
    required this.order,
    required this.message,
  });

  final bool ok;

  /// False when the webhook got there first. The order is still paid.
  final bool applied;

  /// Authorised but not captured yet — the money is held, not taken.
  final bool pending;

  final ServiceOrder? order;
  final String message;
}
