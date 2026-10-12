import 'package:dio/dio.dart';

import '../core/config/app_config.dart';
import '../core/network/api_exception.dart';

/// Account deletion through the backend's admin routes:
///
///   DELETE /api/admin/users?id=<user id>
///   DELETE /api/admin/advocates?id=<legalCareId>
///
/// Both need the admin `x-api-key`. It is in the source as the default below,
/// so a plain `flutter build apk` works; a rotated key can be passed with
/// `--dart-define=ADMIN_API_KEY=<key>` until the source is updated.
///
/// It does end up inside the built app, where it can be extracted, and it lets
/// its holder delete any account by id. Chosen knowingly on 2026-09-26 over a
/// session-based route; move to one (DELETE /api/user/me) when the backend has
/// it, and rotate the key if a build is ever suspected of being picked apart.
class AccountDeletion {
  const AccountDeletion._();

  // Kept in the source by the owner's decision (2026-09-26) so a plain build
  // works; --dart-define=ADMIN_API_KEY=... still overrides it after a rotation.
  static const String _key = String.fromEnvironment(
    'ADMIN_API_KEY',
    defaultValue: '179cebf288a14fcc77519b9c350deab409cc742391fd1cbd322ca7ce3a365883',
  );

  /// False in a build made without the key: the button then says deletion is
  /// unavailable instead of sending a request the server will refuse.
  static bool get available => _key.isNotEmpty;

  static Future<void> user(String id) => _delete('/api/admin/users', id);
  static Future<void> lawyer(String legalCareId) => _delete('/api/admin/advocates', legalCareId);

  static Future<void> _delete(String path, String id) async {
    if (!available) {
      throw ApiException(message: 'Account deletion is not available in this build.');
    }
    if (id.trim().isEmpty) {
      throw ApiException(message: 'Could not tell which account to delete. Please sign in again.');
    }
    // Its own client, not ApiClient: no cookies are needed, and the key must
    // not ride along on every other request.
    final dio = Dio(BaseOptions(
      baseUrl: AppConfig.baseUrl,
      connectTimeout: const Duration(seconds: 20),
      receiveTimeout: const Duration(seconds: 20),
      validateStatus: (_) => true,
    ));
    try {
      final res = await dio.delete(
        path,
        queryParameters: {'id': id.trim()},
        options: Options(headers: {'x-api-key': _key}),
      );
      final status = res.statusCode ?? 0;
      final data = res.data;
      if (status >= 200 && status < 300 && (data is! Map || data['ok'] != false)) return;
      final serverMessage = data is Map ? (data['message'] ?? data['error'])?.toString() : null;
      throw ApiException(
        message: serverMessage == null || serverMessage.isEmpty
            ? 'Could not delete the account. Please try again.'
            : serverMessage,
        statusCode: status,
      );
    } on DioException {
      throw ApiException(
        message: 'No connection. Check your internet and try again.',
        isNetwork: true,
      );
    } finally {
      dio.close();
    }
  }
}
