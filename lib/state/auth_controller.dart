import 'package:flutter/foundation.dart';

import '../core/network/api_exception.dart';
import '../models/account.dart';
import '../models/marketplace.dart';
import '../models/advocate.dart';
import '../services/auth_service.dart';

enum AuthStatus { unknown, signedOut, user, advocate }

/// Who is signed in, app-wide.
///
/// The server is the authority — this holds what it last said, and refreshes
/// rather than mutating its own idea of the session. A screen that believes it
/// is signed in while the cookie is dead is how you get a booking flow that
/// dead-ends at 401 three taps later.
class AuthController extends ChangeNotifier {
  AuthController(this._auth);

  final AuthService _auth;

  AuthStatus _status = AuthStatus.unknown;
  AppUser? _user;
  Advocate? _advocate;
  bool _busy = false;
  String? _error;

  AuthStatus get status => _status;
  AppUser? get user => _user;
  Advocate? get advocate => _advocate;
  bool get busy => _busy;
  String? get error => _error;

  bool get isSignedIn =>
      _status == AuthStatus.user || _status == AuthStatus.advocate;
  bool get isUser => _status == AuthStatus.user;
  bool get isAdvocate => _status == AuthStatus.advocate;
  bool get isResolved => _status != AuthStatus.unknown;

  int get walletBalance => _user?.walletBalance ?? 0;

  /// Read the session on launch, and after anything that could have changed it.
  Future<void> refresh() async {
    try {
      final session = await _auth.me();
      _apply(session);
    } on ApiException {
      // A failed read is not proof of being signed out — it could be the
      // network. Only an explicit "no role" answer signs the app out.
      if (_status == AuthStatus.unknown) _status = AuthStatus.signedOut;
    }
    notifyListeners();
  }

  void _apply(SessionInfo session) {
    _user = session.user;
    _advocate = session.advocate;
    if (session.isUser && session.user != null) {
      _status = AuthStatus.user;
    } else if (session.isAdvocate && session.advocate != null) {
      _status = AuthStatus.advocate;
    } else {
      _status = AuthStatus.signedOut;
    }
  }

  // ── Client sign-in ───────────────────────────────────────────────────────

  Future<bool> sendOtp(String phone) => _run(() => _auth.sendOtp(phone));

  /// Verifies the code and adopts the session.
  ///
  /// Returns the result rather than just a bool because the caller needs
  /// `created` (a brand-new account — the moment a registration actually
  /// happened) and `needsName` (ask for a name before going on).
  Future<OtpVerifyResult?> verifyOtp({
    required String phone,
    required String otp,
  }) async {
    _busy = true;
    _error = null;
    notifyListeners();
    try {
      final result = await _auth.verifyOtp(phone: phone, otp: otp);
      await refresh();
      return result;
    } on ApiException catch (e) {
      _error = e.message;
      return null;
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  Future<bool> setName(String name) => _run(() async {
        await _auth.setName(name);
        await refresh();
      });

  Future<bool> setAnonymous(bool value) => _run(() async {
        final updated = await _auth.setAnonymous(value);
        if (updated != null) _user = updated;
      });

  /// Saves the billing address and refreshes, so the next checkout prefills
  /// from it. The server rejects a malformed PIN code or GSTIN, and _run
  /// surfaces that message rather than the app guessing at the rules.
  Future<bool> setBillingAddress(BillingAddress address) => _run(() async {
        final updated = await _auth.setBillingAddress(address);
        if (updated != null) _user = updated;
      });

  // ── Lawyer sign-in: mobile + OTP ─────────────────────────────────────────

  Future<bool> sendAdvocateOtp(String phone) =>
      _run(() => _auth.sendAdvocateOtp(phone));

  /// Verifies the code and, when the number is already a lawyer's, adopts the
  /// session the server just handed us. Returns null on failure so the caller
  /// can show [error]; on success the caller branches on `registered`.
  Future<AdvocateOtpResult?> verifyAdvocateOtp({
    required String phone,
    required String otp,
  }) async {
    _busy = true;
    _error = null;
    notifyListeners();
    try {
      final result = await _auth.verifyAdvocateOtp(phone: phone, otp: otp);
      // A known number is signed in by that call; a new one is not, and there
      // is nothing to refresh until the account exists.
      if (result.registered) await refresh();
      return result;
    } on ApiException catch (e) {
      _error = e.message;
      return null;
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  /// Creates the account, then picks up the session it returns.
  Future<Advocate?> signUpAdvocate({
    required String name,
    required String email,
    required String city,
  }) async {
    _busy = true;
    _error = null;
    notifyListeners();
    try {
      final created =
          await _auth.signUpAdvocate(name: name, email: email, city: city);
      // Signing up signs the lawyer in, so adopt that session.
      await refresh();
      return created;
    } on ApiException catch (e) {
      _error = e.message;
      return null;
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  // ── Session upkeep ───────────────────────────────────────────────────────

  Future<void> signOut() async {
    await _auth.logout();
    _user = null;
    _advocate = null;
    _status = AuthStatus.signedOut;
    notifyListeners();
  }

  /// Called when any request comes back 401: the cookie is gone or expired, so
  /// stop pretending otherwise.
  void onSessionExpired() {
    if (_status == AuthStatus.signedOut) return;
    _user = null;
    _advocate = null;
    _status = AuthStatus.signedOut;
    notifyListeners();
  }

  /// Keeps the header balance honest after a top-up or a consultation charge,
  /// without a full session round trip.
  void applyWallet(Wallet wallet) {
    final current = _user;
    if (current == null) return;
    _user = AppUser(
      id: current.id,
      name: current.name,
      email: current.email,
      phone: current.phone,
      photo: current.photo,
      city: current.city,
      anonymous: current.anonymous,
      billingAddress: current.billingAddress,
      walletBalance: wallet.balance,
      walletTransactions: wallet.transactions,
      createdAt: current.createdAt,
    );
    notifyListeners();
  }

  void setAdvocateAvailability(bool available) {
    final current = _advocate;
    if (current == null) return;
    _advocate = current;
    notifyListeners();
  }

  void clearError() {
    if (_error == null) return;
    _error = null;
    notifyListeners();
  }

  Future<bool> _run(Future<void> Function() action) async {
    _busy = true;
    _error = null;
    notifyListeners();
    try {
      await action();
      return true;
    } on ApiException catch (e) {
      _error = e.message;
      return false;
    } finally {
      _busy = false;
      notifyListeners();
    }
  }
}
