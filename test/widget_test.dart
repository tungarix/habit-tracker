import 'package:aktenak_habit_tracker/core/date_utils.dart';
import 'package:aktenak_habit_tracker/core/streak.dart';
import 'package:aktenak_habit_tracker/data/database/database.dart';
import 'package:flutter_test/flutter_test.dart';

Habit _habit({
  DateTime? createdAt,
  String scheduledWeekdays = '',
}) {
  return Habit(
    id: 1,
    name: 'Test',
    description: null,
    colorValue: 0xFF4CAF50,
    iconCodePoint: 0xe000,
    createdAt: createdAt ?? DateTime(2026, 1, 1),
    archivedAt: null,
    sortOrder: 0,
    scheduledWeekdays: scheduledWeekdays,
  );
}

Set<String> _dates(Iterable<DateTime> ds) => ds.map(formatYmd).toSet();

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
  });

  group('streaks (everyday habit)', () {
    final habit = _habit(createdAt: DateTime(2026, 6, 1));
    final todayDate = DateTime(2026, 6, 23);

    test('consecutive done days build the current streak', () {
      final done = _dates([
        DateTime(2026, 6, 21),
        DateTime(2026, 6, 22),
        DateTime(2026, 6, 23),
      ]);
      final s = computeStreaks(habit, done, todayDate);
      expect(s.current, 3);
      expect(s.longest, 3);
    });

    test("today not yet done does not break the streak", () {
      final done = _dates([
        DateTime(2026, 6, 21),
        DateTime(2026, 6, 22),
        // 6/23 (today) not done yet
      ]);
      final s = computeStreaks(habit, done, todayDate);
      expect(s.current, 2);
    });

    test('a missed past day breaks the current streak', () {
      final done = _dates([
        DateTime(2026, 6, 20),
        // 6/21 missed
        DateTime(2026, 6, 22),
        DateTime(2026, 6, 23),
      ]);
      final s = computeStreaks(habit, done, todayDate);
      expect(s.current, 2);
      expect(s.longest, 2);
    });
  });

  group('streaks (scheduled habit)', () {
    // Mon/Wed/Fri only.
    final habit = _habit(createdAt: DateTime(2026, 6, 1), scheduledWeekdays: '1,3,5');
    final todayDate = DateTime(2026, 6, 22); // Monday

    test('unscheduled days do not break the streak', () {
      // Done on Fri 6/19 and Mon 6/22; the weekend in between is unscheduled.
      final done = _dates([DateTime(2026, 6, 19), DateTime(2026, 6, 22)]);
      final s = computeStreaks(habit, done, todayDate);
      expect(s.current, 2);
    });
  });

  group('stats', () {
    test('completion rate counts only scheduled days', () {
      final habit = _habit(createdAt: DateTime(2026, 6, 22), scheduledWeekdays: '1,2,3');
      final todayDate = DateTime(2026, 6, 24); // Wed; scheduled Mon,Tue,Wed
      final done = _dates([DateTime(2026, 6, 22), DateTime(2026, 6, 24)]); // 2 of 3
      final stats = computeStats(habit, done, todayDate);
      expect(stats.totalScheduled, 3);
      expect(stats.totalDone, 2);
      expect(stats.completionRate, closeTo(2 / 3, 1e-9));
    });
  });
}
