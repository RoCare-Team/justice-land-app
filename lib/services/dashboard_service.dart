import 'package:dio/dio.dart';

import '../core/network/api_client.dart';
import '../core/network/endpoints.dart';
import '../models/account.dart';
import '../models/advocate.dart';
import '../models/json.dart';

/// The lawyer's own side: their editable profile, their enquiries, and the
/// availability switch that decides whether clients can reach them at all.
class DashboardService {
  DashboardService(this._api);

  final ApiClient _api;

  /// The signed-in lawyer's profile, in editable form.
  Future<Advocate> profile() async {
    final data = await _api.get(Endpoints.dashboardProfile);
    final map = J.map(data);
    return Advocate.fromJson(J.map(map['advocate'] ?? map));
  }

  /// How complete the lawyer's profile is — the same score as the website's
  /// dashboard, read off the profile route.
  Future<ProfileCompletion> completion() async {
    final data = await _api.get(Endpoints.dashboardProfile);
    return ProfileCompletion.fromJson(J.map(J.map(data)['completion']));
  }

  /// The lawyer's earnings wallet — what paid consultations have credited.
  ///
  /// Read off the same profile route: for the signed-in lawyer it carries
  /// `walletBalance` and `walletTransactions`, which the public profile strips.
  /// There is no payout route on the server, so this is read-only.
  Future<Wallet> earnings() async {
    final data = await _api.get(Endpoints.dashboardProfile);
    final map = J.map(data);
    final advocate = J.map(map['advocate'] ?? map);
    return Wallet(
      balance: J.int$(advocate['walletBalance']),
      transactions:
          J.models(advocate['walletTransactions'], WalletTransaction.fromJson),
    );
  }

  /// Saves the profile. Only the keys present are written, matching the API's
  /// `!== undefined` checks — so a screen that edits one section cannot blank
  /// the sections it never showed.
  ///
  /// Field names are the API's, not the model's: `fullName` rather than
  /// `name`, `services` rather than `specializations`. Translating here keeps
  /// that mismatch in one place instead of scattered through the UI.
  Future<Advocate> saveProfile(Map<String, dynamic> changes) async {
    final data = await _api.put(Endpoints.dashboardProfile, body: changes);
    final map = J.map(data);
    return Advocate.fromJson(J.map(map['advocate'] ?? map));
  }

  /// The online/offline switch.
  ///
  /// This is not cosmetic: a lawyer who is off is refused every booking —
  /// chat, video and phone alike — so the client is told plainly rather than
  /// left waiting on a request nobody will see.
  Future<bool> setAvailable(bool available) async {
    final data = await _api.patch(
      Endpoints.dashboardProfile,
      body: {'available': available},
    );
    return J.flag(J.map(data)['available'], available);
  }

  /// Permanently closes the account and removes the lawyer from the public
  /// directory.
  Future<void> deleteAccount() async {
    await _api.delete(Endpoints.dashboardProfile);
    await _api.clearSession();
  }

  // ── Enquiries ────────────────────────────────────────────────────────────

  /// The enquiries sent to this lawyer. A GET on the same route a client POSTs
  /// an enquiry to; the server hands back whichever side of it is yours.
  Future<List<Enquiry>> enquiries() async {
    final data = await _api.get(Endpoints.enquiries);
    return J.models(J.map(data)['enquiries'], Enquiry.fromJson);
  }

  /// Moves an enquiry along: 'new' → 'pending' → 'confirmed' | 'declined'.
  Future<Enquiry> setEnquiryStatus(String id, String status) async {
    final data = await _api.patch(
      Endpoints.enquiry(id),
      body: {'status': status},
    );
    final map = J.map(data);
    return Enquiry.fromJson(J.map(map['enquiry'] ?? map));
  }

  // ── Media ────────────────────────────────────────────────────────────────

  /// Uploads an image and returns the URL to store on the profile.
  Future<String> uploadImage(String filePath, {String fieldName = 'file'}) async {
    final form = FormData.fromMap({
      fieldName: await MultipartFile.fromFile(filePath),
    });
    final data = await _api.upload(Endpoints.upload, form: form);
    final map = J.map(data);
    return J.str(map['url'] ?? map['path'] ?? map['location']);
  }

  // ── Verification documents ───────────────────────────────────────────────

  /// The documents this lawyer has uploaded, by kind.
  Future<Map<String, VerificationDocument>> verificationDocuments() async {
    final data = await _api.get(Endpoints.verificationDocuments);
    final docs = J.models(J.map(data)['documents'], VerificationDocument.fromJson);
    return {for (final d in docs) d.kind: d};
  }

  /// Uploads (or replaces) one document. [kind] is `bar_council_certificate`
  /// or `government_id`.
  Future<VerificationDocument> uploadVerificationDocument({
    required String kind,
    required String filePath,
    required String fileName,
  }) async {
    final form = FormData.fromMap({
      'kind': kind,
      'file': await MultipartFile.fromFile(filePath, filename: fileName),
    });
    final data = await _api.upload(Endpoints.verificationDocuments, form: form);
    return VerificationDocument.fromJson(J.map(J.map(data)['document']));
  }

  // ── Bank accounts ────────────────────────────────────────────────────────

  /// The lawyer's saved payout accounts, primary first — last four digits only.
  Future<List<BankAccount>> bankAccounts() async {
    final data = await _api.get(Endpoints.payouts);
    return J.models(J.map(data)['bankAccounts'], BankAccount.fromJson);
  }

  /// Adds a payout account. The server validates the number, IFSC and PAN
  /// again and answers with a sentence the screen can show as it is.
  Future<BankAccount> addBankAccount({
    required String holderName,
    required String bankName,
    required String accountNumber,
    required String ifsc,
    String pan = '',
  }) async {
    final data = await _api.post(Endpoints.bankAccounts, body: {
      'holderName': holderName,
      'bankName': bankName,
      'accountNumber': accountNumber,
      'ifsc': ifsc,
      if (pan.isNotEmpty) 'pan': pan,
    });
    return BankAccount.fromJson(J.map(J.map(data)['account']));
  }

  // ── Push notifications ───────────────────────────────────────────────────

  /// Registers this device's Firebase token, so a new request or an incoming
  /// call reaches the signed-in lawyer even with the app backgrounded or
  /// closed. Called again whenever Firebase rotates the token.
  Future<void> registerFcmToken(String token) =>
      _api.post(Endpoints.fcmToken, body: {'token': token});

  /// Removes this device's token — called on sign-out, so a phone that has
  /// moved on to a different account stops ringing for the one it left.
  Future<void> unregisterFcmToken(String token) =>
      _api.delete(Endpoints.fcmToken, body: {'token': token});
}

/// A saved payout account as the server shows it: never the full number.
class BankAccount {
  const BankAccount({
    required this.id,
    required this.holderName,
    required this.bankName,
    required this.ifsc,
    required this.accountLast4,
    required this.panLast4,
    required this.isPrimary,
  });

  final String id;
  final String holderName;
  final String bankName;
  final String ifsc;
  final String accountLast4;
  final String panLast4;
  final bool isPrimary;

  factory BankAccount.fromJson(Map<String, dynamic> j) => BankAccount(
        id: J.str(j['id']),
        holderName: J.str(j['holderName']),
        bankName: J.str(j['bankName']),
        ifsc: J.str(j['ifsc']),
        accountLast4: J.str(j['accountLast4']),
        panLast4: J.str(j['panLast4']),
        isPrimary: J.flag(j['isPrimary']),
      );
}

/// Profile completion: a percentage and what is still missing.
class ProfileCompletion {
  const ProfileCompletion({
    required this.percent,
    required this.done,
    required this.total,
    required this.missing,
  });

  final int percent;
  final int done;
  final int total;
  final List<({String key, String label, String step})> missing;

  factory ProfileCompletion.fromJson(Map<String, dynamic> j) => ProfileCompletion(
        percent: J.int$(j['percent']).clamp(0, 100),
        done: J.int$(j['done']),
        total: J.int$(j['total']),
        missing: [
          for (final m in J.mapList(j['missing']))
            (key: J.str(m['key']), label: J.str(m['label']), step: J.str(m['step'])),
        ],
      );
}

/// One uploaded verification document — its details, never its contents.
class VerificationDocument {
  const VerificationDocument({
    required this.id,
    required this.kind,
    required this.fileName,
    required this.size,
    this.uploadedAt,
  });

  final String id;
  final String kind;
  final String fileName;
  final int size;
  final DateTime? uploadedAt;

  factory VerificationDocument.fromJson(Map<String, dynamic> j) => VerificationDocument(
        id: J.str(j['id']),
        kind: J.str(j['kind']),
        fileName: J.str(j['fileName']),
        size: J.int$(j['size']),
        uploadedAt: J.date(j['uploadedAt']),
      );
}
