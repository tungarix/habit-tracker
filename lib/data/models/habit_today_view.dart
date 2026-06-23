import '../../core/streak.dart';
import '../database/database.dart';

/// A habit decorated with everything the Today screen needs to render one row.
class HabitTodayView {
  final Habit habit;
  final bool doneToday;
  final bool scheduledToday;
  final StreakInfo streak;

  const HabitTodayView({
    required this.habit,
    required this.doneToday,
    required this.scheduledToday,
    required this.streak,
  });
}
