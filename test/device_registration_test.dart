// Registering a phone for pushes: a route the server does not have yet answers
// with the website's HTML page and a 200, which must count as a failure — that
// is how tokens silently never reached the server — and a lawyer's token still
// has the older lawyers-only route to go to.

import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'package:flutter_legal_care/core/network/api_client.dart';
import 'package:flutter_legal_care/core/network/api_exception.dart';
import 'package:flutter_legal_care/core/network/endpoints.dart';
import 'package:flutter_legal_care/services/dashboard_service.dart';

class _FakePathProvider extends PathProviderPlatform with MockPlatformInterfaceMixin {
  @override
  Future<String?> getApplicationDocumentsPath() async => '.dart_tool/test_docs';
}

/// Answers the new devices route with the website's page (as production does
/// until the route is deployed) and every other route with `{ ok: true }`.
class _Server implements HttpClientAdapter {
  final List<String> seen = [];

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? _, Future<void>? __) async {
    seen.add('${options.method} ${options.path}');
    if (options.path == Endpoints.notificationDevices) {
      return ResponseBody.fromString(
        '<!DOCTYPE html><html><body>Justiceland</body></html>',
        200,
        headers: {Headers.contentTypeHeader: ['text/html; charset=utf-8']},
      );
    }
    return ResponseBody.fromString(
      jsonEncode({'ok': true}),
      200,
      headers: {Headers.contentTypeHeader: [Headers.jsonContentType]},
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ApiClient api;
  late _Server server;

  setUpAll(() async {
    PathProviderPlatform.instance = _FakePathProvider();
    api = await ApiClient.init();
  });

  setUp(() {
    server = _Server();
    api.raw.httpClientAdapter = server;
  });

  test('an HTML page in place of an API answer is a 404, not a success', () async {
    await expectLater(
      DashboardService(api).registerDevice('tok'),
      throwsA(isA<ApiException>()
          .having((e) => e.statusCode, 'statusCode', 404)
          .having((e) => e.code, 'code', 'not-found')),
    );
  });

  test("a lawyer's token goes to the lawyers-only route as well", () async {
    await DashboardService(api).registerLawyerToken('tok');
    await DashboardService(api).unregisterLawyerToken('tok');
    expect(server.seen, ['POST ${Endpoints.legacyFcmToken}', 'DELETE ${Endpoints.legacyFcmToken}']);
  });

  test('a JSON answer is still a success', () async {
    expect(await api.get('/api/anything'), {'ok': true});
  });
}
