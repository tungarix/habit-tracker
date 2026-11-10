import 'dart:io';

import 'package:aktenak_habit_tracker/data/sync/sync_format.dart';
import 'package:flutter_test/flutter_test.dart';

/// The sync code is copied to the mobile app and its rules live in
/// docs/senkron.md. Two guards keep that honest.
void main() {
  test('lib/data/sync imports no Flutter, Riverpod or dart:ui', () {
    final files = Directory('lib/data/sync')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))
        .toList();
    expect(files.length, greaterThanOrEqualTo(4));
    final forbidden = RegExp(
      r'''import\s+['"](package:flutter/|package:flutter_riverpod/|dart:ui|dart:io)''',
    );
    final offenders = <String>[];
    for (final f in files) {
      for (final (i, line) in f.readAsLinesSync().indexed) {
        if (forbidden.hasMatch(line)) offenders.add('${f.path}:${i + 1}: ${line.trim()}');
      }
    }
    expect(offenders, isEmpty, reason: offenders.join('\n'));
  });

  test('the limits in docs/senkron.md equal the constants in code', () {
    final doc = File('docs/senkron.md').readAsStringSync();
    int fromDoc(String name) {
      final at = doc.indexOf('`$name`');
      final m = at < 0 ? null : RegExp(r'\|\s*(\d+)').firstMatch(doc.substring(at));
      expect(m, isNotNull, reason: '$name missing from docs/senkron.md');
      return int.parse(m!.group(1)!);
    }

    expect(fromDoc('syncMaxFileBytes'), syncMaxFileBytes);
    expect(fromDoc('syncMaxRecords'), syncMaxRecords);
    expect(fromDoc('syncMaxJsonDepth'), syncMaxJsonDepth);
    expect(fromDoc('syncMaxTextLength'), syncMaxTextLength);
    expect(fromDoc('syncMaxHabitName'), syncMaxHabitName);
    expect(fromDoc('syncMaxTaskTitle'), syncMaxTaskTitle);
    expect(fromDoc('syncMaxHabits'), syncMaxHabits);
    expect(fromDoc('syncMaxTasks'), syncMaxTasks);
    expect(fromDoc('syncMaxFutureSecs'), syncMaxFutureSecs);
  });
}
