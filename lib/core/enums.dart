/// Pure-Dart enums shared by the database schema, the streak logic and the UI.
/// No Flutter imports here so `core/streak.dart` and the tests stay pure.
library;

/// Per-day state of a habit. Stored as the enum index (drift `intEnum`),
/// so the order below is part of the on-disk format — never reorder.
enum EntryStatus {
  done, // ✓ yapıldı
  missed, // ✗ yapılmadı
  skipped, // – atlandı (seriyi bozmaz)
}

/// Tap cycle used by the Today screen and the monthly grid:
/// boş → ✓ → ✗ → – → boş.
EntryStatus? nextStatus(EntryStatus? current) {
  switch (current) {
    case null:
      return EntryStatus.done;
    case EntryStatus.done:
      return EntryStatus.missed;
    case EntryStatus.missed:
      return EntryStatus.skipped;
    case EntryStatus.skipped:
      return null;
  }
}

/// What a habit measures. Stored as the `name` string.
///
/// `bool` habits are a plain tick. `count` habits record an amount against a
/// daily [Habits.target] — "10 bin adım", "Derin çalışma 90 dk" and friends,
/// where the number used to be buried in the habit's name.
enum HabitKind {
  bool_('bool', 'Yap / yapma'),
  count('count', 'Sayılabilir');

  /// Stored value (`bool_` serialises as `bool`, which is a Dart keyword).
  final String storageName;
  final String label;
  const HabitKind(this.storageName, this.label);

  static HabitKind fromStorage(String? value) {
    for (final k in HabitKind.values) {
      if (k.storageName == value) return k;
    }
    return HabitKind.bool_;
  }
}

/// Habit category. Stored as the `name` string; empty string in the DB means
/// "no category" (legacy habits from schema v1).
enum HabitCategory {
  beden('Beden'),
  konusma('Konuşma'),
  zihin('Zihin');

  final String label;
  const HabitCategory(this.label);

  static HabitCategory? tryParse(String? value) {
    if (value == null || value.isEmpty) return null;
    for (final c in HabitCategory.values) {
      if (c.name == value) return c;
    }
    return null;
  }
}

/// Where a task sits. Stored as [storageName].
enum TaskStatus {
  todo('todo', 'Yapılacak'),
  doing('doing', 'Yapılıyor'),
  done('done', 'Bitti');

  final String storageName;
  final String label;
  const TaskStatus(this.storageName, this.label);

  static TaskStatus fromStorage(String? value) {
    for (final s in TaskStatus.values) {
      if (s.storageName == value) return s;
    }
    return TaskStatus.todo;
  }
}

/// Task priority. Stored as the int [value] so ordering is a plain sort.
enum TaskPriority {
  low(0, 'Düşük'),
  normal(1, 'Orta'),
  high(2, 'Yüksek');

  final int value;
  final String label;
  const TaskPriority(this.value, this.label);

  static TaskPriority fromValue(int? value) {
    for (final p in TaskPriority.values) {
      if (p.value == value) return p;
    }
    return TaskPriority.normal;
  }
}

/// Focus timer session type. Stored as [storageName].
enum SessionKind {
  focus('focus', 'Odak'),
  rest('break', 'Mola');

  final String storageName;
  final String label;
  const SessionKind(this.storageName, this.label);

  static SessionKind fromStorage(String? value) {
    for (final k in SessionKind.values) {
      if (k.storageName == value) return k;
    }
    return SessionKind.focus;
  }
}

/// Mood scale, 1..5. Stored as [value].
enum Mood {
  yorgun(1, 'Yorgun', '😴'),
  stresli(2, 'Stresli', '😣'),
  uzgun(3, 'Üzgün', '😞'),
  memnun(4, 'Memnun', '🙂'),
  mutlu(5, 'Mutlu', '😄');

  final int value;
  final String label;
  final String emoji;
  const Mood(this.value, this.label, this.emoji);

  static Mood? fromValue(int? value) {
    for (final m in Mood.values) {
      if (m.value == value) return m;
    }
    return null;
  }
}
