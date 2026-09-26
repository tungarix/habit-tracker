import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/enums.dart';
import '../../../core/sessions.dart';
import '../../../data/providers.dart';
import '../../../shared/theme.dart';

/// Pomodoro timer + this week's focus totals.
///
/// A row is written only when a run finishes (or is stopped after at least a
/// minute), so an abandoned timer never inflates the numbers.
class FocusCard extends ConsumerStatefulWidget {
  const FocusCard({super.key});

  @override
  ConsumerState<FocusCard> createState() => _FocusCardState();
}

class _FocusCardState extends ConsumerState<FocusCard> {
  static const _presets = <int>[25, 45, 15]; // minutes
  static const _minimumRecordedSeconds = 60;

  int _plannedMinutes = 25;
  SessionKind _kind = SessionKind.focus;
  DateTime? _startedAt;
  int _remaining = 25 * 60;
  Timer? _ticker;

  bool get _running => _ticker != null;

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  void _start() {
    setState(() {
      _startedAt = DateTime.now();
      _remaining = _plannedMinutes * 60;
      _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
    });
  }

  void _tick() {
    if (_remaining <= 1) {
      _finish(completed: true);
      return;
    }
    setState(() => _remaining--);
  }

  /// Stops the run. [completed] distinguishes "rang" from "stopped early".
  Future<void> _finish({required bool completed}) async {
    final started = _startedAt;
    _ticker?.cancel();
    _ticker = null;
    if (started == null) return;

    final ended = DateTime.now();
    final elapsed = ended.difference(started).inSeconds;

    setState(() {
      _startedAt = null;
      _remaining = _plannedMinutes * 60;
    });

    // Sub-minute runs are noise, not data.
    if (elapsed < _minimumRecordedSeconds) {
      if (mounted && !completed) {
        ScaffoldMessenger.of(context)
          ..clearSnackBars()
          ..showSnackBar(const SnackBar(
            duration: Duration(seconds: 2),
            content: Text('1 dakikadan kısa seans kaydedilmedi.'),
          ));
      }
      return;
    }

    await ref.read(sessionRepositoryProvider).record(
          kind: _kind,
          startedAt: started,
          endedAt: ended,
          durationS: elapsed,
          day: ref.read(todayProvider),
        );

    if (mounted && completed) {
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(SnackBar(
          duration: const Duration(seconds: 3),
          content: Text('${_kind.label} bitti · ${formatDuration(elapsed)}'),
        ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final summary = ref.watch(focusSummaryProvider);
    final total = _plannedMinutes * 60;
    final progress = _running ? 1 - (_remaining / total) : 0.0;

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(Icons.timer_outlined, size: 17, color: colors.textDim),
                const SizedBox(width: 8),
                Text('Odak',
                    style: TextStyle(
                        fontWeight: FontWeight.w700, color: colors.text)),
                const Spacer(),
                if (summary.dayStreak > 1)
                  Text('${summary.dayStreak} gün üst üste',
                      style: TextStyle(fontSize: 11, color: colors.textDim)),
              ],
            ),
            const SizedBox(height: 14),

            // Countdown
            Center(
              child: Text(
                formatClock(_running ? _remaining : total),
                style: kTabularNums.copyWith(
                  fontSize: 40,
                  fontWeight: FontWeight.w700,
                  height: 1,
                  color: _running ? colors.done : colors.text,
                ),
              ),
            ),
            const SizedBox(height: 12),

            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 5,
                color: _kind == SessionKind.focus ? colors.done : colors.gold,
                backgroundColor: colors.idle,
              ),
            ),
            const SizedBox(height: 14),

            if (!_running) ...[
              Row(
                children: [
                  for (final m in _presets) ...[
                    Expanded(
                      child: _Chip(
                        label: '$m dk',
                        selected: _plannedMinutes == m,
                        onTap: () => setState(() {
                          _plannedMinutes = m;
                          _kind =
                              m <= 15 ? SessionKind.rest : SessionKind.focus;
                          _remaining = m * 60;
                        }),
                      ),
                    ),
                    if (m != _presets.last) const SizedBox(width: 6),
                  ],
                ],
              ),
              const SizedBox(height: 10),
              FilledButton.icon(
                onPressed: _start,
                icon: const Icon(Icons.play_arrow_rounded, size: 20),
                label: Text('${_kind.label} başlat'),
              ),
            ] else
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _finish(completed: false),
                      icon: const Icon(Icons.stop_rounded, size: 18),
                      label: const Text('Bitir'),
                    ),
                  ),
                ],
              ),

            const SizedBox(height: 14),
            Divider(height: 1, color: colors.border),
            const SizedBox(height: 12),

            Row(
              children: [
                Expanded(
                  child: _Stat(
                    label: 'Bugün',
                    value: formatDuration(summary.todaySeconds),
                    colors: colors,
                  ),
                ),
                Expanded(
                  child: _Stat(
                    label: 'Son 7 gün',
                    value: formatDuration(summary.last7Seconds),
                    colors: colors,
                  ),
                ),
                Expanded(
                  child: _Stat(
                    label: 'Seans',
                    value: '${summary.last7Sessions}',
                    colors: colors,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _Chip({required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Material(
      color: selected ? colors.surfaceAlt : Colors.transparent,
      borderRadius: BorderRadius.circular(9),
      child: InkWell(
        borderRadius: BorderRadius.circular(9),
        onTap: onTap,
        child: Container(
          height: 34,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(9),
            border: Border.all(
              color: selected ? colors.done : colors.border,
            ),
          ),
          child: Text(
            label,
            style: kTabularNums.copyWith(
              fontSize: 12.5,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              color: selected ? colors.text : colors.textDim,
            ),
          ),
        ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  final String label;
  final String value;
  final AppColors colors;
  const _Stat({required this.label, required this.value, required this.colors});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(fontSize: 10.5, color: colors.textDim)),
        const SizedBox(height: 2),
        Text(value,
            style: kTabularNums.copyWith(
                fontSize: 15, fontWeight: FontWeight.w700, color: colors.text)),
      ],
    );
  }
}
