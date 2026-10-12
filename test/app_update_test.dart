// The update check: what the server's answer means on screen, and that an
// answer that never comes (or is not an answer) leaves the app usable.

import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'package:flutter_legal_care/core/config/app_config.dart';
import 'package:flutter_legal_care/core/network/api_client.dart';
import 'package:flutter_legal_care/core/network/endpoints.dart';
import 'package:flutter_legal_care/features/update/app_update_gate.dart';
import 'package:flutter_legal_care/services/app_update_service.dart';

class _FakePathProvider extends PathProviderPlatform with MockPlatformInterfaceMixin {
  @override
  Future<String?> getApplicationDocumentsPath() async => '.dart_tool/test_docs';
}

class _Server implements HttpClientAdapter {
  _Server(this.status, this.body, {this.html = false});

  final int status;
  final Object body;
  final bool html;
  RequestOptions? seen;

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? _, Future<void>? __) async {
    seen = options;
    return ResponseBody.fromString(
      html ? '<!DOCTYPE html><html></html>' : jsonEncode(body),
      status,
      headers: {
        Headers.contentTypeHeader: [html ? 'text/html; charset=utf-8' : Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

/// Answers with [update] without a network.
class _FakeService implements AppUpdateService {
  _FakeService(this.update);

  AppUpdate? update;

  @override
  Future<AppUpdate?> check() async => update;
}

AppUpdate _update(UpdateKind kind, {int latestBuild = 12}) => AppUpdate(
      kind: kind,
      latestVersion: '10.0.3',
      latestBuild: latestBuild,
      title: '',
      message: '',
      storeUrl: 'https://play.google.com/store/apps/details?id=com.justiceland.care',
    );

/// A fresh launch each time: whatever was on screen goes first.
Future<void> _pump(WidgetTester tester, AppUpdateService service) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pumpWidget(MaterialApp(
    home: const Scaffold(body: Text('The app')),
    builder: (context, child) => AppUpdateGate(service: service, child: child!),
  ));
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AppUpdateService', () {
    late ApiClient api;

    setUpAll(() async {
      PathProviderPlatform.instance = _FakePathProvider();
      api = await ApiClient.init();
    });

    test('sends this build and reads the answer', () async {
      final server = _Server(200, {
        'platform': 'android',
        'update': 'force',
        'latestVersion': '10.0.3',
        'latestBuild': 12,
        'minSupportedBuild': 12,
        'title': 'Update required',
        'message': 'Please update.',
        'storeUrl': 'https://play.google.com/store/apps/details?id=com.justiceland.care',
      });
      api.raw.httpClientAdapter = server;
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      final update = await AppUpdateService(api).check();
      debugDefaultTargetPlatformOverride = null;

      expect(server.seen?.path, Endpoints.appVersion);
      expect(server.seen?.queryParameters['platform'], 'android');
      expect(server.seen?.queryParameters['build'], AppConfig.build);
      expect(update?.kind, UpdateKind.force);
      expect(update?.latestBuild, 12);
      expect(update?.title, 'Update required');
    });

    test('an error, a missing route or an HTML page is no answer, not an update', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      for (final server in [
        _Server(404, {'error': 'Not found.'}),
        _Server(500, {'error': 'boom'}),
        _Server(200, '', html: true),
      ]) {
        api.raw.httpClientAdapter = server;
        expect(await AppUpdateService(api).check(), isNull);
      }
      debugDefaultTargetPlatformOverride = null;
    });
  });

  group('AppUpdateGate', () {
    testWidgets('force covers the app with only an Update button', (tester) async {
      await _pump(tester, _FakeService(_update(UpdateKind.force)));
      expect(find.text('Update required'), findsOneWidget);
      expect(find.text('Update now'), findsOneWidget);
      expect(find.text('Later'), findsNothing);
    });

    testWidgets('optional offers Update and Later; Later lasts until the app is left', (tester) async {
      await _pump(tester, _FakeService(_update(UpdateKind.optional)));
      expect(find.text('Update available'), findsOneWidget);

      await tester.tap(find.text('Later'));
      await tester.pumpAndSettle();
      expect(find.text('Update available'), findsNothing);

      // Home, then back into the app: it asks again.
      for (final state in [
        AppLifecycleState.inactive,
        AppLifecycleState.hidden,
        AppLifecycleState.paused,
        AppLifecycleState.hidden,
        AppLifecycleState.inactive,
        AppLifecycleState.resumed,
      ]) {
        tester.binding.handleAppLifecycleStateChanged(state);
      }
      await tester.pumpAndSettle();
      expect(find.text('Update available'), findsOneWidget);
    });

    testWidgets('a fresh launch asks again after Later', (tester) async {
      await _pump(tester, _FakeService(_update(UpdateKind.optional)));
      await tester.tap(find.text('Later'));
      await tester.pumpAndSettle();

      await _pump(tester, _FakeService(_update(UpdateKind.optional)));
      expect(find.text('Update available'), findsOneWidget);
    });

    testWidgets('nothing to update, or no answer at all: just the app', (tester) async {
      await _pump(tester, _FakeService(_update(UpdateKind.none)));
      expect(find.text('Update required'), findsNothing);
      expect(find.text('Update available'), findsNothing);

      await _pump(tester, _FakeService(null));
      expect(find.text('The app'), findsOneWidget);
      expect(find.text('Update required'), findsNothing);
    });
  });
}
