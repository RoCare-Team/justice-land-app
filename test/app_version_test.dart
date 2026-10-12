// AppConfig.version and .build are typed by hand; this keeps them the version
// being shipped.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_legal_care/core/config/app_config.dart';

void main() {
  test('AppConfig.version matches pubspec.yaml', () {
    final line = File('pubspec.yaml')
        .readAsLinesSync()
        .firstWhere((l) => l.startsWith('version:'));
    final name = line.substring('version:'.length).trim().split('+').first;
    expect(AppConfig.version, name,
        reason: 'Bump AppConfig.version along with version: in pubspec.yaml');
  });

  test('AppConfig.build matches the build number in pubspec.yaml', () {
    final line = File('pubspec.yaml')
        .readAsLinesSync()
        .firstWhere((l) => l.startsWith('version:'));
    final build = int.parse(line.split('+').last.trim());
    expect(AppConfig.build, build,
        reason: 'Bump AppConfig.build along with the +build in pubspec.yaml');
  });
}
