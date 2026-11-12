import 'package:aktenak_habit_tracker/core/streak.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

void main() {
  final today = DateTime(2026, 6, 23);
  final tenDays = [for (var i = 1; i <= 10; i++) DateTime(2026, 6, 23 - i)];

  group('sayaçlı alışkanlıkta bugünkü kısmi miktar seriyi bozmaz', () {
    final count = testHabit(
      createdAt: DateTime(2026, 6, 1),
      kind: 'count',
      target: 10000,
    );

    test('bugün hedefin altı (✗ olarak yazılır): seri korunur', () {
      final s = computeStreaks(
        count,
        statusMap(done: tenDays, missed: [today]),
        today,
      );
      expect(s.current, 10);
      expect(s.longest, 10);
    });

    test('geçmiş günün kısmi miktarı seriyi yine bozar', () {
      final s = computeStreaks(
        count,
        statusMap(done: tenDays.skip(1), missed: [tenDays.first, today]),
        today,
      );
      expect(s.current, 0);
    });

    test('hedef tamamlanınca bugün seriye eklenir', () {
      final s = computeStreaks(
        count,
        statusMap(done: [...tenDays, today]),
        today,
      );
      expect(s.current, 11);
    });
  });

  test('ikili alışkanlıkta bugünkü açık ✗ seriyi bozmaya devam eder', () {
    final s = computeStreaks(
      testHabit(createdAt: DateTime(2026, 6, 1)),
      statusMap(done: tenDays, missed: [today]),
      today,
    );
    expect(s.current, 0);
  });
}
