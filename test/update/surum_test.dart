import 'dart:io';

import 'package:aktenak_habit_tracker/surum.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('lib/surum.dart pubspec.yaml sürümüyle aynı', () {
    final m = RegExp(
      r'^version:\s*(\d+\.\d+\.\d+)\+',
      multiLine: true,
    ).firstMatch(File('pubspec.yaml').readAsStringSync());
    expect(m, isNotNull);
    expect(uygulamaSurumu, m![1]);
  });
}
