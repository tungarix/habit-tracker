import 'package:aktenak_habit_tracker/core/stats.dart';
import 'package:aktenak_habit_tracker/data/database/database.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

void main() {
  final start = DateTime(2026, 6, 1);

  group('dayCompletionRate', () {
    final habits = [
      testHabit(id: 1, createdAt: start),
      testHabit(id: 2, createdAt: start),
    ];

    test('is done / scheduled across habits', () {
      final rate = dayCompletionRate(
        habits,
        {
          1: statusMap(done: [DateTime(2026, 6, 10)]),
          2: statusMap(missed: [DateTime(2026, 6, 10)]),
        },
        DateTime(2026, 6, 10),
      );
      expect(rate, closeTo(0.5, 1e-9));
    });

    test('an untracked scheduled day counts against the rate', () {
      final rate = dayCompletionRate(
        habits,
        {1: statusMap(done: [DateTime(2026, 6, 10)])},
        DateTime(2026, 6, 10),
      );
      expect(rate, closeTo(0.5, 1e-9));
    });

    test('skipped habits leave the denominator', () {
      final rate = dayCompletionRate(
        habits,
        {
          1: statusMap(done: [DateTime(2026, 6, 10)]),
          2: statusMap(skipped: [DateTime(2026, 6, 10)]),
        },
        DateTime(2026, 6, 10),
      );
      expect(rate, 1.0);
    });

    test('habits created later are ignored', () {
      final rate = dayCompletionRate(
        [
          testHabit(id: 1, createdAt: start),
          testHabit(id: 2, createdAt: DateTime(2026, 6, 20)),
        ],
        {1: statusMap(done: [DateTime(2026, 6, 10)])},
        DateTime(2026, 6, 10),
      );
      expect(rate, 1.0);
    });

    test('is null when nothing is scheduled that day', () {
      final rate = dayCompletionRate(
        [testHabit(id: 1, createdAt: start, scheduledWeekdays: '1')], // Mondays
        const {},
        DateTime(2026, 6, 10), // a Wednesday
      );
      expect(rate, isNull);
    });
  });

  group('lastNDaysCompletion', () {
    test('averages only the days that had something scheduled', () {
      // Mondays-only habit; over 7 days exactly one Monday is scheduled.
      final habits = [
        testHabit(id: 1, createdAt: start, scheduledWeekdays: '1'),
      ];
      final avg = lastNDaysCompletion(
        habits,
        {1: statusMap(done: [DateTime(2026, 6, 22)])}, // Monday
        DateTime(2026, 6, 28),
        7,
      );
      expect(avg, 1.0);
    });

    test('is 0 when nothing was ever scheduled', () {
      expect(
        lastNDaysCompletion(const <Habit>[], const {}, DateTime(2026, 6, 28), 7),
        0,
      );
    });
  });

  group('habitHeatmap', () {
    test('maps each status and treats an untracked past day as a miss', () {
      final habit = testHabit(id: 1, createdAt: DateTime(2026, 6, 25));
      final cells = habitHeatmap(
        habit,
        statusMap(
          done: [DateTime(2026, 6, 26)],
          skipped: [DateTime(2026, 6, 27)],
          missed: [DateTime(2026, 6, 28)],
        ),
        DateTime(2026, 6, 30),
        6, // 6/25 .. 6/30
      );
      expect(cells, [
        HeatCell.missed, // 6/25 created, untracked
        HeatCell.done, // 6/26
        HeatCell.skipped, // 6/27
        HeatCell.missed, // 6/28
        HeatCell.missed, // 6/29 untracked
        HeatCell.inactive, // 6/30 is today — not a miss yet
      ]);
    });

    test('days before the habit existed are inactive', () {
      final cells = habitHeatmap(
        testHabit(id: 1, createdAt: DateTime(2026, 6, 29)),
        const {},
        DateTime(2026, 6, 30),
        3, // 6/28, 6/29, 6/30
      );
      expect(cells.first, HeatCell.inactive);
    });

    test('off-days are inactive, not misses', () {
      final cells = habitHeatmap(
        testHabit(id: 1, createdAt: start, scheduledWeekdays: '1'), // Mon only
        const {},
        DateTime(2026, 6, 24), // Wednesday
        2, // Tue 6/23, Wed 6/24
      );
      expect(cells, [HeatCell.inactive, HeatCell.inactive]);
    });
  });

  group('pearson', () {
    test('is 1 for a perfectly increasing relationship', () {
      expect(pearson([1, 2, 3, 4], [2, 4, 6, 8]), closeTo(1.0, 1e-9));
    });

    test('is -1 for a perfectly inverse relationship', () {
      expect(pearson([1, 2, 3, 4], [8, 6, 4, 2]), closeTo(-1.0, 1e-9));
    });

    test('is null with fewer than three samples', () {
      expect(pearson([1, 2], [3, 4]), isNull);
    });

    test('is null when a series never varies', () {
      expect(pearson([3, 3, 3, 3], [1, 2, 3, 4]), isNull);
    });
  });

  group('moodCompletionCorrelation', () {
    test("pairs each mood day with that day's completion", () {
      final habits = [testHabit(id: 1, createdAt: start)];
      final result = moodCompletionCorrelation(
        habits,
        {
          1: statusMap(
            done: [DateTime(2026, 6, 10), DateTime(2026, 6, 12)],
            missed: [DateTime(2026, 6, 11)],
          )
        },
        {
          '2026-06-10': testMood(DateTime(2026, 6, 10), 5),
          '2026-06-11': testMood(DateTime(2026, 6, 11), 1),
          '2026-06-12': testMood(DateTime(2026, 6, 12), 4),
        },
        DateTime(2026, 6, 30),
      );

      expect(result.sampleDays, 3);
      expect(result.averageByMood[5], 1.0);
      expect(result.averageByMood[1], 0.0);
      expect(result.daysByMood[4], 1);
      // Good moods line up with completed days here.
      expect(result.r, isNotNull);
      expect(result.r!, greaterThan(0.9));
    });

    test('ignores mood days in the future', () {
      final result = moodCompletionCorrelation(
        [testHabit(id: 1, createdAt: start)],
        const {},
        {'2026-07-05': testMood(DateTime(2026, 7, 5), 3)},
        DateTime(2026, 6, 30),
      );
      expect(result.sampleDays, 0);
      expect(result.r, isNull);
    });

    test('is empty when there are no moods at all', () {
      final result = moodCompletionCorrelation(
        [testHabit(id: 1, createdAt: start)],
        const {},
        const {},
        DateTime(2026, 6, 30),
      );
      expect(result.sampleDays, 0);
      expect(result.averageByMood, isEmpty);
    });
  });
}
