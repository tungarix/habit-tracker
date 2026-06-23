import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants.dart';
import '../../core/date_utils.dart';
import '../../data/database/database.dart';
import '../../data/providers.dart';
import '../../shared/widgets/habit_avatar.dart';
import 'habit_edit_dialog.dart';

/// Manage habits: create, edit, archive, restore, delete.
class HabitsScreen extends ConsumerWidget {
  const HabitsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activeAsync = ref.watch(activeHabitsProvider);
    final archivedAsync = ref.watch(archivedHabitsProvider);

    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => HabitEditDialog.show(context),
        icon: const Icon(Icons.add),
        label: const Text('Alışkanlık'),
      ),
      body: SafeArea(
        child: activeAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text('Hata: $e')),
          data: (active) {
            final archived = archivedAsync.value ?? const <Habit>[];
            return ListView(
              padding: const EdgeInsets.fromLTRB(12, 20, 12, 96),
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
                  child: Text('Alışkanlıklar', style: Theme.of(context).textTheme.headlineMedium),
                ),
                if (active.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(24),
                    child: Center(child: Text('Henüz aktif alışkanlık yok.')),
                  ),
                for (final h in active) _ActiveHabitTile(habit: h),
                if (archived.isNotEmpty) ...[
                  const Padding(
                    padding: EdgeInsets.fromLTRB(8, 24, 8, 8),
                    child: Text('Arşiv', style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                  for (final h in archived) _ArchivedHabitTile(habit: h),
                ],
              ],
            );
          },
        ),
      ),
    );
  }
}

class _ActiveHabitTile extends ConsumerWidget {
  final Habit habit;
  const _ActiveHabitTile({required this.habit});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.read(habitRepositoryProvider);
    final days = parseWeekdays(habit.scheduledWeekdays);
    final subtitle = days.isEmpty ? 'Her gün' : days.map((d) => kWeekdayShort[d - 1]).join(' · ');

    return Card(
      child: ListTile(
        onTap: () => HabitEditDialog.show(context, existing: habit),
        leading: HabitAvatar(habit: habit),
        title: Text(habit.name, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(subtitle),
        trailing: PopupMenuButton<String>(
          onSelected: (value) {
            switch (value) {
              case 'edit':
                HabitEditDialog.show(context, existing: habit);
              case 'archive':
                repo.archive(habit.id);
            }
          },
          itemBuilder: (_) => const [
            PopupMenuItem(value: 'edit', child: Text('Düzenle')),
            PopupMenuItem(value: 'archive', child: Text('Arşivle')),
          ],
        ),
      ),
    );
  }
}

class _ArchivedHabitTile extends ConsumerWidget {
  final Habit habit;
  const _ArchivedHabitTile({required this.habit});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.read(habitRepositoryProvider);
    return Card(
      child: Opacity(
        opacity: 0.7,
        child: ListTile(
          leading: HabitAvatar(habit: habit, size: 36),
          title: Text(habit.name),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                tooltip: 'Geri yükle',
                icon: const Icon(Icons.unarchive_outlined),
                onPressed: () => repo.unarchive(habit.id),
              ),
              IconButton(
                tooltip: 'Sil',
                icon: const Icon(Icons.delete_outline),
                onPressed: () => _confirmDelete(context, ref, habit),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref, Habit habit) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Kalıcı olarak sil?'),
        content: Text('“${habit.name}” ve tüm kayıtları silinecek. Bu geri alınamaz.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('İptal')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.error),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Sil'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await ref.read(habitRepositoryProvider).delete(habit.id);
    }
  }
}
