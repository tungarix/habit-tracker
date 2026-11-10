/// `.habitsync` file format: constants, errors and the import report.
///
/// Pure Dart (no Flutter, no Riverpod): the same logic is copied to the mobile
/// app, and `test/sync_purity_test.dart` keeps it that way. The single source
/// of truth for the rules is docs/senkron.md; the limits below must read the
/// same there (a test compares them).
library;

/// `format` value of every sync file.
const String syncFormat = 'habit-sync';

/// File format version this code writes and the highest it reads.
const int syncVersion = 1;

/// File extension without the dot.
const String syncExtension = 'habitsync';

// -- Limits (docs/senkron.md "Sınırlar"; both apps apply all of them) ---------

/// Largest file accepted, in bytes (checked before decoding).
const int syncMaxFileBytes = 16 * 1024 * 1024;

/// Most records in one file: habits + entries + moods + tasks + sessions +
/// deleted. About ten years of 60 habits fit with room to spare.
const int syncMaxRecords = 250000;

/// Most habits and most tasks in one file. Matching unmatched file rows against
/// local rows is quadratic, so a per-kind cap keeps a hostile file cheap.
const int syncMaxHabits = 10000;
const int syncMaxTasks = 10000;

/// `updated_at` / `deleted_at` may be at most this far ahead of the importing
/// device's clock (one day of clock skew). A later stamp would win every
/// last-writer-wins comparison from then on, so the whole file is rejected.
const int syncMaxFutureSecs = 86400;

/// Deepest JSON nesting accepted (a real file nests 3 deep).
const int syncMaxJsonDepth = 8;

/// Longest free text (description, note), in UTF-16 code units.
const int syncMaxTextLength = 10000;

/// Longest habit name / task title, matching the table constraints.
const int syncMaxHabitName = 100;
const int syncMaxTaskTitle = 200;

/// Tombstone kinds, in the order the file lists them.
const List<String> syncKinds = ['habit', 'entry', 'mood', 'task', 'session'];

/// The file was rejected; nothing was changed. [message] is shown to the user.
class SyncException implements Exception {
  final String message;
  const SyncException(this.message);

  @override
  String toString() => message;
}

/// The file comes from a newer version of the format.
class SyncVersionException extends SyncException {
  const SyncVersionException(int found)
      : super('Bu dosya daha yeni bir senkron sürümünden ($found). '
            'Uygulamayı güncelle.');
}

class SyncCounts {
  int added = 0;
  int updated = 0;
  int deleted = 0;
  int skipped = 0;

  int get changed => added + updated + deleted;
}

/// What an import did, per record kind.
class SyncReport {
  final habit = SyncCounts();
  final entry = SyncCounts();
  final mood = SyncCounts();
  final task = SyncCounts();
  final session = SyncCounts();
  final setting = SyncCounts();

  /// Local rows that took over the file's uid (first-match rule). Not a data
  /// change from the user's point of view, so it stays out of [changed].
  int adopted = 0;

  List<SyncCounts> get _all => [habit, entry, mood, task, session, setting];

  int get added => _all.fold(0, (n, c) => n + c.added);
  int get updated => _all.fold(0, (n, c) => n + c.updated);
  int get deleted => _all.fold(0, (n, c) => n + c.deleted);
  int get skipped => _all.fold(0, (n, c) => n + c.skipped);
  bool get changed => added + updated + deleted > 0;

  /// One line for the UI.
  String summary() {
    if (!changed && skipped == 0) return 'Değişiklik yok, her şey zaten güncel.';
    return 'Eklenen $added, güncellenen $updated, silinen $deleted'
        '${skipped > 0 ? ', atlanan $skipped' : ''}.';
  }
}

/// Unix seconds -> `YYYY-MM-DDTHH:MM:SSZ` (fixed width, UTC, no fraction).
String syncTime(int secs) {
  final iso = DateTime.fromMillisecondsSinceEpoch(secs * 1000, isUtc: true)
      .toIso8601String();
  return '${iso.substring(0, 19)}Z';
}
