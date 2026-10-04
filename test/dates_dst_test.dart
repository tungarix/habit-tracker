import 'dart:io';

import 'package:aktenak_habit_tracker/core/date_utils.dart';
import 'package:aktenak_habit_tracker/core/streak.dart';
import 'package:aktenak_habit_tracker/core/tasks.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

/// Day arithmetic must be calendar arithmetic. `d.add(Duration(days: 1))` adds
/// 24 *hours*, so on a daylight-saving changeover a local midnight lands on
/// 23:00 the same day (clocks back) or 01:00 two dates on (clocks forward):
/// a day is counted twice or skipped, and streaks break for no reason.
///
/// Honest limit: these tests run in whatever zone the machine is in. In a zone
/// without daylight saving (this dev machine uses Turkey time, UTC+3 all year)
/// `Duration(days: 1)` gives the same answer as the calendar step, so the
/// behavioural tests below cannot go red here on their own. They are a
/// regression net for machines (and CI) in a DST zone; the source guard at the
/// bottom is what fails everywhere if the pattern comes back.
void main() {
  // US (2nd Sunday of March, 1st Sunday of November) and EU (last Sunday of
  // March and October) clock changes, 2024-2027.
  final changeovers = <DateTime>[
    DateTime(2024, 3, 10), DateTime(2024, 11, 3),
    DateTime(2025, 3, 9), DateTime(2025, 11, 2),
    DateTime(2026, 3, 8), DateTime(2026, 11, 1),
    DateTime(2027, 3, 14), DateTime(2027, 11, 7),
    DateTime(2024, 3, 31), DateTime(2024, 10, 27),
    DateTime(2025, 3, 30), DateTime(2025, 10, 26),
    DateTime(2026, 3, 29), DateTime(2026, 10, 25),
    DateTime(2027, 3, 28), DateTime(2027, 10, 31),
  ];

  /// Every calendar day of 2024-01-01 .. 2027-12-31 (1461 days). Generated
  /// from UTC dates, which have no daylight saving, so the list itself never
  /// depends on the helper under test.
  List<DateTime> allDays() => [
        for (var i = 0; i < 1461; i++)
          () {
            final u = DateTime.utc(2024, 1, 1).add(Duration(days: i));
            return DateTime(u.year, u.month, u.day);
          }(),
      ];

  group('test fixture sanity', () {
    test('every listed changeover date is a Sunday', () {
      for (final d in changeovers) {
        expect(d.weekday, DateTime.sunday, reason: '$d should be a Sunday');
      }
    });

    test('the day list covers 2024-2027 without gaps', () {
      final days = allDays();
      expect(days.length, 1461); // 2024 is a leap year
      expect(days.first, DateTime(2024, 1, 1));
      expect(days.last, DateTime(2027, 12, 31));
    });
  });

  group('nextDay / previousDay', () {
    test('step exactly one calendar day for every day of 2024-2027', () {
      final wrong = <String>[];
      final days = allDays();
      for (var i = 0; i < days.length; i++) {
        final d = days[i];
        final next = nextDay(d);
        final prev = previousDay(d);
        if (next != DateTime(d.year, d.month, d.day + 1)) {
          wrong.add('nextDay($d) = $next');
        }
        if (prev != DateTime(d.year, d.month, d.day - 1)) {
          wrong.add('previousDay($d) = $prev');
        }
        if (i + 1 < days.length && dateOnly(next) != days[i + 1]) {
          wrong.add('nextDay($d) skipped or repeated a date: $next');
        }
        if (i > 0 && dateOnly(prev) != days[i - 1]) {
          wrong.add('previousDay($d) skipped or repeated a date: $prev');
        }
        if (nextDay(prev) != d || previousDay(next) != d) {
          wrong.add('nextDay/previousDay are not inverses around $d');
        }
      }
      expect(wrong, isEmpty, reason: wrong.take(10).join('\n'));
    });

    test('around every clock change the neighbouring dates are consecutive',
        () {
      for (final t in changeovers) {
        final before = previousDay(t);
        final after = nextDay(t);
        expect(before, DateTime(t.year, t.month, t.day - 1),
            reason: 'day before $t');
        expect(after, DateTime(t.year, t.month, t.day + 1),
            reason: 'day after $t');
        expect(nextDay(before), t, reason: 'forward over the change at $t');
        expect(previousDay(after), t, reason: 'back over the change at $t');
      }
    });

    test('the time of day is dropped', () {
      expect(nextDay(DateTime(2026, 3, 7, 22, 45)), DateTime(2026, 3, 8));
      expect(previousDay(DateTime(2026, 3, 9, 5)), DateTime(2026, 3, 8));
    });

    test('month, year and leap-day boundaries', () {
      expect(nextDay(DateTime(2026, 7, 31)), DateTime(2026, 8, 1));
      expect(nextDay(DateTime(2026, 12, 31)), DateTime(2027, 1, 1));
      expect(nextDay(DateTime(2028, 2, 28)), DateTime(2028, 2, 29));
      expect(nextDay(DateTime(2028, 2, 29)), DateTime(2028, 3, 1));
      expect(previousDay(DateTime(2028, 3, 1)), DateTime(2028, 2, 29));
      expect(previousDay(DateTime(2027, 1, 1)), DateTime(2026, 12, 31));
    });
  });

  group('calendarDaysBetween', () {
    test('is 1 between consecutive days, whatever the clock did', () {
      final wrong = <String>[];
      final days = allDays();
      for (var i = 0; i + 1 < days.length; i++) {
        if (calendarDaysBetween(days[i], days[i + 1]) != 1) {
          wrong.add('${days[i]} -> ${days[i + 1]}');
        }
        if (calendarDaysBetween(days[i + 1], days[i]) != -1) {
          wrong.add('${days[i + 1]} -> ${days[i]}');
        }
      }
      expect(wrong, isEmpty, reason: wrong.take(10).join('\n'));
    });

    test('counts a whole window across each clock change', () {
      for (final t in changeovers) {
        final from = DateTime(t.year, t.month, t.day - 3);
        final to = DateTime(t.year, t.month, t.day + 4);
        expect(calendarDaysBetween(from, to), 7, reason: 'window around $t');
        expect(calendarDaysBetween(to, from), -7, reason: 'reverse at $t');
        expect(calendarDaysBetween(previousDay(t), nextDay(t)), 2,
            reason: 'across $t');
      }
    });

    test('is 0 for the same day and ignores the time of day', () {
      expect(calendarDaysBetween(DateTime(2026, 10, 4), DateTime(2026, 10, 4)),
          0);
      expect(
        calendarDaysBetween(
          DateTime(2026, 10, 4, 3),
          DateTime(2026, 10, 4, 23, 59),
        ),
        0,
      );
      // Two minutes apart on the clock, one calendar day apart.
      expect(
        calendarDaysBetween(
          DateTime(2026, 3, 8, 23, 59),
          DateTime(2026, 3, 9, 0, 1),
        ),
        1,
      );
      // Almost 24 hours apart on the clock, still a whole calendar day.
      expect(
        calendarDaysBetween(
          DateTime(2026, 3, 8, 0, 1),
          DateTime(2026, 3, 9, 23, 59),
        ),
        1,
      );
    });

    test('spans the four years in one go', () {
      expect(
        calendarDaysBetween(DateTime(2024, 1, 1), DateTime(2027, 12, 31)),
        1460,
      );
      expect(
        calendarDaysBetween(DateTime(2027, 12, 31), DateTime(2024, 1, 1)),
        -1460,
      );
    });
  });

  group('daysBetween', () {
    test('lists every calendar date around each clock change exactly once',
        () {
      for (final t in changeovers) {
        final start = DateTime(t.year, t.month, t.day - 2);
        final end = DateTime(t.year, t.month, t.day + 2);
        expect(daysBetween(start, end), [
          for (var i = -2; i <= 2; i++) DateTime(t.year, t.month, t.day + i),
        ], reason: 'around $t');
      }
    });

    test('a year-long range has one entry per day', () {
      expect(daysBetween(DateTime(2026, 1, 1), DateTime(2026, 12, 31)).length,
          365);
      expect(daysBetween(DateTime(2028, 1, 1), DateTime(2028, 12, 31)).length,
          366);
    });
  });

  group('streaks and stats across clock changes', () {
    test('a daily habit marked every day 2024-2027 is one unbroken run', () {
      final days = allDays();
      final habit = testHabit(createdAt: DateTime(2024, 1, 1, 12));
      final statuses = statusMap(done: days);
      final today = DateTime(2027, 12, 31);

      final streak = computeStreaks(habit, statuses, today);
      expect(streak.current, 1461);
      expect(streak.longest, 1461);

      final stats = computeStats(habit, statuses, today);
      expect(stats.totalScheduled, 1461);
      expect(stats.totalDone, 1461);
      expect(stats.totalSkipped, 0);
      expect(stats.completionRate, 1.0);
    });

    test('a Mon/Wed/Fri habit counts exactly its calendar weekdays', () {
      final days = allDays();
      // Independent oracle: weekday numbers of UTC dates, no local clock.
      final scheduledDays = [
        for (final d in days)
          if ([1, 3, 5].contains(DateTime.utc(d.year, d.month, d.day).weekday))
            d,
      ];
      final habit = testHabit(
        createdAt: DateTime(2024, 1, 1, 12),
        scheduledWeekdays: '1,3,5',
      );
      final statuses = statusMap(done: scheduledDays);
      final today = DateTime(2027, 12, 31);

      final stats = computeStats(habit, statuses, today);
      expect(stats.totalScheduled, scheduledDays.length);
      expect(stats.totalDone, scheduledDays.length);
      expect(stats.streak.current, scheduledDays.length);
      expect(stats.streak.longest, scheduledDays.length);
    });

    test('one untracked day in a clock-change week breaks the run right there',
        () {
      for (final t in changeovers) {
        final first = DateTime(t.year, t.month, t.day - 3);
        final today = DateTime(t.year, t.month, t.day + 3);
        final habit = testHabit(
          createdAt: DateTime(first.year, first.month, first.day, 12),
        );
        final statuses = statusMap(done: [
          for (var i = -3; i <= 3; i++)
            if (i != 0) DateTime(t.year, t.month, t.day + i),
        ]);

        final streak = computeStreaks(habit, statuses, today);
        expect(streak.current, 3, reason: 'run after the gap at $t');
        expect(streak.longest, 3, reason: 'longest at $t');

        final stats = computeStats(habit, statuses, today);
        expect(stats.totalScheduled, 7, reason: 'days in the window at $t');
        expect(stats.totalDone, 6, reason: 'marked days at $t');
      }
    });

    test('a fully marked week over each clock change stays unbroken', () {
      for (final t in changeovers) {
        final first = DateTime(t.year, t.month, t.day - 3);
        final today = DateTime(t.year, t.month, t.day + 3);
        final habit = testHabit(
          createdAt: DateTime(first.year, first.month, first.day, 12),
        );
        final statuses = statusMap(done: daysBetween(first, today));

        final streak = computeStreaks(habit, statuses, today);
        expect(streak.current, 7, reason: 'current at $t');
        expect(streak.longest, 7, reason: 'longest at $t');
        expect(computeStats(habit, statuses, today).totalScheduled, 7,
            reason: 'scheduled at $t');
      }
    });
  });

  group('bucketFor across clock changes', () {
    // Distance in calendar days -> expected bucket.
    DueBucket expected(int k) {
      if (k < 0) return DueBucket.overdue;
      if (k == 0) return DueBucket.today;
      if (k == 1) return DueBucket.tomorrow;
      if (k <= 7) return DueBucket.thisWeek;
      return DueBucket.later;
    }

    test('every day of 2024-2027 buckets by calendar distance', () {
      final wrong = <String>[];
      for (final today in allDays()) {
        for (final k in [-8, -1, 0, 1, 2, 7, 8]) {
          final due = DateTime(today.year, today.month, today.day + k);
          final bucket = bucketFor(testTask(dueDay: due), today);
          if (bucket != expected(k)) {
            wrong.add('today $today, due $due: $bucket, wanted ${expected(k)}');
          }
        }
      }
      expect(wrong, isEmpty, reason: wrong.take(10).join('\n'));
    });

    test('the day before and after a clock change are today/tomorrow apart',
        () {
      for (final t in changeovers) {
        final before = previousDay(t);
        expect(bucketFor(testTask(dueDay: t), before), DueBucket.tomorrow,
            reason: 'due on $t, today the day before');
        expect(bucketFor(testTask(dueDay: before), t), DueBucket.overdue,
            reason: 'due the day before $t, today $t');
        expect(bucketFor(testTask(dueDay: t), t), DueBucket.today);
      }
    });
  });

  group('source guard', () {
    // The behavioural tests above only bite in a daylight-saving time zone.
    // This one bites everywhere: it stops the 24-hour-day pattern from being
    // written again anywhere in lib/.
    final libFiles = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart') && !f.path.endsWith('.g.dart'))
        .toList();

    test('lib/ is scanned (the guard is not satisfied by an empty folder)', () {
      expect(libFiles.length, greaterThan(20));
    });

    test('no day stepping with Duration(days: ...) anywhere in lib/', () {
      final offenders = <String>[];
      for (final file in libFiles) {
        for (final (i, line) in file.readAsLinesSync().indexed) {
          if (line.trimLeft().startsWith('//')) continue;
          if (RegExp(r'Duration\(\s*days\s*:').hasMatch(line)) {
            offenders.add('${file.path}:${i + 1}: ${line.trim()}');
          }
        }
      }
      expect(
        offenders,
        isEmpty,
        reason: 'Use nextDay/previousDay (date_utils.dart): a Duration of days '
            'is 24 hours, which breaks on daylight-saving days.\n'
            '${offenders.join('\n')}',
      );
    });

    test('.inDays only appears in date_utils.dart (calendarDaysBetween)', () {
      final offenders = <String>[];
      for (final file in libFiles) {
        if (file.path.replaceAll('\\', '/').endsWith('lib/core/date_utils.dart')) {
          continue;
        }
        for (final (i, line) in file.readAsLinesSync().indexed) {
          if (line.trimLeft().startsWith('//')) continue;
          if (line.contains('.inDays')) {
            offenders.add('${file.path}:${i + 1}: ${line.trim()}');
          }
        }
      }
      expect(
        offenders,
        isEmpty,
        reason: 'Use calendarDaysBetween (date_utils.dart) for a difference '
            'in calendar days: inDays on local dates is off by one on a '
            '23-hour daylight-saving day.\n${offenders.join('\n')}',
      );
    });
  });
}
