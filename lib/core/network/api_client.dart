import 'dart:io';

import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:dio_cookie_manager/dio_cookie_manager.dart';
import 'package:path_provider/path_provider.dart';

import '../config/app_config.dart';
import 'api_exception.dart';

/// The one HTTP client the app uses.
///
/// Authentication is the website's, unchanged: the server sets an httpOnly
/// `lci_token` cookie and every later request carries it. That is why the jar
/// is persisted to disk — it *is* the session. Nothing here reads or stores a
/// token by hand, because the token is not ours to see.
class ApiClient {
  ApiClient._(this._dio, this._jar);

  final Dio _dio;
  final PersistCookieJar _jar;

  static ApiClient? _instance;
  static ApiClient get instance {
    final client = _instance;
    if (client == null) {
      throw StateError('ApiClient.init() must be awaited before first use.');
    }
    return client;
  }

  /// Called once from main() before the app runs.
  static Future<ApiClient> init() async {
    if (_instance != null) return _instance!;

    final dir = await getApplicationDocumentsDirectory();
    final jar = PersistCookieJar(
      ignoreExpires: false,
      storage: FileStorage('${dir.path}/.justiceland_cookies'),
    );

    final dio = Dio(
      BaseOptions(
        baseUrl: AppConfig.baseUrl,
        connectTimeout: const Duration(seconds: 20),
        receiveTimeout: const Duration(seconds: 30),
        sendTimeout: const Duration(seconds: 30),
        headers: const {
          'Accept': 'application/json',
          // Marks mobile traffic in server logs without changing behaviour.
          'X-Client': 'justiceland-flutter',
        },
        // Never throw on a status code — every route below reads the body for
        // the server's own error message, which is friendlier than "500".
        validateStatus: (_) => true,
        followRedirects: true,
      ),
    );

    dio.interceptors.add(CookieManager(jar));

    _instance = ApiClient._(dio, jar);
    return _instance!;
  }

  Dio get raw => _dio;

  /// Wipe the session cookie. Used on sign-out and whenever the server tells
  /// us the session is gone, so the app cannot sit on a dead cookie.
  Future<void> clearSession() => _jar.deleteAll();

  // ── Verbs ────────────────────────────────────────────────────────────────

  Future<dynamic> get(
    String path, {
    Map<String, dynamic>? query,
    CancelToken? cancelToken,
  }) =>
      _send(() => _dio.get(path, queryParameters: query, cancelToken: cancelToken));

  Future<dynamic> post(
    String path, {
    Object? body,
    Map<String, dynamic>? query,
    CancelToken? cancelToken,
  }) =>
      _send(() => _dio.post(path, data: body, queryParameters: query, cancelToken: cancelToken));

  Future<dynamic> put(String path, {Object? body}) =>
      _send(() => _dio.put(path, data: body));

  Future<dynamic> patch(String path, {Object? body}) =>
      _send(() => _dio.patch(path, data: body));

  Future<dynamic> delete(String path, {Object? body, Map<String, dynamic>? query}) =>
      _send(() => _dio.delete(path, data: body, queryParameters: query));

  /// Multipart upload — used for the profile photo and gallery, which the web
  /// app posts to /api/admin/upload as form data.
  Future<dynamic> upload(String path, {required FormData form}) =>
      _send(() => _dio.post(path, data: form));

  // ── Plumbing ─────────────────────────────────────────────────────────────

  Future<dynamic> _send(Future<Response<dynamic>> Function() run) async {
    late final Response<dynamic> res;
    try {
      res = await run();
    } on DioException catch (e) {
      throw _fromDio(e);
    } on SocketException {
      throw ApiException(
        message: 'No internet connection. Check your network and try again.',
        isNetwork: true,
      );
    }

    final status = res.statusCode ?? 0;
    final data = res.data;

    if (status >= 200 && status < 300) return data;

    // The API answers errors as { error, message? }. `error` is sometimes a
    // code the flow branches on ('insufficient', 'offline'), sometimes the
    // sentence itself — so keep both and let ApiException sort it out.
    String? code;
    String message = 'Something went wrong. Please try again.';

    if (data is Map) {
      final rawError = data['error'];
      final rawMessage = data['message'];
      if (rawError is String && rawError.isNotEmpty) {
        final looksLikeCode = !rawError.contains(' ') && rawError.length < 30;
        code = looksLikeCode ? rawError : null;
        message = rawMessage is String && rawMessage.isNotEmpty
            ? rawMessage
            : (looksLikeCode ? message : rawError);
      } else if (rawMessage is String && rawMessage.isNotEmpty) {
        message = rawMessage;
      }
      // Some routes send the sentence in `error` and the machine code in a
      // separate `code` field ({ error: 'Another lawyer just picked this up.',
      // code: 'taken' }) — the client queries and their credits do.
      final rawCode = data['code'];
      if (rawCode is String && rawCode.isNotEmpty) code = rawCode;
    }

    if (status == 401 && message.isEmpty) {
      message = 'Please sign in to continue.';
    }

    throw ApiException(message: message, statusCode: status, code: code);
  }

  ApiException _fromDio(DioException e) {
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return ApiException(
          message: 'The server took too long to respond. Please try again.',
          isNetwork: true,
        );
      case DioExceptionType.connectionError:
        return ApiException(
          message: 'Could not reach Justiceland. Check your connection.',
          isNetwork: true,
        );
      case DioExceptionType.cancel:
        return ApiException(message: 'Request cancelled.');
      default:
        return ApiException(
          message: e.message ?? 'Network error. Please try again.',
          isNetwork: true,
        );
    }
  }
}
