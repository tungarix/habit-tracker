import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/update/akis.dart';
import '../../data/update/uygula.dart';
import '../../surum.dart';

/// Açılışta: önceki güncellemenin sonucunu bildirir, ilk seferde denetim izni sorar, açıksa
/// günde en çok bir kez (saatlik zamanlayıcıyla) sürüm sorar. [etkin] false ise hiçbir şey yapmaz (testler).
class GuncellemeAcilis extends ConsumerStatefulWidget {
  const GuncellemeAcilis({super.key, required this.child, this.etkin = false});

  final Widget child;
  final bool etkin;

  @override
  ConsumerState<GuncellemeAcilis> createState() => _GuncellemeAcilisState();
}

class _GuncellemeAcilisState extends ConsumerState<GuncellemeAcilis> {
  Timer? _zamanlayici;

  @override
  void initState() {
    super.initState();
    if (!widget.etkin) return;
    WidgetsBinding.instance.addPostFrameCallback((_) => _basla());
  }

  @override
  void dispose() {
    _zamanlayici?.cancel();
    super.dispose();
  }

  Future<void> _basla() async {
    try {
      final kurucu = await ref.read(kurucuProvider.future);
      final g = await ref.read(guncelleyiciProvider.future);
      final mesaj = await sonucuOkuVeTemizle(
        sonuc: kurucu.sonucDosyasi,
        kurulum: kurucu.kurulumKlasoru,
        hazirlik: g.klasor,
        surum: uygulamaSurumu,
      );
      if (!mounted) return;
      if (mesaj != null) {
        ScaffoldMessenger.maybeOf(
          context,
        )?.showSnackBar(SnackBar(content: Text(mesaj)));
      }
      if (g.denetim == null) {
        final evet = await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (c) => AlertDialog(
            title: const Text('Yeni sürümleri denetleyeyim mi?'),
            content: const Text(
              'Uygulama yalnızca github.com/tungarix/habit-tracker adresine '
              'yeni sürüm var mı diye sorar; kişisel veri göndermez. '
              'Bunu sonra Yedek & Ayarlar bölümünden değiştirebilirsin.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(c, false),
                child: const Text('Denetleme'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(c, true),
                child: const Text('Denetle'),
              ),
            ],
          ),
        );
        await g.denetimYaz(evet ?? false);
      }
      Future<void> adim() async {
        if (await g.otomatikAdim()) ref.invalidate(guncelleyiciProvider);
      }

      unawaited(adim());
      _zamanlayici = Timer.periodic(const Duration(hours: 1), (_) => adim());
    } catch (_) {
      // Güncelleme yardımcıdır: hatası uygulamayı düşürmemeli.
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
