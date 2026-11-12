import 'package:aktenak_habit_tracker/shared/windows_bildirim.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('hatırlatıcı etiketi nativeapi sınırına uyar (1-16, [A-Za-z0-9_-])', () {
    final etiket = hatirlaticiEtiketi('2026-11-12');
    expect(etiket.length, inInclusiveRange(1, 16));
    expect(RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(etiket), isTrue);
  });

  test('toast betiği XML ve PowerShell tırnaklarını kaçırır', () {
    final betik = toastBetigi("A'b", '<3 & "x"');
    expect(betik, contains(r'HKCU:\Software\Classes\AppUserModelId\com.aktenak.habit_tracker'));
    expect(betik, isNot(contains('@')));
    expect(betik, contains("A''b"));
    expect(betik, contains('&lt;3 &amp; &quot;x&quot;'));
  });
}
