import 'dart:async';

import 'package:flutter/foundation.dart';

import '../core/config/app_config.dart';
import '../core/network/api_client.dart';
import '../core/network/endpoints.dart';
import '../models/json.dart';

/// What the server says about this installed build.
enum UpdateKind { none, optional, force }

/// The answer of GET /api/app/version, for the build this app is.
class AppUpdate {
  const AppUpdate({
    required this.kind,
    required this.latestVersion,
    required this.latestBuild,
    required this.title,
    required this.message,
    required this.storeUrl,
  });

  factory AppUpdate.fromJson(Map<String, dynamic> j) => AppUpdate(
        kind: switch (J.str(j['update'])) {
          'force' => UpdateKind.force,
          'optional' => UpdateKind.optional,
          _ => UpdateKind.none,
        },
        latestVersion: J.str(j['latestVersion']),
        latestBuild: J.int$(j['latestBuild']),
        title: J.str(j['title']),
        message: J.str(j['message']),
        storeUrl: J.str(j['storeUrl']),
      );

  final UpdateKind kind;
  final String latestVersion;
  final int latestBuild;
  final String title;
  final String message;

  /// Play Store or App Store page. Empty when there is nothing to update to.
  final String storeUrl;
}

/// Asks the server whether this build should be updated.
///
/// Fails open: no answer, a slow one or a malformed one is "nothing to do",
/// because an outage of this one endpoint must never lock anyone out of the
/// app.
class AppUpdateService {
  AppUpdateService(this._api);

  final ApiClient _api;

  static const _timeout = Duration(seconds: 5);

  Future<AppUpdate?> check() async {
    final platform = switch (defaultTargetPlatform) {
      TargetPlatform.android => 'android',
      TargetPlatform.iOS => 'ios',
      _ => null,
    };
    if (platform == null) return null;
    try {
      final data = await _api.get(Endpoints.appVersion, query: {
        'platform': platform,
        'build': AppConfig.build,
        'version': AppConfig.version,
      }).timeout(_timeout);
      return data is Map ? AppUpdate.fromJson(J.map(data)) : null;
    } catch (e) {
      debugPrint('AppUpdateService: no answer, carrying on: $e');
      return null;
    }
  }
}
