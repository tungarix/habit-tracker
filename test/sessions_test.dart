import 'package:aktenak_habit_tracker/core/enums.dart';
import 'package:aktenak_habit_tracker/core/sessions.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

void main() {
  final today = DateTime(2026, 8, 12);

  group('focusSecondsOn', () {
    test('adds up focus time for one day and ignores breaks', () {
      final total = focusSecondsOn([
        testSession(id: 1, day: today, durationS: 1500),
        testSession(id: 2, day: today, durationS: 900),
        testSession(id: 3, day: today, durationS: 300, kind: SessionKind.rest),
        testSession(id: 4, day: DateTime(2026, 8, 11), durationS: 1200),
      ], today);
      expect(total, 2400);
    });
  });

  group('focusSecondsSeries', () {
    test('returns one bucket per day, oldest first, zero when idle', () {
      final series = focusSecondsSeries([
        testSession(id: 1, day: today, durationS: 600),
        testSession(id: 2, day: DateTime(2026, 8, 10), durationS: 300),
      ], today, 3); // 8/10, 8/11, 8/12
      expect(series, [300, 0, 600]);
    });
  });

  group('summariseFocus', () {
    test('splits today from the rolling week', () {
      final summary = summariseFocus([
        testSession(id: 1, day: today, durationS: 1500),
        testSession(id: 2, day: DateTime(2026, 8, 9), durationS: 1500),
        testSession(id: 3, day: DateTime(2026, 8, 1), durationS: 9000), // old
      ], today);

      expect(summary.todaySeconds, 1500);
      expect(summary.todaySessions, 1);
      expect(summary.last7Seconds, 3000);
      expect(summary.last7Sessions, 2);
    });

    test('counts consecutive focus days as a streak', () {
      final summary = summariseFocus([
        testSession(id: 1, day: today),
        testSession(id: 2, day: DateTime(2026, 8, 11)),
        testSession(id: 3, day: DateTime(2026, 8, 10)),
        // 8/9 missing -> streak stops at 3
        testSession(id: 4, day: DateTime(2026, 8, 8)),
      ], today);
      expect(summary.dayStreak, 3);
    });

    test('an empty today does not break yesterday\'s streak', () {
      final summary = summariseFocus([
        testSession(id: 1, day: DateTime(2026, 8, 11)),
        testSession(id: 2, day: DateTime(2026, 8, 10)),
      ], today);
      expect(summary.dayStreak, 2);
    });

    test('no sessions at all means no streak', () {
      expect(summariseFocus(const [], today).dayStreak, 0);
    });
  });

  group('formatting', () {
    test('durations read the way a human would say them', () {
      expect(formatDuration(45), '45sn');
      expect(formatDuration(1500), '25dk');
      expect(formatDuration(3600), '1s');
      expect(formatDuration(5400), '1s 30dk');
    });

    test('the countdown is always mm:ss and never negative', () {
      expect(formatClock(1500), '25:00');
      expect(formatClock(59), '00:59');
      expect(formatClock(-5), '00:00');
    });
  });
}
