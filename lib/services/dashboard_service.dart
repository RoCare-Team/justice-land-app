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
}
