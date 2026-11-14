import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/date_utils.dart';
import '../../../core/enums.dart';
import '../../../data/providers.dart';
import '../../../shared/theme.dart';

const _aylar = [
  'Ocak', 'Şubat', 'Mart', 'Nisan', 'Mayıs', 'Haziran',
  'Temmuz', 'Ağustos', 'Eylül', 'Ekim', 'Kasım', 'Aralık',
];

/// '2026-11-12' -> '12 Kasım 2026'.
String moodGunBasligi(String ymd) {
  final d = parseYmd(ymd);
  return '${d.day} ${_aylar[d.month - 1]} ${d.year}';
}

/// Onay penceresi; yalnız "Sil" true döndürür.
Future<bool> moodOnayIste(
  BuildContext context, {
  required String baslik,
  required String govde,
}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(baslik),
      content: Text(govde),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('İptal')),
        TextButton(
          style: TextButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.error),
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Sil'),
        ),
      ],
    ),
  );
  return ok ?? false;
}

/// Not penceresini açar; boş metin (ya da "Notu sil") notu siler, ruh hali kalır.
/// Bugün kartı ve geçmiş penceresi ortak kullanır.
Future<void> moodNotuDuzenle(
  BuildContext context,
  WidgetRef ref,
  String dateStr,
  String? current, {
  String baslik = 'Bugüne kısa not',
}) async {
  final result = await showDialog<String>(
    context: context,
    builder: (context) =>
        _NotDiyalogu(baslangic: current ?? '', baslik: baslik),
  );
  if (result != null) {
    final trimmed = result.trim();
    await ref
        .read(habitRepositoryProvider)
        .setMoodNote(dateStr, trimmed.isEmpty ? null : trimmed);
  }
}

/// Kendi controller'ını taşır: showDialog döner dönmez dispose etmek, kapanış
/// animasyonu sürerken TextField hâlâ dinliyorken çalışırdı.
class _NotDiyalogu extends StatefulWidget {
  final String baslangic;
  final String baslik;
  const _NotDiyalogu({required this.baslangic, required this.baslik});

  @override
  State<_NotDiyalogu> createState() => _NotDiyaloguState();
}

class _NotDiyaloguState extends State<_NotDiyalogu> {
  late final controller = TextEditingController(text: widget.baslangic);

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(widget.baslik),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 200,
          decoration: const InputDecoration(hintText: 'Örn. yoğun bir gündü'),
          onSubmitted: (v) => Navigator.pop(context, v),
        ),
        actions: [
          if (widget.baslangic.isNotEmpty)
            TextButton(
                onPressed: () => Navigator.pop(context, ''),
                child: const Text('Notu sil')),
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('İptal')),
          FilledButton(
              onPressed: () => Navigator.pop(context, controller.text),
              child: const Text('Kaydet')),
        ],
      );
}

/// Tüm ruh hali kayıtları, yeniden eskiye; not düzenleme ve gün silme.
class MoodGecmisiDialog extends ConsumerWidget {
  const MoodGecmisiDialog({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = AppColors.of(context);
    final moods = [...?ref.watch(allMoodsProvider).value]
      ..sort((a, b) => b.date.compareTo(a.date));

    return AlertDialog(
      title: const Text('Ruh hali geçmişi'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520, maxHeight: 560),
        child: SizedBox(
          width: 520,
          child: moods.isEmpty
              ? Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: Text('Henüz ruh hali kaydı yok.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: colors.textDim)),
                )
              : ListView.builder(
                  shrinkWrap: true,
                  itemCount: moods.length,
                  itemBuilder: (context, i) {
                    final m = moods[i];
                    final mood = Mood.fromValue(m.mood);
                    final note = m.note ?? '';
                    final baslik = moodGunBasligi(m.date);
                    return ListTile(
                      leading: mood == null
                          ? null
                          : Icon(mood.icon, semanticLabel: mood.label),
                      title: Text(baslik),
                      subtitle: Text(
                        note.isEmpty ? 'Not yok' : note,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: note.isEmpty
                            ? TextStyle(color: colors.textDim)
                            : null,
                      ),
                      trailing: IconButton(
                        tooltip: 'Sil: $baslik',
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () async {
                          final ok = await moodOnayIste(
                            context,
                            baslik: 'Bu günün kaydı silinsin mi?',
                            govde: 'Ruh hali ve notu silinir. Bu geri alınamaz.',
                          );
                          if (ok) {
                            await ref
                                .read(habitRepositoryProvider)
                                .clearMood(m.date);
                          }
                        },
                      ),
                      onTap: () => moodNotuDuzenle(
                        context,
                        ref,
                        m.date,
                        m.note,
                        baslik: baslik,
                      ),
                    );
                  },
                ),
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Kapat')),
      ],
    );
  }
}
