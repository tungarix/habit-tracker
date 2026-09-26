import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/enums.dart';
import '../../core/tasks.dart';
import '../../data/database/database.dart';
import '../../data/providers.dart';
import '../../shared/theme.dart';
import 'task_edit_dialog.dart';
import 'widgets/task_row.dart';

/// Full task list, grouped by urgency. Deliberately one flat list per group —
/// no boards, no projects; those are in the fridge.
///
/// [embedded] drops the Scaffold so the same screen can live inside the app
/// shell as a tab, or be pushed as its own route from the dashboard.
class TasksScreen extends ConsumerStatefulWidget {
  final bool embedded;
  const TasksScreen({super.key, this.embedded = false});

  @override
  ConsumerState<TasksScreen> createState() => _TasksScreenState();
}

class _TasksScreenState extends ConsumerState<TasksScreen> {
  bool _showDone = false;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final all = ref.watch(sortedTasksProvider);
    final day = ref.watch(todayProvider);
    final summary = ref.watch(taskSummaryProvider);

    final open = all
        .where((t) => TaskStatus.fromStorage(t.status) != TaskStatus.done)
        .toList();
    final done = all
        .where((t) => TaskStatus.fromStorage(t.status) == TaskStatus.done)
        .toList();

    final groups = <(String, List<Task>)>[
      ('Geciken', _inBucket(open, day, DueBucket.overdue)),
      ('Bugün', _inBucket(open, day, DueBucket.today)),
      ('Yarın', _inBucket(open, day, DueBucket.tomorrow)),
      ('Bu hafta', _inBucket(open, day, DueBucket.thisWeek)),
      ('Sonra', _inBucket(open, day, DueBucket.later)),
      ('Tarihsiz', _inBucket(open, day, DueBucket.someday)),
    ];

    final body = SafeArea(
      child: ListView(
        padding: EdgeInsets.fromLTRB(
            widget.embedded ? 4 : 16, 8, widget.embedded ? 4 : 16, 96),
        children: [
          if (widget.embedded)
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 4, 0, 4),
              child: Row(
                children: [
                  Text('Görevler',
                      style: Theme.of(context)
                          .textTheme
                          .headlineSmall
                          ?.copyWith(fontWeight: FontWeight.bold)),
                  const Spacer(),
                  if (done.isNotEmpty)
                    TextButton.icon(
                      onPressed: () => setState(() => _showDone = !_showDone),
                      icon: Icon(
                          _showDone ? Icons.visibility_off : Icons.visibility,
                          size: 18),
                      label: Text('Bitenler (${done.length})'),
                    ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    onPressed: () => TaskEditDialog.show(context),
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('Görev'),
                  ),
                ],
              ),
            ),
          ..._buildGroups(context, groups, done, colors, summary),
        ],
      ),
    );

    if (widget.embedded) return body;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Görevler'),
        actions: [
          if (done.isNotEmpty)
            TextButton.icon(
              onPressed: () => setState(() => _showDone = !_showDone),
              icon: Icon(_showDone ? Icons.visibility_off : Icons.visibility,
                  size: 18),
              label: Text('Bitenler (${done.length})'),
            ),
          const SizedBox(width: 8),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => TaskEditDialog.show(context),
        icon: const Icon(Icons.add),
        label: const Text('Görev'),
      ),
      body: body,
    );
  }

  List<Widget> _buildGroups(
    BuildContext context,
    List<(String, List<Task>)> groups,
    List<Task> done,
    AppColors colors,
    TaskSummary summary,
  ) {
    return [
            if (summary.open == 0 && done.isEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 48),
                child: Column(
                  children: [
                    Icon(Icons.checklist_rtl_outlined,
                        size: 56, color: colors.textDim),
                    const SizedBox(height: 14),
                    const Text('Henüz görev yok',
                        style: TextStyle(
                            fontSize: 17, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 6),
                    Text('İlk görevini ekle — sadece başlık yeter.',
                        style: TextStyle(color: colors.textDim)),
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      onPressed: () => TaskEditDialog.show(context),
                      icon: const Icon(Icons.add),
                      label: const Text('Görev ekle'),
                    ),
                  ],
                ),
              ),
            for (final (title, items) in groups)
              if (items.isNotEmpty) ...[
                _GroupHeader(title: title, count: items.length),
                for (final t in items)
                  TaskRow(
                    task: t,
                    onEdit: () => TaskEditDialog.show(context, existing: t),
                  ),
                const SizedBox(height: 10),
              ],
            if (_showDone && done.isNotEmpty) ...[
              Row(
                children: [
                  Expanded(
                    child: _GroupHeader(title: 'Bitenler', count: done.length),
                  ),
                  TextButton(
                    onPressed: () => _confirmClear(context),
                    child: Text('Temizle',
                        style: TextStyle(color: colors.missed, fontSize: 12)),
                  ),
                ],
              ),
              for (final t in done)
                TaskRow(
                  task: t,
                  onEdit: () => TaskEditDialog.show(context, existing: t),
                ),
            ],
    ];
  }

  static List<Task> _inBucket(List<Task> tasks, DateTime day, DueBucket bucket) =>
      tasks.where((t) => bucketFor(t, day) == bucket).toList();

  Future<void> _confirmClear(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Biten görevler silinsin mi?'),
        content: const Text(
            'Tamamlanmış tüm görevler kalıcı olarak silinir. Bu geri alınamaz.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('İptal')),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.error),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Sil'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await ref.read(taskRepositoryProvider).clearDone();
    }
  }
}

class _GroupHeader extends StatelessWidget {
  final String title;
  final int count;
  const _GroupHeader({required this.title, required this.count});

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(6, 12, 6, 4),
      child: Row(
        children: [
          Text(title,
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: colors.textDim)),
          const SizedBox(width: 6),
          Text('$count',
              style: kTabularNums.copyWith(
                  fontSize: 11, color: colors.textDim.withValues(alpha: 0.7))),
        ],
      ),
    );
  }
}
