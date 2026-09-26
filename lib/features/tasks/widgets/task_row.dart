import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/date_utils.dart';
import '../../../core/enums.dart';
import '../../../core/tasks.dart';
import '../../../data/database/database.dart';
import '../../../data/providers.dart';
import '../../../shared/theme.dart';

/// One task line: checkbox, title, priority mark, due label.
/// Used by both the dashboard block and the full task screen.
class TaskRow extends ConsumerWidget {
  final Task task;
  final bool dense;
  final VoidCallback? onEdit;

  const TaskRow({
    super.key,
    required this.task,
    this.dense = false,
    this.onEdit,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = AppColors.of(context);
    final day = ref.watch(todayProvider);
    final status = TaskStatus.fromStorage(task.status);
    final priority = TaskPriority.fromValue(task.priority);
    final bucket = bucketFor(task, day);
    final isDone = status == TaskStatus.done;

    final dueColor = switch (bucket) {
      DueBucket.overdue => colors.missed,
      DueBucket.today => colors.done,
      _ => colors.textDim,
    };

    return Semantics(
      button: true,
      checked: isDone,
      label: task.title,
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () => ref.read(taskRepositoryProvider).toggleDone(task),
          onLongPress: onEdit,
          child: Padding(
            padding: EdgeInsets.symmetric(
                horizontal: 6, vertical: dense ? 5 : 8),
            child: Row(
              children: [
                _Checkbox(done: isDone, colors: colors),
                const SizedBox(width: 10),
                if (priority == TaskPriority.high && !isDone) ...[
                  Container(
                    width: 5,
                    height: 5,
                    decoration: BoxDecoration(
                      color: colors.missed,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 6),
                ],
                Expanded(
                  child: Text(
                    task.title,
                    maxLines: dense ? 1 : 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: dense ? 12.5 : 13.5,
                      fontWeight:
                          status == TaskStatus.doing ? FontWeight.w700 : null,
                      color: isDone ? colors.textDim : colors.text,
                      decoration: isDone ? TextDecoration.lineThrough : null,
                      decorationColor: colors.textDim,
                    ),
                  ),
                ),
                if (status == TaskStatus.doing) ...[
                  const SizedBox(width: 6),
                  Icon(Icons.bolt, size: 14, color: colors.gold),
                ],
                if (task.dueDay != null && !isDone) ...[
                  const SizedBox(width: 8),
                  Text(
                    _dueLabel(bucket, task.dueDay!, day),
                    style: kTabularNums.copyWith(
                        fontSize: 11, color: dueColor),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  static String _dueLabel(DueBucket bucket, String dueDay, DateTime today) {
    switch (bucket) {
      case DueBucket.today:
        return 'bugün';
      case DueBucket.tomorrow:
        return 'yarın';
      case DueBucket.overdue:
        final days = today.difference(parseYmd(dueDay)).inDays;
        return '$days gün geçti';
      default:
        final d = parseYmd(dueDay);
        return '${d.day}.${d.month}';
    }
  }
}

class _Checkbox extends StatelessWidget {
  final bool done;
  final AppColors colors;
  const _Checkbox({required this.done, required this.colors});

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      width: 18,
      height: 18,
      decoration: BoxDecoration(
        color: done ? colors.done : Colors.transparent,
        border: Border.all(color: done ? colors.done : colors.border, width: 1.6),
        borderRadius: BorderRadius.circular(5),
      ),
      child: done
          ? const Icon(Icons.check, size: 13, color: Colors.white)
          : null,
    );
  }
}
