import 'package:aktenak_habit_tracker/core/enums.dart';
import 'package:aktenak_habit_tracker/core/tasks.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

void main() {
  final today = DateTime(2026, 8, 12);

  group('bucketFor', () {
    test('classifies each distance from today', () {
      expect(bucketFor(testTask(dueDay: DateTime(2026, 8, 11)), today),
          DueBucket.overdue);
      expect(bucketFor(testTask(dueDay: today), today), DueBucket.today);
      expect(bucketFor(testTask(dueDay: DateTime(2026, 8, 13)), today),
          DueBucket.tomorrow);
      expect(bucketFor(testTask(dueDay: DateTime(2026, 8, 18)), today),
          DueBucket.thisWeek);
      expect(bucketFor(testTask(dueDay: DateTime(2026, 9, 1)), today),
          DueBucket.later);
      expect(bucketFor(testTask(), today), DueBucket.someday);
    });

    test('the 7th day out is still this week, the 8th is later', () {
      expect(bucketFor(testTask(dueDay: DateTime(2026, 8, 19)), today),
          DueBucket.thisWeek);
      expect(bucketFor(testTask(dueDay: DateTime(2026, 8, 20)), today),
          DueBucket.later);
    });
  });

  group('sortTasks', () {
    test('done sinks, doing floats', () {
      final sorted = sortTasks([
        testTask(id: 1, status: TaskStatus.done, dueDay: today),
        testTask(id: 2, status: TaskStatus.todo, dueDay: today),
        testTask(id: 3, status: TaskStatus.doing),
      ], today);
      expect(sorted.map((t) => t.id), [3, 2, 1]);
    });

    test('overdue comes before today', () {
      final sorted = sortTasks([
        testTask(id: 1, dueDay: today),
        testTask(id: 2, dueDay: DateTime(2026, 8, 9)),
      ], today);
      expect(sorted.first.id, 2);
    });

    test('within a bucket, higher priority wins', () {
      final sorted = sortTasks([
        testTask(id: 1, dueDay: today, priority: TaskPriority.low),
        testTask(id: 2, dueDay: today, priority: TaskPriority.high),
        testTask(id: 3, dueDay: today, priority: TaskPriority.normal),
      ], today);
      expect(sorted.map((t) => t.id), [2, 3, 1]);
    });

    test('ties break by age, oldest first', () {
      final sorted = sortTasks([
        testTask(id: 1, dueDay: today, createdAt: DateTime(2026, 8, 5)),
        testTask(id: 2, dueDay: today, createdAt: DateTime(2026, 8, 1)),
      ], today);
      expect(sorted.first.id, 2);
    });
  });

  group('thisWeek', () {
    test('keeps overdue through this-week, drops later and undated', () {
      final result = thisWeek([
        testTask(id: 1, dueDay: DateTime(2026, 8, 10)), // overdue
        testTask(id: 2, dueDay: today),
        testTask(id: 3, dueDay: DateTime(2026, 8, 17)),
        testTask(id: 4, dueDay: DateTime(2026, 9, 30)), // later
        testTask(id: 5), // undated
      ], today);
      expect(result.map((t) => t.id), [1, 2, 3]);
    });

    test('excludes completed work', () {
      final result = thisWeek([
        testTask(id: 1, dueDay: today, status: TaskStatus.done),
        testTask(id: 2, dueDay: today),
      ], today);
      expect(result.map((t) => t.id), [2]);
    });
  });

  group('summarise', () {
    test('counts open, doing, overdue and due-today', () {
      final s = summarise([
        testTask(id: 1, dueDay: DateTime(2026, 8, 10)), // overdue
        testTask(id: 2, dueDay: today, status: TaskStatus.doing),
        testTask(id: 3, dueDay: DateTime(2026, 8, 20)),
        testTask(id: 4, status: TaskStatus.done),
      ], today);
      expect(s.open, 3);
      expect(s.doing, 1);
      expect(s.overdue, 1);
      expect(s.dueToday, 1);
    });

    test('doneToday follows the tracking day, not the calendar day', () {
      // Completed at 01:00 on 8/13 — with a 04:00 day start that is still 8/12.
      final s = summarise(
        [
          testTask(
            id: 1,
            status: TaskStatus.done,
            completedAt: DateTime(2026, 8, 13, 1, 0),
          ),
        ],
        today,
      );
      expect(s.doneToday, 1);
    });

    test('a task finished yesterday does not count as done today', () {
      final s = summarise(
        [
          testTask(
            id: 1,
            status: TaskStatus.done,
            completedAt: DateTime(2026, 8, 11, 15, 0),
          ),
        ],
        today,
      );
      expect(s.doneToday, 0);
    });
  });
}
