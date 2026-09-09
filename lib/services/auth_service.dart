import '../core/network/api_client.dart';
import '../core/network/endpoints.dart';
import '../models/account.dart';
import '../models/advocate.dart';
import '../models/json.dart';
import '../models/marketplace.dart';

/// Who is signed in, if anyone. The backend answers this from the session
/// cookie, so the app never decides it for itself.
class SessionInfo {
  const SessionInfo({this.role, this.user, this.advocate});

  /// 'user' | 'advocate' | null
  final String? role;
  final AppUser? user;
  final Advocate? advocate;

  static const SessionInfo signedOut = SessionInfo();

  bool get isSignedIn => role != null;
  bool get isUser => role == 'user';
  bool get isAdvocate => role == 'advocate';

  String get displayName =>
      user?.displayName ?? advocate?.name ?? 'Guest';

  factory SessionInfo.fromJson(Map<String, dynamic> j) {
    final role = j['role'] == null ? null : J.str(j['role']);
    return SessionInfo(
      role: (role == null || role.isEmpty) ? null : role,
      user: j['user'] == null ? null : AppUser.fromJson(J.map(j['user'])),
      advocate:
          j['advocate'] == null ? null : Advocate.fromJson(J.map(j['advocate'])),
    );
  }
}

/// The result of verifying a login OTP.
class OtpVerifyResult {
  const OtpVerifyResult({
    required this.ok,
    required this.created,
    required this.needsName,
    this.user,
  });

  final bool ok;

  /// True only the first time a number is seen — the account was just created.
  /// This is the honest signal that a registration happened; the same form
  /// signs existing clients in, and treating those as sign-ups would count
  /// every returning visitor as new.
  final bool created;

  /// The account has no name yet, so ask for one before continuing.
  final bool needsName;

  final AppUser? user;

  factory OtpVerifyResult.fromJson(Map<String, dynamic> j) => OtpVerifyResult(
        ok: J.flag(j['ok'], true),
        created: J.flag(j['created']),
        needsName: J.flag(j['needsName']),
        user: j['user'] == null ? null : AppUser.fromJson(J.map(j['user'])),
      );
}

/// What verifying a lawyer's code told us.
class AdvocateOtpResult {
  const AdvocateOtpResult({
    required this.ok,
    required this.registered,
    this.name = '',
    this.redirect = '',
  });

  final bool ok;

  /// True when the number already belongs to a lawyer — they are now signed in
  /// and there is nothing left to ask. False means the number is new: the
  /// server has set the proof cookie and the app should collect a name, email
  /// and city, then call [AuthService.signUpAdvocate].
  final bool registered;

  /// Their name, so the app can greet them without another round trip.
  final String name;

  /// Where the website would have sent them. Followed for parity, not trusted:
  /// the app maps it to its own route rather than opening a URL.
  final String redirect;

  factory AdvocateOtpResult.fromJson(Map<String, dynamic> j) =>
      AdvocateOtpResult(
        ok: J.flag(j['ok'], true),
        registered: J.flag(j['registered']),
        name: J.str(j['name']),
        redirect: J.str(j['redirect']),
      );
}

class AuthService {
  AuthService(this._api);

  final ApiClient _api;

  /// The current session. Called on launch and after every sign-in/out.
  Future<SessionInfo> me() async {
    final data = await _api.get(Endpoints.me);
    return SessionInfo.fromJson(J.map(data));
  }

  // ── Client sign-in: mobile + OTP ─────────────────────────────────────────

  /// Sends the code. The gateway generates and verifies it — the app never
  /// sees or checks the digits itself.
  Future<void> sendOtp(String phone) async {
    await _api.post(Endpoints.userOtpSend, body: {'phone': phone});
  }

  Future<OtpVerifyResult> verifyOtp({
    required String phone,
    required String otp,
  }) async {
    final data = await _api.post(
      Endpoints.userOtpVerify,
      body: {'phone': phone, 'otp': otp},
    );
    return OtpVerifyResult.fromJson(J.map(data));
  }

  /// Names a freshly created account.
  Future<AppUser?> setName(String name) async {
    final data = await _api.patch(Endpoints.userMe, body: {'name': name});
    final map = J.map(data);
    final user = map['user'];
    return user == null ? null : AppUser.fromJson(J.map(user));
  }

  /// The client's privacy preference: when on, lawyers see 'Anonymous'.
  Future<AppUser?> setAnonymous(bool value) async {
    final data = await _api.patch(Endpoints.userMe, body: {'anonymous': value});
    final map = J.map(data);
    final user = map['user'];
    return user == null ? null : AppUser.fromJson(J.map(user));
  }

  /// Save the address that prefills a service checkout.
  ///
  /// Validation lives on the server — the PIN code and GSTIN formats are
  /// checked there and the error comes back as a sentence, so the app does not
  /// keep a second copy of rules that could drift out of step with it.
  Future<AppUser?> setBillingAddress(BillingAddress address) async {
    final data = await _api.patch(
      Endpoints.userMe,
      body: {'billingAddress': address.toJson()},
    );
    final map = J.map(data);
    final user = map['user'];
    return user == null ? null : AppUser.fromJson(J.map(user));
  }

  // ── Lawyer sign-in: mobile + OTP ─────────────────────────────────────────
  //
  // The same two calls as the client flow, against the lawyer's own routes.
  // What differs is the answer: verifying a number the website already knows
  // signs the lawyer straight in, and verifying one it does not returns
  // `registered: false` plus an httpOnly proof cookie, which `signUpAdvocate`
  // then spends. The app never carries the number between those two calls —
  // the server does, in a cookie the app cannot read.

  /// Texts a code to a lawyer's number.
  Future<void> sendAdvocateOtp(String phone) async {
    await _api.post(Endpoints.advocateOtpSend, body: {'phone': phone});
  }

  /// Checks the code. See [AdvocateOtpResult] for the two possible answers.
  Future<AdvocateOtpResult> verifyAdvocateOtp({
    required String phone,
    required String otp,
  }) async {
    final data = await _api.post(
      Endpoints.advocateOtpVerify,
      body: {'phone': phone, 'otp': otp},
    );
    return AdvocateOtpResult.fromJson(J.map(data));
  }

  /// Creates the lawyer's account from the three things asked after the code.
  ///
  /// Deliberately takes no phone number. The server reads it from the proof it
  /// set moments ago, so an app that got the number wrong — or a request that
  /// was tampered with — cannot create an account for somebody else's line.
  Future<Advocate?> signUpAdvocate({
    required String name,
    required String email,
    required String city,
  }) async {
    final res = await _api.post(Endpoints.advocateSignup, body: {
      'name': name.trim(),
      'email': email.trim(),
      'city': city.trim(),
    });
    final advocate = J.map(res)['advocate'];
    return advocate == null ? null : Advocate.fromJson(J.map(advocate));
  }

  // ── Sign out ─────────────────────────────────────────────────────────────

  /// Asks the server to clear the cookie, then drops the local jar too. The
  /// second half matters: if the request fails the app must still forget the
  /// session rather than appear signed in with a cookie the server rejects.
  Future<void> logout() async {
    try {
      await _api.post(Endpoints.logout);
    } finally {
      await _api.clearSession();
    }
  }
}
