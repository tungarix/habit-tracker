import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants.dart';
import '../../core/date_utils.dart';
import '../../data/database/database.dart';
import '../../data/providers.dart';

/// Add / edit a habit. Pass [existing] to edit, leave null to create.
class HabitEditDialog extends ConsumerStatefulWidget {
  final Habit? existing;
  const HabitEditDialog({super.key, this.existing});

  static Future<void> show(BuildContext context, {Habit? existing}) {
    return showDialog<void>(
      context: context,
      builder: (_) => HabitEditDialog(existing: existing),
    );
  }

  @override
  ConsumerState<HabitEditDialog> createState() => _HabitEditDialogState();
}

class _HabitEditDialogState extends ConsumerState<HabitEditDialog> {
  late final TextEditingController _name;
  late final TextEditingController _desc;
  late int _colorValue;
  late int _iconCodePoint;
  late Set<int> _weekdays; // empty = every day

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _name = TextEditingController(text: e?.name ?? '');
    _desc = TextEditingController(text: e?.description ?? '');
    _colorValue = e?.colorValue ?? kHabitColors.first.toARGB32();
    _iconCodePoint = e?.iconCodePoint ?? kHabitIcons.first.codePoint;
    _weekdays = e == null ? <int>{} : parseWeekdays(e.scheduledWeekdays).toSet();
  }

  @override
  void dispose() {
    _name.dispose();
    _desc.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty) return;
    final repo = ref.read(habitRepositoryProvider);
    final desc = _desc.text.trim().isEmpty ? null : _desc.text.trim();
    final weekdays = weekdaysToString(_weekdays);

    if (_isEdit) {
      await repo.updateHabit(widget.existing!.copyWith(
        name: name,
        description: Value(desc),
        colorValue: _colorValue,
        iconCodePoint: _iconCodePoint,
        scheduledWeekdays: weekdays,
      ));
    } else {
      await repo.createHabit(
        name: name,
        description: desc,
        colorValue: _colorValue,
        iconCodePoint: _iconCodePoint,
        scheduledWeekdays: weekdays,
      );
    }
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(_isEdit ? 'Alışkanlığı düzenle' : 'Yeni alışkanlık'),
      content: SizedBox(
        width: 380,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _name,
                autofocus: true,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(labelText: 'Ad', hintText: 'Örn. Sabah egzersizi'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _desc,
                decoration: const InputDecoration(labelText: 'Açıklama (opsiyonel)'),
              ),
              const SizedBox(height: 20),
              _SectionLabel('Renk'),
              _ColorPicker(
                selected: _colorValue,
                onSelected: (c) => setState(() => _colorValue = c),
              ),
              const SizedBox(height: 20),
              _SectionLabel('İkon'),
              _IconPicker(
                selectedCodePoint: _iconCodePoint,
                color: Color(_colorValue),
                onSelected: (cp) => setState(() => _iconCodePoint = cp),
              ),
              const SizedBox(height: 20),
              _SectionLabel('Planlı günler'),
              const SizedBox(height: 4),
              Text(
                _weekdays.isEmpty ? 'Her gün' : 'Seçili günlerde',
                style: TextStyle(color: Theme.of(context).colorScheme.outline, fontSize: 12),
              ),
              const SizedBox(height: 8),
              _WeekdayPicker(
                selected: _weekdays,
                onChanged: (s) => setState(() => _weekdays = s),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('İptal')),
        FilledButton(onPressed: _save, child: const Text('Kaydet')),
      ],
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);
  @override
  Widget build(BuildContext context) =>
      Text(text, style: const TextStyle(fontWeight: FontWeight.w600));
}

class _ColorPicker extends StatelessWidget {
  final int selected;
  final ValueChanged<int> onSelected;
  const _ColorPicker({required this.selected, required this.onSelected});

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        for (final c in kHabitColors)
          GestureDetector(
            onTap: () => onSelected(c.toARGB32()),
            child: Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: c,
                shape: BoxShape.circle,
                border: Border.all(
                  color: c.toARGB32() == selected
                      ? Theme.of(context).colorScheme.onSurface
                      : Colors.transparent,
                  width: 3,
                ),
              ),
              child: c.toARGB32() == selected
                  ? const Icon(Icons.check, color: Colors.white, size: 18)
                  : null,
            ),
          ),
      ],
    );
  }
}

class _IconPicker extends StatelessWidget {
  final int selectedCodePoint;
  final Color color;
  final ValueChanged<int> onSelected;
  const _IconPicker({
    required this.selectedCodePoint,
    required this.color,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final icon in kHabitIcons)
          GestureDetector(
            onTap: () => onSelected(icon.codePoint),
            child: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: icon.codePoint == selectedCodePoint
                    ? color.withValues(alpha: 0.2)
                    : Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: icon.codePoint == selectedCodePoint ? color : Colors.transparent,
                  width: 2,
                ),
              ),
              child: Icon(icon,
                  color: icon.codePoint == selectedCodePoint
                      ? color
                      : Theme.of(context).colorScheme.onSurfaceVariant),
            ),
          ),
      ],
    );
  }
}

class _WeekdayPicker extends StatelessWidget {
  final Set<int> selected;
  final ValueChanged<Set<int>> onChanged;
  const _WeekdayPicker({required this.selected, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 6,
      children: [
        for (var day = 1; day <= 7; day++)
          FilterChip(
            label: Text(kWeekdayShort[day - 1]),
            selected: selected.contains(day),
            onSelected: (on) {
              final next = {...selected};
              if (on) {
                next.add(day);
              } else {
                next.remove(day);
              }
              onChanged(next);
            },
          ),
      ],
    );
  }
}
