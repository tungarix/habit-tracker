import 'package:aktenak_habit_tracker/features/dashboard/widgets/focus_card.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final start = DateTime(2026, 6, 23, 23, 0);

  test('seans süresi planı aşamaz (uyku sonrası şişmez)', () {
    final wake = start.add(const Duration(hours: 8, minutes: 15));
    expect(focusElapsedSeconds(start, wake, 25 * 60), 25 * 60);
  });

  test('normal seansta duvar saati farkı döner', () {
    final now = start.add(const Duration(minutes: 10, seconds: 30));
    expect(focusElapsedSeconds(start, now, 25 * 60), 630);
  });

  test('saat geri alınırsa süre negatif olmaz', () {
    final now = start.subtract(const Duration(hours: 1));
    expect(focusElapsedSeconds(start, now, 25 * 60), 0);
  });
}
