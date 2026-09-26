import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The blueprint's load-bearing architectural rule:
///
/// > `core/` içinde tek bir GUI importu bile olmayacak.
///
/// `core/` holds the data model and the logic. Keeping Flutter out of it means
/// the whole logic layer can be lifted to another UI (or run in a plain Dart
/// process) without dragging a rendering toolkit along. This test is the rule's
/// enforcement — without it the rule quietly erodes on the first busy day.
void main() {
  test('core/ imports no GUI toolkit', () {
    final coreDir = Directory('lib/core');
    expect(coreDir.existsSync(), isTrue,
        reason: 'lib/core must exist — run this test from the project root.');

    // Anything that pulls in a rendering layer. `dart:ui` counts too: it is the
    // engine binding, not plain Dart.
    final forbidden = RegExp(
      r'''import\s+['"](package:flutter/|package:flutter_riverpod/|dart:ui)''',
    );

    final offenders = <String>[];
    for (final file in coreDir
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))) {
      for (final (i, line) in file.readAsLinesSync().indexed) {
        if (forbidden.hasMatch(line)) {
          offenders.add('${file.path}:${i + 1}: ${line.trim()}');
        }
      }
    }

    expect(
      offenders,
      isEmpty,
      reason: 'GUI imports leaked into core/:\n${offenders.join('\n')}\n'
          'Move presentation code to lib/shared/ instead.',
    );
  });

  test('core/ files are all reachable Dart sources', () {
    // Guards against the rule being "satisfied" by an empty or missing folder.
    final dartFiles = Directory('lib/core')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))
        .toList();
    expect(dartFiles.length, greaterThanOrEqualTo(4));
  });
}
