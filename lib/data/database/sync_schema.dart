/// SQL for the v5 sync schema (uid, updatedAt, delete log), as plain strings.
///
/// Kept apart from `database.dart` so the trigger text is one reviewable unit:
/// fresh installs and upgrades both run [syncSchemaStatements], which is what
/// makes a new database and an upgraded one identical (migration_test checks).
/// Pure Dart, no Flutter imports.
library;

import '../../core/constants.dart';

// Trigger bodies use upserts, never `INSERT OR REPLACE`: SQLite lets the outer
// statement's conflict mode override a trigger's, and an outer upsert (which
// the repositories use) would turn the REPLACE into a constraint error.

/// SQLite expression for "now" in unix seconds.
const String _now = "CAST(strftime('%s', 'now') AS INTEGER)";

/// SQLite expression for a random UUID v4 (lowercase, hyphenated).
const String sqlUuidV4 = "lower(hex(randomblob(4)) || '-' || hex(randomblob(2)) "
    "|| '-4' || substr(hex(randomblob(2)), 2) "
    "|| '-' || substr('89ab', 1 + (random() & 3), 1) "
    "|| substr(hex(randomblob(2)), 2) || '-' || hex(randomblob(6)))";

/// Tables that get a `uid` column (and the tombstone kind used for them).
const Map<String, String> uidTables = {
  'habits': 'habit',
  'tasks': 'task',
  'focus_sessions': 'session',
};

/// Value `updated_at` takes when the column is added to existing rows.
const Map<String, String> updatedAtBackfill = {
  'habits': 'MAX(1, created_at, COALESCE(archived_at, 0))',
  'habit_entries': 'MAX(1, created_at)',
  'mood_entries': 'MAX(1, created_at)',
  'tasks': 'MAX(1, created_at, COALESCE(completed_at, 0))',
  'focus_sessions': 'MAX(1, COALESCE(ended_at, started_at))',
};

/// Per table: tombstone kind and the SQL that yields a row's tombstone key,
/// written once for `OLD` and once for `NEW`. Entries are keyed by their
/// habit's uid; if the habit is already gone (cascade delete) the key is NULL
/// and no tombstone is written - the habit's own tombstone covers its cells.
({String kind, String Function(String row) key}) _identity(String table) {
  switch (table) {
    case 'habit_entries':
      return (
        kind: 'entry',
        key: (r) => "(SELECT uid FROM habits WHERE id = $r.habit_id) "
            "|| '|' || $r.date",
      );
    case 'mood_entries':
      return (kind: 'mood', key: (r) => '$r.date');
    default:
      return (kind: uidTables[table]!, key: (r) => '$r.uid');
  }
}

/// Statements that create the three sync-only pieces: unique uid indexes are
/// created by drift / the migration, so this returns only the triggers.
///
/// All use `IF NOT EXISTS`, so running them twice (half-applied upgrade) is
/// harmless.
List<String> syncSchemaStatements() {
  final out = <String>[];
  const tables = [
    'habits',
    'habit_entries',
    'mood_entries',
    'tasks',
    'focus_sessions',
  ];
  for (final t in tables) {
    final id = _identity(t);
    final hasUid = uidTables.containsKey(t);

    if (hasUid) {
      out.add('CREATE TRIGGER IF NOT EXISTS ${t}_uid_ai AFTER INSERT ON $t '
          'WHEN NEW.uid IS NULL BEGIN '
          'UPDATE $t SET uid = $sqlUuidV4 WHERE id = NEW.id; END');
    }
    // 0 = "caller did not stamp it" (sync import and v5 backups pass a value).
    out.add('CREATE TRIGGER IF NOT EXISTS ${t}_stamp_ai AFTER INSERT ON $t '
        'WHEN NEW.updated_at = 0 BEGIN '
        'UPDATE $t SET updated_at = $_now WHERE id = NEW.id; END');
    // Re-adding a record clears its tombstone.
    out.add('CREATE TRIGGER IF NOT EXISTS ${t}_tomb_ai AFTER INSERT ON $t '
        '${hasUid ? 'WHEN NEW.uid IS NOT NULL ' : ''}BEGIN '
        "DELETE FROM silinenler WHERE kind = '${id.kind}' "
        'AND anahtar = ${id.key('NEW')}; END');
    // A write that did not touch updated_at (or uid, for adoption) is a user
    // edit: stamp it. Sync import sets updated_at explicitly, so it is skipped.
    out.add('CREATE TRIGGER IF NOT EXISTS ${t}_stamp_au AFTER UPDATE ON $t '
        'WHEN NEW.updated_at IS OLD.updated_at'
        '${hasUid ? ' AND NEW.uid IS OLD.uid' : ''} BEGIN '
        'UPDATE $t SET updated_at = $_now WHERE id = NEW.id; END');
    out.add('CREATE TRIGGER IF NOT EXISTS ${t}_tomb_ad AFTER DELETE ON $t '
        'BEGIN INSERT INTO silinenler (kind, anahtar, deleted_at) '
        "SELECT '${id.kind}', ${id.key('OLD')}, $_now "
        'WHERE ${id.key('OLD')} IS NOT NULL '
        'ON CONFLICT (kind, anahtar) DO UPDATE SET deleted_at = excluded.deleted_at; END');
  }

  // The one synced setting keeps its own stamp in a sibling settings row.
  const k = AppConstants.dayStartHourKey;
  const kStamp = AppConstants.dayStartHourStampKey;
  for (final (name, event) in const [('ai', 'INSERT'), ('au', 'UPDATE')]) {
    out.add('CREATE TRIGGER IF NOT EXISTS settings_daystart_$name '
        "AFTER $event ON settings WHEN NEW.key = '$k' BEGIN "
        'INSERT INTO settings (key, value) '
        "VALUES ('$kStamp', CAST($_now AS TEXT)) "
        'ON CONFLICT (key) DO UPDATE SET value = excluded.value; END');
  }
  return out;
}
