import 'package:drift/drift.dart';

import '../../core/enums.dart';
import '../database/database.dart';

/// Task mutations. Ordering and grouping live in `core/tasks.dart`.
class TaskRepository {
  final AppDatabase db;
  TaskRepository(this.db);

  Stream<List<Task>> watchAll() => db.watchAllTasks();

  Future<int> create({
    required String title,
    TaskPriority priority = TaskPriority.normal,
    String? dueDay,
  }) {
    return db.insertTask(
      TasksCompanion.insert(
        title: title,
        priority: Value(priority.value),
        dueDay: Value(dueDay),
      ),
    );
  }

  Future<void> setStatus(int id, TaskStatus status) =>
      db.setTaskStatus(id, status.storageName, DateTime.now());

  /// One tap cycles todo → doing → done → todo.
  Future<TaskStatus> cycleStatus(Task task) async {
    final next = switch (TaskStatus.fromStorage(task.status)) {
      TaskStatus.todo => TaskStatus.doing,
      TaskStatus.doing => TaskStatus.done,
      TaskStatus.done => TaskStatus.todo,
    };
    await setStatus(task.id, next);
    return next;
  }

  /// Checkbox behaviour: straight to done, or back to todo.
  Future<void> toggleDone(Task task) {
    final isDone = TaskStatus.fromStorage(task.status) == TaskStatus.done;
    return setStatus(task.id, isDone ? TaskStatus.todo : TaskStatus.done);
  }

  Future<void> update(Task task) => db.updateTask(task);
  Future<void> delete(int id) => db.deleteTask(id);
  Future<int> clearDone() => db.clearDoneTasks();
}
