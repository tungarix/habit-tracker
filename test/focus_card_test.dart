import 'package:aktenak_habit_tracker/features/dashboard/widgets/focus_card.dart';
import 'package:aktenak_habit_tracker/core/sessions.dart';
import 'package:aktenak_habit_tracker/data/providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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

  testWidgets('çalışan seans varken tepsi Çıkış kancası seansı durdurur', (tester) async {
    tester.view.physicalSize = const Size(1000, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        focusSummaryProvider.overrideWithValue(summariseFocus(const [], DateTime.now())),
      ],
      child: const MaterialApp(home: Scaffold(body: FocusCard())),
    ));
    expect(FocusCard.saveRunningOnQuit, isNull);

    await tester.tap(find.byType(FilledButton));
    await tester.pump();
    expect(find.text('Bitir'), findsOneWidget);
    expect(FocusCard.saveRunningOnQuit, isNotNull);

    await FocusCard.saveRunningOnQuit!();
    await tester.pump();
    expect(find.text('Bitir'), findsNothing);
    expect(FocusCard.saveRunningOnQuit, isNull);
  });
}
