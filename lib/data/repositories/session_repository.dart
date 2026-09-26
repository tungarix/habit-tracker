import '../../core/date_utils.dart';
import '../../core/enums.dart';
import '../database/database.dart';

/// Focus-session writes. A row is only created once a run finishes, so an
/// abandoned timer leaves nothing behind.
class SessionRepository {
  final AppDatabase db;
  SessionRepository(this.db);

  Stream<List<FocusSession>> watchAll() => db.watchAllSessions();

  /// Records a completed run. [day] is the tracking day it belongs to.
  Future<int> record({
    required SessionKind kind,
    required DateTime startedAt,
    required DateTime endedAt,
    required int durationS,
    required DateTime day,
    int? taskId,
  }) {
    return db.insertSession(
      kind: kind.storageName,
      startedAt: startedAt,
      endedAt: endedAt,
      durationS: durationS,
      day: formatYmd(day),
      taskId: taskId,
    );
  }

  Future<void> delete(int id) => db.deleteSession(id);
}
