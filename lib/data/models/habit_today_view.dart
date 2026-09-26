import '../../core/enums.dart';
import '../../core/streak.dart';
import '../database/database.dart';

/// A habit decorated with everything the Today screen needs to render one row.
class HabitTodayView {
  final Habit habit;

  /// Today's explicit mark; null = untracked (boş).
  final EntryStatus? status;
  final bool scheduledToday;
  final StreakInfo streak;

  const HabitTodayView({
    required this.habit,
    required this.status,
    required this.scheduledToday,
    required this.streak,
  });

  bool get doneToday => status == EntryStatus.done;
}
