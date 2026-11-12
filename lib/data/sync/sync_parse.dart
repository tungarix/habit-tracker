import 'dart:convert';
import 'dart:typed_data';

import 'sync_format.dart';

/// Reading and checking a `.habitsync` file. Everything here happens before
/// the database is touched, so a bad file changes nothing (docs/senkron.md §4).

class SHabit {
  SHabit(this.uid, this.name, this.description, this.colorValue,
      this.iconCodePoint, this.category, this.kind, this.target,
      this.createdAt, this.archivedAt, this.sortOrder, this.scheduledWeekdays,
      this.updatedAt);
  final String uid, name, category, kind, scheduledWeekdays;
  final String? description;
  final int colorValue, iconCodePoint, target, sortOrder;
  final int createdAt, updatedAt;
  final int? archivedAt;
}

class SEntry {
  SEntry(this.habitUid, this.date, this.status, this.value, this.createdAt,
      this.updatedAt);
  final String habitUid, date, status;
  final int value, createdAt, updatedAt;
  String get key => '$habitUid|$date';
}

class SMood {
  SMood(this.date, this.mood, this.note, this.createdAt, this.updatedAt);
  final String date;
  final String? note;
  final int mood, createdAt, updatedAt;
}

class STask {
  STask(this.uid, this.title, this.status, this.priority, this.dueDay,
      this.createdAt, this.completedAt, this.updatedAt);
  final String uid, title, status;
  final String? dueDay;
  final int priority, createdAt, updatedAt;
  final int? completedAt;
}

class SSession {
  SSession(this.uid, this.kind, this.startedAt, this.endedAt, this.durationS,
      this.day, this.taskUid, this.updatedAt);
  final String uid, kind, day;
  final String? taskUid;
  final int startedAt, updatedAt;
  final int? endedAt, durationS;
}

class STomb {
  STomb(this.kind, this.key, this.deletedAt);
  final String kind, key;
  final int deletedAt;
}

class SSetting {
  SSetting(this.value, this.updatedAt);
  final int value, updatedAt;
}

/// A validated file.
class SyncFile {
  SSetting? dayStartHour;
  final habits = <SHabit>[];
  final entries = <SEntry>[];
  final moods = <SMood>[];
  final tasks = <STask>[];
  final sessions = <SSession>[];
  final deleted = <STomb>[];
}

final _timeRe = RegExp(r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$');
final _dayRe = RegExp(r'^\d{4}-\d{2}-\d{2}$');
final _uidRe = RegExp(r'^[A-Za-z0-9._:@-]{1,64}$');
final _weekdaysRe = RegExp(r'^([1-7](,[1-7])*)?$');

const _entryStatuses = ['done', 'missed', 'skipped'];
const _taskStatuses = ['todo', 'doing', 'done'];

SyncException _bad(String detail) =>
    SyncException('Senkron dosyası geçersiz: $detail');

/// Nesting depth of the JSON text without decoding it (so a hostile file
/// cannot blow the stack in the decoder). Strings and escapes are skipped.
int jsonDepth(String text) {
  var depth = 0, max = 0;
  var inString = false, escape = false;
  for (var i = 0; i < text.length; i++) {
    final c = text.codeUnitAt(i);
    if (inString) {
      if (escape) {
        escape = false;
      } else if (c == 0x5C) {
        escape = true;
      } else if (c == 0x22) {
        inString = false;
      }
      continue;
    }
    if (c == 0x22) {
      inString = true;
    } else if (c == 0x5B || c == 0x7B) {
      depth++;
      if (depth > max) max = depth;
      if (max > syncMaxJsonDepth) return max;
    } else if (c == 0x5D || c == 0x7D) {
      depth--;
    }
  }
  return max;
}

/// Decodes and validates [bytes]. Throws [SyncException] (or its subclass
/// [SyncVersionException]) for anything wrong; returns nothing half-done.
SyncFile parseSync(Uint8List bytes, {DateTime? now}) {
  final latest = (now ?? DateTime.now()).millisecondsSinceEpoch ~/ 1000 + syncMaxFutureSecs;
  if (bytes.length > syncMaxFileBytes) {
    throw _bad('dosya çok büyük (en çok ${syncMaxFileBytes ~/ (1024 * 1024)} MB)');
  }
  final String text;
  try {
    text = utf8.decode(bytes);
  } on FormatException {
    throw _bad('UTF-8 metin değil');
  }
  final body = text.startsWith('﻿') ? text.substring(1) : text;
  if (jsonDepth(body) > syncMaxJsonDepth) {
    throw _bad('JSON en çok $syncMaxJsonDepth düzey iç içe olabilir');
  }
  final Object? decoded;
  try {
    decoded = jsonDecode(body);
  } on FormatException catch (e) {
    throw _bad('JSON okunamadı (${e.message})');
  }
  if (decoded is! Map<String, dynamic>) throw _bad('bir JSON nesnesi bekleniyor');
  final Map<String, dynamic> root = decoded;
  if (root['format'] != syncFormat) {
    throw const SyncException('Bu bir Habit Tracker senkron dosyası değil.');
  }
  final version = root['version'];
  if (version is! int || version < 1) throw _bad('"version" pozitif tamsayı olmalı');
  if (version > syncVersion) throw SyncVersionException(version);

  List<Map<String, dynamic>> list(String key) {
    final v = root[key];
    if (v == null) return const [];
    if (v is! List) throw _bad('"$key" bir dizi olmalı');
    for (final item in v) {
      if (item is! Map<String, dynamic>) throw _bad('"$key" içinde nesne olmayan kayıt');
    }
    return v.cast<Map<String, dynamic>>();
  }

  final habits = list('habits');
  final entries = list('entries');
  final moods = list('moods');
  final tasks = list('tasks');
  final sessions = list('sessions');
  final deleted = list('deleted');
  final total = habits.length +
      entries.length +
      moods.length +
      tasks.length +
      sessions.length +
      deleted.length;
  if (habits.length > syncMaxHabits) {
    throw _bad('en çok $syncMaxHabits alışkanlık olabilir (var: ${habits.length})');
  }
  if (tasks.length > syncMaxTasks) {
    throw _bad('en çok $syncMaxTasks görev olabilir (var: ${tasks.length})');
  }
  if (total > syncMaxRecords) {
    throw _bad('en çok $syncMaxRecords kayıt olabilir (var: $total)');
  }

  final file = SyncFile();

  final settings = root['settings'];
  if (settings != null) {
    if (settings is! Map<String, dynamic>) throw _bad('"settings" bir nesne olmalı');
    final d = settings['day_start_hour'];
    if (d != null) {
      if (d is! Map<String, dynamic>) throw _bad('day_start_hour bir nesne olmalı');
      file.dayStartHour = SSetting(
        _int(d, 'value', min: 0, max: 12, where: 'day_start_hour'),
        _time(d, 'updated_at', where: 'day_start_hour', latest: latest)!,
      );
    }
  }

  final seen = <String>{};
  void unique(String what, String key) {
    if (!seen.add('$what|$key')) throw _bad('$what: aynı anahtar iki kez ($key)');
  }

  for (final m in habits) {
    final uid = _uid(m, 'uid', 'habit');
    unique('habits', uid);
    final kind = _str(m, 'kind', where: 'habit $uid', oneOf: const ['bool', 'count']);
    final weekdays = _str(m, 'scheduled_weekdays', where: 'habit $uid', max: 20);
    if (!_weekdaysRe.hasMatch(weekdays)) {
      throw _bad('habit $uid: scheduled_weekdays "1,2,..7" biçiminde olmalı');
    }
    file.habits.add(SHabit(
      uid,
      _str(m, 'name', where: 'habit $uid', min: 1, max: syncMaxHabitName),
      _strOrNull(m, 'description', where: 'habit $uid', max: syncMaxTextLength),
      _int(m, 'color_value', min: 0, max: 0xFFFFFFFF, where: 'habit $uid'),
      _int(m, 'icon_code_point', min: 0, max: 0x10FFFF, where: 'habit $uid'),
      _str(m, 'category', where: 'habit $uid', max: 40),
      kind,
      _int(m, 'target', min: 1, max: syncMaxCount, where: 'habit $uid'),
      _time(m, 'created_at', where: 'habit $uid')!,
      _time(m, 'archived_at', where: 'habit $uid', nullable: true),
      _int(m, 'sort_order', min: -1000000, max: 1000000, where: 'habit $uid'),
      weekdays,
      _time(m, 'updated_at', where: 'habit $uid', latest: latest)!,
    ));
  }

  for (final m in entries) {
    final habitUid = _uid(m, 'habit_uid', 'entry');
    final date = _day(m, 'date', where: 'entry');
    unique('entries', '$habitUid|$date');
    file.entries.add(SEntry(
      habitUid,
      date,
      _str(m, 'status', where: 'entry $habitUid|$date', oneOf: _entryStatuses),
      _int(m, 'value', min: 0, max: syncMaxCount, where: 'entry $habitUid|$date'),
      _time(m, 'created_at', where: 'entry $habitUid|$date')!,
      _time(m, 'updated_at', where: 'entry $habitUid|$date', latest: latest)!,
    ));
  }

  for (final m in moods) {
    final date = _day(m, 'date', where: 'mood');
    unique('moods', date);
    file.moods.add(SMood(
      date,
      _int(m, 'mood', min: 1, max: 5, where: 'mood $date'),
      _strOrNull(m, 'note', where: 'mood $date', max: syncMaxTextLength),
      _time(m, 'created_at', where: 'mood $date')!,
      _time(m, 'updated_at', where: 'mood $date', latest: latest)!,
    ));
  }

  for (final m in tasks) {
    final uid = _uid(m, 'uid', 'task');
    unique('tasks', uid);
    file.tasks.add(STask(
      uid,
      _str(m, 'title', where: 'task $uid', min: 1, max: syncMaxTaskTitle),
      _str(m, 'status', where: 'task $uid', oneOf: _taskStatuses),
      _int(m, 'priority', min: 0, max: 2, where: 'task $uid'),
      m['due_day'] == null ? null : _day(m, 'due_day', where: 'task $uid'),
      _time(m, 'created_at', where: 'task $uid')!,
      _time(m, 'completed_at', where: 'task $uid', nullable: true),
      _time(m, 'updated_at', where: 'task $uid', latest: latest)!,
    ));
  }

  for (final m in sessions) {
    final uid = _uid(m, 'uid', 'session');
    unique('sessions', uid);
    final taskUid = m['task_uid'];
    if (taskUid != null && (taskUid is! String || !_uidRe.hasMatch(taskUid))) {
      throw _bad('session $uid: task_uid geçersiz');
    }
    file.sessions.add(SSession(
      uid,
      _str(m, 'kind', where: 'session $uid', oneOf: const ['focus', 'break']),
      _time(m, 'started_at', where: 'session $uid')!,
      _time(m, 'ended_at', where: 'session $uid', nullable: true),
      m['duration_s'] == null
          ? null
          : _int(m, 'duration_s', min: 0, max: 7 * 86400, where: 'session $uid'),
      _day(m, 'day', where: 'session $uid'),
      taskUid as String?,
      _time(m, 'updated_at', where: 'session $uid', latest: latest)!,
    ));
  }

  for (final m in deleted) {
    final kind = _str(m, 'kind', where: 'deleted', oneOf: syncKinds);
    final key = _str(m, 'key', where: 'deleted', min: 1, max: 200);
    final okKey = switch (kind) {
      'entry' => RegExp(r'^[A-Za-z0-9._:@-]{1,64}\|\d{4}-\d{2}-\d{2}$').hasMatch(key),
      'mood' => _dayRe.hasMatch(key),
      _ => _uidRe.hasMatch(key),
    };
    if (!okKey) throw _bad('deleted: "$kind" için anahtar geçersiz ($key)');
    unique('deleted', '$kind|$key');
    file.deleted.add(STomb(kind, key, _time(m, 'deleted_at', where: 'deleted $key', latest: latest)!));
  }
  return file;
}

// -- field helpers ------------------------------------------------------------

String _uid(Map<String, dynamic> m, String key, String where) {
  final v = m[key];
  if (v is! String || !_uidRe.hasMatch(v)) throw _bad('$where: "$key" geçersiz');
  return v;
}

String _str(
  Map<String, dynamic> m,
  String key, {
  required String where,
  int min = 0,
  int max = syncMaxTextLength,
  List<String>? oneOf,
}) {
  final v = m[key];
  if (v is! String) throw _bad('$where: "$key" metin olmalı');
  if (v.length < min || v.length > max) {
    throw _bad('$where: "$key" uzunluğu $min..$max olmalı');
  }
  if (oneOf != null && !oneOf.contains(v)) {
    throw _bad('$where: "$key" şunlardan biri olmalı: ${oneOf.join(', ')}');
  }
  return v;
}

String? _strOrNull(Map<String, dynamic> m, String key,
    {required String where, required int max}) {
  if (m[key] == null) return null;
  return _str(m, key, where: where, max: max);
}

int _int(Map<String, dynamic> m, String key,
    {required int min, required int max, required String where}) {
  final v = m[key];
  if (v is! int) throw _bad('$where: "$key" tamsayı olmalı');
  if (v < min || v > max) throw _bad('$where: "$key" $min..$max olmalı');
  return v;
}

/// `YYYY-MM-DD` that is a real calendar day.
String _day(Map<String, dynamic> m, String key, {required String where}) {
  final v = m[key];
  if (v is! String || !_dayRe.hasMatch(v)) throw _bad('$where: "$key" YYYY-AA-GG olmalı');
  final d = DateTime.utc(int.parse(v.substring(0, 4)), int.parse(v.substring(5, 7)),
      int.parse(v.substring(8, 10)));
  final back = '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  if (back != v) throw _bad('$where: "$key" geçerli bir gün değil ($v)');
  return v;
}

/// Fixed-width UTC time -> unix seconds, at least 1 (0 means "unstamped").
int? _time(Map<String, dynamic> m, String key,
    {required String where, bool nullable = false, int? latest}) {
  final v = m[key];
  if (v == null && nullable) return null;
  if (v is! String || !_timeRe.hasMatch(v)) {
    throw _bad('$where: "$key" YYYY-AA-GGTSS:DD:SSZ olmalı');
  }
  final d = DateTime.tryParse(v);
  // Round trip catches days like Feb 31 that DateTime.parse silently rolls over.
  if (d == null || syncTime(d.millisecondsSinceEpoch ~/ 1000) != v) {
    throw _bad('$where: "$key" geçerli bir zaman değil ($v)');
  }
  final secs = d.millisecondsSinceEpoch ~/ 1000;
  if (d.year < 1970 || d.year > 9999) throw _bad('$where: "$key" aralık dışı ($v)');
  if (latest != null && secs > latest) {
    throw _bad('$where: "$key" gelecekte ($v); cihazın saatini denetle');
  }
  return secs < 1 ? 1 : secs;
}
