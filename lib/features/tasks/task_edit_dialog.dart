import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/date_utils.dart';
import '../../core/enums.dart';
import '../../data/database/database.dart';
import '../../data/providers.dart';
import '../../shared/theme.dart';

/// Add / edit a task. Pass [existing] to edit.
class TaskEditDialog extends ConsumerStatefulWidget {
  final Task? existing;
  const TaskEditDialog({super.key, this.existing});

  static Future<void> show(BuildContext context, {Task? existing}) {
    return showDialog<void>(
      context: context,
      builder: (_) => TaskEditDialog(existing: existing),
    );
  }

  @override
  ConsumerState<TaskEditDialog> createState() => _TaskEditDialogState();
}

class _TaskEditDialogState extends ConsumerState<TaskEditDialog> {
  late final TextEditingController _title;
  late TaskPriority _priority;
  late TaskStatus _status;
  DateTime? _dueDay;

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final t = widget.existing;
    _title = TextEditingController(text: t?.title ?? '');
    _priority = TaskPriority.fromValue(t?.priority);
    _status = TaskStatus.fromStorage(t?.status);
    _dueDay = (t?.dueDay == null || t!.dueDay!.isEmpty)
        ? null
        : parseYmd(t.dueDay!);
  }

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final title = _title.text.trim();
    if (title.isEmpty) return;
    final repo = ref.read(taskRepositoryProvider);
    final dueStr = _dueDay == null ? null : formatYmd(_dueDay!);

    if (_isEdit) {
      final wasDone =
          TaskStatus.fromStorage(widget.existing!.status) == TaskStatus.done;
      final isDone = _status == TaskStatus.done;
      await repo.update(widget.existing!.copyWith(
        title: title,
        priority: _priority.value,
        status: _status.storageName,
        dueDay: Value(dueStr),
        completedAt: Value(
          isDone ? (wasDone ? widget.existing!.completedAt : DateTime.now()) : null,
        ),
      ));
    } else {
      await repo.create(title: title, priority: _priority, dueDay: dueStr);
    }
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _pickDate() async {
    final today = ref.read(todayProvider);
    final picked = await showDatePicker(
      context: context,
      initialDate: _dueDay ?? today,
      firstDate: DateTime(today.year - 1),
      lastDate: DateTime(today.year + 3),
      locale: const Locale('tr'),
    );
    if (picked != null) setState(() => _dueDay = dateOnly(picked));
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final today = ref.watch(todayProvider);

    return AlertDialog(
      title: Text(_isEdit ? 'Görevi düzenle' : 'Yeni görev'),
      content: SizedBox(
        width: 380,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _title,
                autofocus: true,
                onSubmitted: (_) => _save(),
                decoration: const InputDecoration(
                    labelText: 'Başlık', hintText: 'Ne yapılacak?'),
              ),
              const SizedBox(height: 18),
              Text('Öncelik',
                  style: TextStyle(
                      fontWeight: FontWeight.w600, color: colors.text)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  for (final p in TaskPriority.values)
                    ChoiceChip(
                      label: Text(p.label),
                      selected: _priority == p,
                      onSelected: (_) => setState(() => _priority = p),
                    ),
                ],
              ),
              if (_isEdit) ...[
                const SizedBox(height: 18),
                Text('Durum',
                    style: TextStyle(
                        fontWeight: FontWeight.w600, color: colors.text)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: [
                    for (final s in TaskStatus.values)
                      ChoiceChip(
                        label: Text(s.label),
                        selected: _status == s,
                        onSelected: (_) => setState(() => _status = s),
                      ),
                  ],
                ),
              ],
              const SizedBox(height: 18),
              Text('Tarih',
                  style: TextStyle(
                      fontWeight: FontWeight.w600, color: colors.text)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _DateChip(
                    label: 'Bugün',
                    selected: _dueDay == today,
                    onTap: () => setState(() => _dueDay = today),
                  ),
                  _DateChip(
                    label: 'Yarın',
                    selected: _dueDay ==
                        DateTime(today.year, today.month, today.day + 1),
                    onTap: () => setState(() => _dueDay =
                        DateTime(today.year, today.month, today.day + 1)),
                  ),
                  _DateChip(
                    label: 'Tarihsiz',
                    selected: _dueDay == null,
                    onTap: () => setState(() => _dueDay = null),
                  ),
                  ActionChip(
                    avatar: const Icon(Icons.calendar_today_outlined, size: 15),
                    label: Text(_dueDay == null ? 'Seç' : formatYmd(_dueDay!)),
                    onPressed: _pickDate,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
      actions: [
        if (_isEdit)
          TextButton(
            onPressed: () async {
              await ref.read(taskRepositoryProvider).delete(widget.existing!.id);
              if (context.mounted) Navigator.of(context).pop();
            },
            child: Text('Sil', style: TextStyle(color: colors.missed)),
          ),
        TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('İptal')),
        FilledButton(onPressed: _save, child: const Text('Kaydet')),
      ],
    );
  }
}

class _DateChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _DateChip(
      {required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => onTap(),
    );
  }
}
