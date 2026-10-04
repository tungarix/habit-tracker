import 'package:aktenak_habit_tracker/core/date_utils.dart';
import 'package:aktenak_habit_tracker/core/enums.dart';
import 'package:aktenak_habit_tracker/core/streak.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

// Fixtures live in helpers.dart so a schema change touches one file.
final _habit = testHabit;
final _statuses = statusMap;

void main() {
  group('date utils', () {
    test('empty schedule means every day', () {
      expect(isScheduledOn('', DateTime(2026, 6, 22)), isTrue); // Monday
      expect(isScheduledOn('', DateTime(2026, 6, 28)), isTrue); // Sunday
    });

    test('weekday filtering', () {
      // Mon=1..Sun=7. 2026-06-22 is a Monday.
      expect(isScheduledOn('1,3,5', DateTime(2026, 6, 22)), isTrue); // Mon
      expect(isScheduledOn('1,3,5', DateTime(2026, 6, 23)), isFalse); // Tue
    });

    test('parse/serialise weekdays roundtrip', () {
      expect(parseWeekdays('5,1,3'), [1, 3, 5]);
      expect(weekdaysToString([3, 1, 5, 1]), '1,3,5');
    });

    test('daysInMonth', () {
      expect(daysInMonth(DateTime(2026, 2, 15)), 28);
      expect(daysInMonth(DateTime(2028, 2, 1)), 29); // leap year
      expect(daysInMonth(DateTime(2026, 7, 1)), 31);
    });
  });

  group('status cycle', () {
    test('boş → ✓ → ✗ → – → boş', () {
      expect(nextStatus(null), EntryStatus.done);
      expect(nextStatus(EntryStatus.done), EntryStatus.missed);
      expect(nextStatus(EntryStatus.missed), EntryStatus.skipped);
      expect(nextStatus(EntryStatus.skipped), isNull);
    });
  });

  group('streaks (everyday habit)', () {
    final habit = _habit(createdAt: DateTime(2026, 6, 1));
    final todayDate = DateTime(2026, 6, 23);

    test('consecutive done days build the current streak', () {
      final s = computeStreaks(
        habit,
        _statuses(done: [
          DateTime(2026, 6, 21),
          DateTime(2026, 6, 22),
          DateTime(2026, 6, 23),
        ]),
        todayDate,
      );
      expect(s.current, 3);
      expect(s.longest, 3);
    });

    test('today not yet marked does not break the streak', () {
      final s = computeStreaks(
        habit,
        _statuses(done: [
          DateTime(2026, 6, 21),
          DateTime(2026, 6, 22),
          // 6/23 (today) untracked
        ]),
        todayDate,
      );
      expect(s.current, 2);
    });

    test('an untracked past day breaks the current streak', () {
      final s = computeStreaks(
        habit,
        _statuses(done: [
          DateTime(2026, 6, 20),
          // 6/21 untracked
          DateTime(2026, 6, 22),
          DateTime(2026, 6, 23),
        ]),
        todayDate,
      );
      expect(s.current, 2);
      expect(s.longest, 2);
    });

    test('an explicit missed (✗) breaks the streak, today included', () {
      final s = computeStreaks(
        habit,
        _statuses(
          done: [DateTime(2026, 6, 21), DateTime(2026, 6, 22)],
          missed: [DateTime(2026, 6, 23)], // today explicitly failed
        ),
        todayDate,
      );
      expect(s.current, 0);
      expect(s.longest, 2);
    });

    test('a skipped (–) day is neutral: does not break, does not count', () {
      final s = computeStreaks(
        habit,
        _statuses(
          done: [DateTime(2026, 6, 20), DateTime(2026, 6, 21), DateTime(2026, 6, 23)],
          skipped: [DateTime(2026, 6, 22)],
        ),
        todayDate,
      );
      expect(s.current, 3);
      expect(s.longest, 3);
    });
  });

  group('streaks (scheduled habit)', () {
    // Mon/Wed/Fri only.
    final habit = _habit(createdAt: DateTime(2026, 6, 1), scheduledWeekdays: '1,3,5');
    final todayDate = DateTime(2026, 6, 22); // Monday

    test('unscheduled days do not break the streak', () {
      // Done on Fri 6/19 and Mon 6/22; the weekend in between is unscheduled.
      final s = computeStreaks(
        habit,
        _statuses(done: [DateTime(2026, 6, 19), DateTime(2026, 6, 22)]),
        todayDate,
      );
      expect(s.current, 2);
    });
  });

  group('stats', () {
    test('completion rate counts only scheduled days', () {
      final habit = _habit(createdAt: DateTime(2026, 6, 22), scheduledWeekdays: '1,2,3');
      final todayDate = DateTime(2026, 6, 24); // Wed; scheduled Mon,Tue,Wed
      final stats = computeStats(
        habit,
        _statuses(done: [DateTime(2026, 6, 22), DateTime(2026, 6, 24)]), // 2 of 3
        todayDate,
      );
      expect(stats.totalScheduled, 3);
      expect(stats.totalDone, 2);
      expect(stats.completionRate, closeTo(2 / 3, 1e-9));
    });

    test('skipped days are excluded from the denominator', () {
      // Noon, not midnight: before 04:00 a creation stamp counts for the
      // previous tracking day (see night_creation_test.dart).
      final habit = _habit(createdAt: DateTime(2026, 6, 20, 12));
      final todayDate = DateTime(2026, 6, 23); // 4 days total
      final stats = computeStats(
        habit,
        _statuses(
          done: [DateTime(2026, 6, 20), DateTime(2026, 6, 22)],
          skipped: [DateTime(2026, 6, 21)],
          missed: [DateTime(2026, 6, 23)],
        ),
        todayDate,
      );
      expect(stats.totalScheduled, 3); // 4 days - 1 skipped
      expect(stats.totalDone, 2);
      expect(stats.totalSkipped, 1);
      expect(stats.completionRate, closeTo(2 / 3, 1e-9));
    });
  });
}
