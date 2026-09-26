import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/providers.dart';
import '../../../shared/theme.dart';
import '../task_edit_dialog.dart';
import '../tasks_screen.dart';
import 'task_row.dart';

/// Dashboard block: what is actually due this week, plus a one-line adder.
/// Undated tasks stay out — they are not a commitment for this week.
class WeekTasksCard extends ConsumerWidget {
  const WeekTasksCard({super.key});

  static const _maxShown = 6;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = AppColors.of(context);
    final tasks = ref.watch(thisWeekTasksProvider);
    final summary = ref.watch(taskSummaryProvider);
    final shown = tasks.take(_maxShown).toList();

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(Icons.checklist_rtl_outlined,
                    size: 17, color: colors.textDim),
                const SizedBox(width: 8),
                Text('Bu hafta',
                    style: TextStyle(
                        fontWeight: FontWeight.w700, color: colors.text)),
                const Spacer(),
                if (summary.doneToday > 0)
                  Text('bugün ${summary.doneToday} bitti',
                      style: TextStyle(fontSize: 11, color: colors.textDim)),
                IconButton(
                  tooltip: 'Tüm görevler',
                  visualDensity: VisualDensity.compact,
                  iconSize: 18,
                  icon: Icon(Icons.open_in_full, color: colors.textDim),
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const TasksScreen()),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            if (shown.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  summary.open == 0
                      ? 'Bu hafta için görev yok.'
                      : '${summary.open} görev var ama hiçbirinin tarihi bu hafta değil.',
                  style: TextStyle(fontSize: 12, color: colors.textDim),
                ),
              )
            else
              for (final t in shown)
                TaskRow(
                  task: t,
                  dense: true,
                  onEdit: () => TaskEditDialog.show(context, existing: t),
                ),
            if (tasks.length > _maxShown)
              Padding(
                padding: const EdgeInsets.only(left: 6, top: 4),
                child: Text('+${tasks.length - _maxShown} daha',
                    style: TextStyle(fontSize: 11, color: colors.textDim)),
              ),
            const SizedBox(height: 6),
            const _QuickAdd(),
          ],
        ),
      ),
    );
  }
}

/// Single-line adder: type, press Enter, keep going. Anything more (priority,
/// due date) lives in the edit dialog.
class _QuickAdd extends ConsumerStatefulWidget {
  const _QuickAdd();

  @override
  ConsumerState<_QuickAdd> createState() => _QuickAddState();
}

class _QuickAddState extends ConsumerState<_QuickAdd> {
  final _controller = TextEditingController();
  final _focus = FocusNode();

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final title = _controller.text.trim();
    if (title.isEmpty) return;
    await ref.read(taskRepositoryProvider).create(
          title: title,
          dueDay: formatToday(ref),
        );
    _controller.clear();
    _focus.requestFocus(); // stay in the flow
  }

  String formatToday(WidgetRef ref) {
    final day = ref.read(todayProvider);
    return '${day.year.toString().padLeft(4, '0')}-'
        '${day.month.toString().padLeft(2, '0')}-'
        '${day.day.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return TextField(
      controller: _controller,
      focusNode: _focus,
      textInputAction: TextInputAction.done,
      onSubmitted: (_) => _submit(),
      style: const TextStyle(fontSize: 13),
      decoration: InputDecoration(
        isDense: true,
        hintText: 'Bugüne görev ekle…',
        hintStyle: TextStyle(fontSize: 12.5, color: colors.textDim),
        prefixIcon: Icon(Icons.add, size: 18, color: colors.textDim),
        prefixIconConstraints:
            const BoxConstraints(minWidth: 30, minHeight: 30),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(9),
          borderSide: BorderSide(color: colors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(9),
          borderSide: BorderSide(color: colors.border),
        ),
        contentPadding: const EdgeInsets.symmetric(vertical: 10),
      ),
    );
  }
}
