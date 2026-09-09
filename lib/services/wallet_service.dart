import '../core/network/api_client.dart';
import '../core/network/endpoints.dart';
import '../models/account.dart';
import '../models/json.dart';

/// The wallet, and the three-step top-up.
///
/// Money only ever enters a wallet through a Razorpay payment the server has
/// verified. The app opens an order, runs checkout, and hands the result back
/// for verification — it never tells the server an amount to credit, because
/// anything the client can say, an attacker can say too.
class WalletService {
  WalletService(this._api);

  final ApiClient _api;

  /// Balance and ledger for the signed-in client.
  Future<Wallet> read() async {
    final data = await _api.get(Endpoints.wallet);
    return Wallet.fromJson(J.map(data));
  }

  /// Step 1 — open a Razorpay order. Nothing is charged here and nothing is
  /// credited; this only produces the order the checkout sheet needs.
  ///
  /// The response carries the key id the server is actually configured with,
  /// so a key rotated in the admin panel takes effect on the very next top-up
  /// without shipping a new build.
  Future<WalletOrder> createOrder(int amountRupees) async {
    final data = await _api.post(
      Endpoints.walletOrder,
      body: {'amount': amountRupees},
    );
    return WalletOrder.fromJson(J.map(data));
  }

  /// Step 3 — hand the checkout result to the server, which checks the
  /// signature with Razorpay before crediting anything.
  ///
  /// Returns the wallet as it stands afterwards. [WalletVerifyResult.pending]
  /// means the payment is authorised but not captured yet: the money is held,
  /// not taken, and the webhook will finish the job — so the app says "your
  /// balance will update shortly" rather than claiming success or failure.
  Future<WalletVerifyResult> verify({
    required String orderId,
    required String paymentId,
    required String signature,
  }) async {
    final data = await _api.post(Endpoints.walletVerify, body: {
      'razorpay_order_id': orderId,
      'razorpay_payment_id': paymentId,
      'razorpay_signature': signature,
    });
    final map = J.map(data);
    return WalletVerifyResult(
      ok: J.flag(map['ok'], true),
      credited: J.flag(map['credited'], true),
      pending: J.flag(map['pending']),
      wallet: Wallet(
        balance: J.int$(map['balance']),
        transactions:
            J.models(map['transactions'], WalletTransaction.fromJson),
      ),
      message: J.str(map['message'] ?? map['error']),
    );
  }
}

class WalletVerifyResult {
  const WalletVerifyResult({
    required this.ok,
    required this.credited,
    required this.pending,
    required this.wallet,
    required this.message,
  });

  final bool ok;

  /// False when the webhook credited it first. Not an error — the money is in,
  /// it just was not this request that put it there.
  final bool credited;

  /// Authorised but not captured yet.
  final bool pending;

  final Wallet wallet;
  final String message;
}
