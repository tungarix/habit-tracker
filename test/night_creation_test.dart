import 'package:aktenak_habit_tracker/core/date_utils.dart';
import 'package:aktenak_habit_tracker/core/stats.dart';
import 'package:aktenak_habit_tracker/core/streak.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

/// A habit added between midnight and the day-start hour belongs to the
/// *tracking* day that is still running, not to the next calendar day. Before
/// the fix every start-day check used the calendar day, so a mark made that
/// night fell "before the habit existed" and vanished from streaks, stats and
/// the heat strip.
void main() {
  final oct3 = DateTime(2026, 10, 3);
  final oct4 = DateTime(2026, 10, 4);
  final oct5 = DateTime(2026, 10, 5);

  // Added on the night of 4 -> 5 October. Tracking day (04:00 start): 4 Oct.
  final night = testHabit(id: 1, createdAt: DateTime(2026, 10, 5, 1, 30));

  group('computeStreaks / computeStats — created at 01:30', () {
    test('a mark on the creation tracking day builds the streak', () {
      final s = computeStreaks(night, statusMap(done: [oct4]), oct4);
      expect(s.current, 1);
      expect(s.longest, 1);
    });

    test('computeStats counts that day as scheduled and done', () {
      final stats = computeStats(night, statusMap(done: [oct4]), oct4);
      expect(stats.totalScheduled, 1);
      expect(stats.totalDone, 1);
      expect(stats.totalSkipped, 0);
      expect(stats.completionRate, 1.0);
      // The streak embedded in the stats must follow the same rule.
      expect(stats.streak.current, 1);
      expect(stats.streak.longest, 1);
    });

    test('the next day, still untracked, extends nothing but breaks nothing',
        () {
      final statuses = statusMap(done: [oct4]);
      final s = computeStreaks(night, statuses, oct5);
      expect(s.current, 1); // 5 Oct is today and not marked yet: grace
      expect(s.longest, 1);

      final stats = computeStats(night, statuses, oct5);
      expect(stats.totalScheduled, 2);
      expect(stats.totalDone, 1);
    });

    test('an unmarked creation day is a real miss once it is in the past', () {
      final stats = computeStats(night, const {}, oct5);
      expect(stats.totalScheduled, 2); // 4 Oct (missed) + 5 Oct (open)
      expect(stats.totalDone, 0);
      expect(computeStreaks(night, const {}, oct5).current, 0);
    });

    test('03:59 still belongs to the previous day, 04:00 starts the new one',
        () {
      final justBefore =
          testHabit(id: 2, createdAt: DateTime(2026, 10, 5, 3, 59));
      final justAfter = testHabit(id: 3, createdAt: DateTime(2026, 10, 5, 4));
      final statuses = statusMap(done: [oct4]);

      expect(computeStreaks(justBefore, statuses, oct4).current, 1);
      // Created at 04:00 sharp: its first day is 5 Oct, which is after today.
      expect(computeStreaks(justAfter, statuses, oct4).current, 0);
      expect(computeStats(justAfter, statuses, oct4).totalScheduled, 0);
    });
  });

  group('dayCompletionRate — created at 01:30', () {
    final older = testHabit(id: 2, createdAt: DateTime(2026, 6, 1, 12));

    test('counts the night-created habit on its tracking day', () {
      final rate = dayCompletionRate(
        [night, older],
        {
          1: statusMap(done: [oct4]),
          2: statusMap(missed: [oct4]),
        },
        oct4,
      );
      expect(rate, closeTo(0.5, 1e-9)); // 1 done of 2 scheduled
    });

    test('a habit created that night alone gives a rate, not null', () {
      expect(
        dayCompletionRate([night], {1: statusMap(done: [oct4])}, oct4),
        1.0,
      );
    });

    test('the day before the creation tracking day still ignores the habit',
        () {
      expect(dayCompletionRate([night], const {}, oct3), isNull);
    });
  });

  group('habitHeatmap / habitHeatPoints — created at 01:30', () {
    test('the 4 October cell is done', () {
      final cells = habitHeatmap(night, statusMap(done: [oct4]), oct4, 3);
      expect(cells, [
        HeatCell.inactive, // 2 Oct, before the habit
        HeatCell.inactive, // 3 Oct, before the habit
        HeatCell.done, // 4 Oct
      ]);
    });

    test('an unmarked creation day reads as a miss, not as "before"', () {
      final cells = habitHeatmap(night, const {}, oct5, 3);
      expect(cells, [
        HeatCell.inactive, // 3 Oct, before the habit
        HeatCell.missed, // 4 Oct, the creation tracking day, left untracked
        HeatCell.inactive, // 5 Oct is today: not a miss yet
      ]);
    });

    test('a count habit that fell short on that day keeps its progress', () {
      final counter = testHabit(
        id: 4,
        createdAt: DateTime(2026, 10, 5, 1, 30),
        kind: 'count',
        target: 10000,
      );
      final points = habitHeatPoints(
        counter,
        const {}, // 5 000 of 10 000 steps: no ✓ yet
        {formatYmd(oct4): 5000},
        oct5,
        3,
      );
      expect(points[1].cell, HeatCell.missed);
      expect(points[1].intensity, closeTo(0.5, 1e-9));
    });
  });

  group('rolling aggregates — created at 01:30', () {
    test('dailyCompletionSeries includes the creation tracking day', () {
      final series = dailyCompletionSeries(
        [night],
        {1: statusMap(done: [oct4])},
        oct5,
        3,
      );
      expect(series, [null, 1.0, 0.0]);
    });

    test('lastNDaysCompletion averages over it', () {
      final avg = lastNDaysCompletion(
        [night],
        {1: statusMap(done: [oct4])},
        oct5,
        3,
      );
      expect(avg, closeTo(0.5, 1e-9)); // (1.0 + 0.0) / 2 scheduled days
    });

    test('moodCompletionCorrelation pairs a mood on that day', () {
      final correlation = moodCompletionCorrelation(
        [night],
        {1: statusMap(done: [oct4])},
        {formatYmd(oct4): testMood(oct4, 4)},
        oct5,
      );
      expect(correlation.sampleDays, 1);
      expect(correlation.daysByMood, {4: 1});
      expect(correlation.averageByMood[4], 1.0);
    });
  });

  group('custom day-start hour', () {
    // With a 06:00 start, 05:00 still belongs to the night before and 07:00
    // starts the new day.
    final earlyMorning = testHabit(id: 1, createdAt: DateTime(2026, 10, 5, 5));
    final lateMorning = testHabit(id: 2, createdAt: DateTime(2026, 10, 5, 7));

    test('05:00 and 07:00 fall on different tracking days at hour 6', () {
      expect(dayOf(earlyMorning.createdAt, dayStartHour: 6), oct4);
      expect(dayOf(lateMorning.createdAt, dayStartHour: 6), oct5);
    });

    test('computeStreaks follows the configured hour', () {
      final statuses = statusMap(done: [oct4]);
      expect(
        computeStreaks(earlyMorning, statuses, oct4, dayStartHour: 6).current,
        1,
      );
      expect(
        computeStreaks(lateMorning, statuses, oct4, dayStartHour: 6).current,
        0,
      );
      // With the default 04:00 the 05:00 habit starts on 5 October instead.
      expect(computeStreaks(earlyMorning, statuses, oct4).current, 0);
    });

    test('computeStats follows the configured hour', () {
      final statuses = statusMap(done: [oct4]);
      final at6 = computeStats(earlyMorning, statuses, oct4, dayStartHour: 6);
      expect(at6.totalScheduled, 1);
      expect(at6.totalDone, 1);
      expect(at6.streak.current, 1); // forwarded to the embedded streak too
      expect(computeStats(earlyMorning, statuses, oct4).totalScheduled, 0);
    });

    test('dayCompletionRate follows the configured hour', () {
      final byHabit = {1: statusMap(done: [oct4])};
      expect(
        dayCompletionRate([earlyMorning], byHabit, oct4, dayStartHour: 6),
        1.0,
      );
      expect(dayCompletionRate([earlyMorning], byHabit, oct4), isNull);
    });

    test('dailyCompletionSeries follows the configured hour', () {
      final byHabit = {1: statusMap(done: [oct4])};
      expect(
        dailyCompletionSeries([earlyMorning], byHabit, oct4, 2,
            dayStartHour: 6),
        [null, 1.0],
      );
      expect(dailyCompletionSeries([earlyMorning], byHabit, oct4, 2),
          [null, null]);
    });

    test('lastNDaysCompletion follows the configured hour', () {
      final byHabit = {1: statusMap(done: [oct4])};
      expect(
        lastNDaysCompletion([earlyMorning], byHabit, oct4, 2, dayStartHour: 6),
        1.0,
      );
      expect(lastNDaysCompletion([earlyMorning], byHabit, oct4, 2), 0.0);
    });

    test('habitHeatmap follows the configured hour', () {
      // Nothing marked, looking back from 5 Oct: 4 Oct is a miss only when the
      // habit already existed that day.
      expect(
        habitHeatmap(earlyMorning, const {}, oct5, 2, dayStartHour: 6),
        [HeatCell.missed, HeatCell.inactive],
      );
      expect(
        habitHeatmap(earlyMorning, const {}, oct5, 2),
        [HeatCell.inactive, HeatCell.inactive],
      );
    });

    test('habitHeatPoints follows the configured hour', () {
      final counter = testHabit(
        id: 5,
        createdAt: DateTime(2026, 10, 5, 5),
        kind: 'count',
        target: 10,
      );
      final values = {formatYmd(oct4): 5};
      final at6 =
          habitHeatPoints(counter, const {}, values, oct5, 2, dayStartHour: 6);
      expect(at6.first.cell, HeatCell.missed);
      expect(at6.first.intensity, closeTo(0.5, 1e-9));

      final atDefault = habitHeatPoints(counter, const {}, values, oct5, 2);
      expect(atDefault.first.cell, HeatCell.inactive);
      expect(atDefault.first.intensity, 0.0);
    });

    test('moodCompletionCorrelation follows the configured hour', () {
      final byHabit = {1: statusMap(done: [oct4])};
      final moods = {formatYmd(oct4): testMood(oct4, 3)};
      final at6 = moodCompletionCorrelation(
        [earlyMorning],
        byHabit,
        moods,
        oct5,
        dayStartHour: 6,
      );
      expect(at6.sampleDays, 1);
      final atDefault =
          moodCompletionCorrelation([earlyMorning], byHabit, moods, oct5);
      expect(atDefault.sampleDays, 0);
    });
  });

  group('habits created in the daytime are unaffected', () {
    // 14:00 is the same day under every start hour, so these must read exactly
    // as they did when the start day was the calendar date.
    final day = testHabit(id: 1, createdAt: DateTime(2026, 10, 1, 14));
    final doneThrough3 = statusMap(done: [
      DateTime(2026, 10, 1),
      DateTime(2026, 10, 2),
      oct3,
    ]);

    test('streaks and stats start on the creation date', () {
      final s = computeStreaks(day, doneThrough3, oct4);
      expect(s.current, 3); // 4 Oct is today, unmarked: grace
      expect(s.longest, 3);

      final stats = computeStats(day, doneThrough3, oct4);
      expect(stats.totalScheduled, 4);
      expect(stats.totalDone, 3);
      expect(stats.completionRate, closeTo(0.75, 1e-9));
    });

    test('the result does not depend on the start hour', () {
      for (final hour in [0, 4, 6, 12]) {
        final stats = computeStats(day, doneThrough3, oct4, dayStartHour: hour);
        expect(stats.totalScheduled, 4, reason: 'hour $hour');
        expect(stats.streak.current, 3, reason: 'hour $hour');
      }
    });

    test('the day before creation is still "before"', () {
      final byHabit = {1: doneThrough3};
      expect(dayCompletionRate([day], byHabit, DateTime(2026, 9, 30)), isNull);
      expect(dayCompletionRate([day], byHabit, DateTime(2026, 10, 1)), 1.0);

      expect(
        habitHeatmap(day, doneThrough3, oct4, 5),
        [
          HeatCell.inactive, // 30 Sep
          HeatCell.done, // 1 Oct
          HeatCell.done, // 2 Oct
          HeatCell.done, // 3 Oct
          HeatCell.inactive, // 4 Oct is today
        ],
      );
    });

    test('a habit created tomorrow in the daytime does not exist yet', () {
      final tomorrow = testHabit(id: 2, createdAt: DateTime(2026, 10, 5, 14));
      final s = computeStreaks(tomorrow, const {}, oct4);
      expect(s.current, 0);
      expect(s.longest, 0);
      expect(computeStats(tomorrow, const {}, oct4).totalScheduled, 0);
      expect(dayCompletionRate([tomorrow], const {}, oct4), isNull);
    });
  });
}
