// An audio or video call is billed from the moment it connects, not from the
// lawyer's Accept: the model reads zero until the server says the clock has
// started, and the reporter that tells it so retries and reports once.

import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_legal_care/core/network/api_exception.dart';
import 'package:flutter_legal_care/features/consultation/call_clock.dart';
import 'package:flutter_legal_care/models/consultation.dart';

Consultation _session({required String type, required bool clockStarted, String status = 'active'}) {
  final now = DateTime.now().toUtc();
  return Consultation.fromJson({
    'id': 'c1',
    'userId': 'u1',
    'userName': 'Asim',
    'advocateId': 'a1',
    'advocateName': 'Robin',
    'type': type,
    'status': status,
    'rate': 10,
    'maxMinutes': 30,
    'createdAt': now.subtract(const Duration(minutes: 2)).toIso8601String(),
    'startedAt': now.subtract(const Duration(seconds: 9)).toIso8601String(),
    'endsAt': now.add(const Duration(minutes: 29)).toIso8601String(),
    'remainingMs': const Duration(minutes: 29).inMilliseconds,
    'callClockStarted': clockStarted,
  });
}

void main() {
  group('the clock of an audio or video session', () {
    test('reads zero, and nothing billed, while the call is still connecting', () {
      for (final type in ['audio', 'video']) {
        final s = _session(type: type, clockStarted: false);
        expect(s.awaitingCallClock, isTrue, reason: type);
        expect(s.elapsed, Duration.zero, reason: type);
        expect(s.elapsedMinutes, 0, reason: type);
        expect(s.runningCost, 0, reason: type);
      }
    });

    test('runs once the call has connected', () {
      final s = _session(type: 'audio', clockStarted: true);
      expect(s.awaitingCallClock, isFalse);
      expect(s.elapsed.inSeconds, greaterThanOrEqualTo(8));
      expect(s.runningCost, 10, reason: 'a started minute is a billed minute');
    });

    test('a chat session is on its own clock, unaffected', () {
      final s = _session(type: 'chat', clockStarted: false);
      expect(s.awaitingCallClock, isFalse);
      expect(s.elapsed.inSeconds, greaterThanOrEqualTo(8));
    });

    test('a finished session is never "waiting"', () {
      expect(_session(type: 'audio', clockStarted: false, status: 'ended').awaitingCallClock, isFalse);
    });
  });

  group('CallClockReporter', () {
    test('reports once, then re-reads the session', () async {
      var sent = 0;
      var reloaded = 0;
      final r = CallClockReporter(() async => sent++, () async => reloaded++);

      await r.report();
      await r.report(); // a reconnect, or the second event for the same call

      expect(sent, 1);
      expect(reloaded, 1);
    });

    test('retries a failed report, then succeeds', () async {
      var sent = 0;
      var reloaded = 0;
      final r = CallClockReporter(
        () async {
          sent++;
          if (sent < 3) throw ApiException(message: 'offline');
        },
        () async => reloaded++,
        retryDelay: Duration.zero,
      );

      await r.report();

      expect(sent, 3);
      expect(reloaded, 1);
    });

    test('gives up after its attempts, and lets a later connect event try again', () async {
      var sent = 0;
      final r = CallClockReporter(
        () async {
          sent++;
          throw ApiException(message: 'offline');
        },
        () async {},
        retryDelay: Duration.zero,
        attempts: 3,
      );

      await r.report();
      expect(sent, 3);

      await r.report();
      expect(sent, 6);
    });

    test('stops once the screen is gone', () async {
      var sent = 0;
      final r = CallClockReporter(
        () async {
          sent++;
          throw ApiException(message: 'offline');
        },
        () async {},
        retryDelay: Duration.zero,
      );

      final done = r.report();
      r.cancel();
      await done;

      expect(sent, lessThan(4));
    });
  });
}
