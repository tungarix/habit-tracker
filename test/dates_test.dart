import 'package:aktenak_habit_tracker/core/date_utils.dart';
import 'package:flutter_test/flutter_test.dart';

/// The day-start rule decides which day a mark belongs to. It is the single
/// most expensive thing to get wrong later, so it gets its own test file.
void main() {
  group('dayOf — default start hour (04:00)', () {
    test('a mark made after midnight counts for the day that just ended', () {
      // Real case from this user's data: written 2026-07-31 01:35.
      expect(dayOf(DateTime(2026, 7, 31, 1, 35)), DateTime(2026, 7, 30));
    });

    test('03:59 is still the previous day, 04:00 starts the new one', () {
      expect(dayOf(DateTime(2026, 7, 31, 3, 59)), DateTime(2026, 7, 30));
      expect(dayOf(DateTime(2026, 7, 31, 4)), DateTime(2026, 7, 31));
    });

    test('daytime marks land on the obvious day', () {
      expect(dayOf(DateTime(2026, 7, 31, 10)), DateTime(2026, 7, 31));
      expect(dayOf(DateTime(2026, 7, 31, 23, 59)), DateTime(2026, 7, 31));
    });

    test('rolls back across a month boundary', () {
      expect(dayOf(DateTime(2026, 8, 1, 2)), DateTime(2026, 7, 31));
    });

    test('rolls back across a year boundary', () {
      expect(dayOf(DateTime(2027, 1, 1, 1)), DateTime(2026, 12, 31));
    });

    test('rolls back into a leap day', () {
      expect(dayOf(DateTime(2028, 3, 1, 2)), DateTime(2028, 2, 29));
    });
  });

  group('dayOf — configurable start hour', () {
    test('hour 0 means plain calendar days', () {
      expect(dayOf(DateTime(2026, 7, 31, 1, 35), dayStartHour: 0),
          DateTime(2026, 7, 31));
    });

    test('a later start hour extends the night further', () {
      expect(dayOf(DateTime(2026, 7, 31, 5), dayStartHour: 6),
          DateTime(2026, 7, 30));
      expect(dayOf(DateTime(2026, 7, 31, 6), dayStartHour: 6),
          DateTime(2026, 7, 31));
    });
  });

  group('nextDayBoundary', () {
    test('is the coming 04:00 for an evening instant', () {
      expect(
        nextDayBoundary(DateTime(2026, 7, 30, 22)),
        DateTime(2026, 7, 31, 4),
      );
    });

    test('is later the same morning for a post-midnight instant', () {
      // 01:35 belongs to 7/30, whose day ends at 7/31 04:00.
      expect(
        nextDayBoundary(DateTime(2026, 7, 31, 1, 35)),
        DateTime(2026, 7, 31, 4),
      );
    });

    test('always lies in the future', () {
      for (final hour in [0, 3, 4, 5, 12, 23]) {
        final instant = DateTime(2026, 7, 30, hour, 30);
        expect(nextDayBoundary(instant).isAfter(instant), isTrue,
            reason: 'boundary must be ahead of $instant');
      }
    });
  });

  group('lastDays', () {
    test('returns count days ending at the given day, oldest first', () {
      final days = lastDays(DateTime(2026, 8, 2), 3);
      expect(days, [
        DateTime(2026, 7, 31),
        DateTime(2026, 8, 1),
        DateTime(2026, 8, 2),
      ]);
    });

    test('crosses a month boundary correctly', () {
      expect(lastDays(DateTime(2026, 3, 1), 2).first, DateTime(2026, 2, 28));
    });
  });
}
