import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../data/update/ag.dart';
import '../../data/update/akis.dart';
import '../../data/update/guncelleyici.dart';
import '../../surum.dart';

/// Hata koduna karşılık gelen Türkçe açıklama; ham istisna asla gösterilmez.
String guncellemeHataMetni(String kod) => switch (kod) {
  'ag_hatasi' => "GitHub'a ulaşılamadı. İnternet bağlantını kontrol et.",
  'limit' => 'GitHub şu an çok fazla istek aldı. Biraz sonra tekrar dene.',
  'bozuk_yanit' => "GitHub'dan beklenmeyen bir yanıt geldi.",
  'adres_izinsiz' => 'İndirme adresi güvenli bulunmadı, işlem durduruldu.',
  'boyut_uyusmuyor' => 'İndirilen dosyanın boyutu beklenenle uyuşmuyor.',
  'ozet_bulunamadi' =>
    'Sürümün doğrulama özeti bulunamadı, güncelleme yapılmadı.',
  'ozet_uyusmuyor' =>
    'İndirilen dosya doğrulanamadı (SHA-256 uyuşmuyor). Silindi.',
  'paket_bozuk' => 'Güncelleme paketi bozuk ya da beklenmeyen içerikte.',
  'klasor_yazilamaz' =>
    'Uygulamanın klasörüne yazılamıyor (ör. Program Files). Yeni sürümü elle indir.',
  'disk_dolu' => 'Diskte yeterli yer yok.',
  'izin_yok' => 'Dosya izni ya da yedek sorunu nedeniyle devam edilemedi.',
  'surum_dusuk' => 'Bu sürüm zaten kurulu olandan yeni değil.',
  'iptal' => 'İndirme iptal edildi.',
  _ => 'Güncelleme yapılamadı.',
};

enum _Asama { bosta, denetliyor, indiriyor, hazir, kuruluyor }

/// Yedek & Ayarlar içindeki "Güncelleme" kartı: denetle / indir / kur.
class GuncellemeBolumu extends ConsumerStatefulWidget {
  const GuncellemeBolumu({super.key});

  @override
  ConsumerState<GuncellemeBolumu> createState() => _GuncellemeBolumuState();
}

class _GuncellemeBolumuState extends ConsumerState<GuncellemeBolumu> {
  _Asama _asama = _Asama.bosta;
  String? _hata;
  int _alinan = 0;
  Iptal? _iptal;

  Future<void> _denetle(Guncelleyici g) async {
    setState(() {
      _asama = _Asama.denetliyor;
      _hata = null;
    });
    await g.denetle();
    if (!mounted) return;
    setState(() {
      _asama = _Asama.bosta;
      _hata = g.hataKodu;
    });
  }

  Future<void> _indir(Guncelleyici g) async {
    final y = g.teklif;
    if (y == null) return;
    final iptal = Iptal();
    setState(() {
      _asama = _Asama.indiriyor;
      _hata = null;
      _alinan = 0;
      _iptal = iptal;
    });
    try {
      await (await ref.read(kurucuProvider.future)).onKosul();
      await g.hazirla(
        y,
        iptal: iptal,
        ilerleme: (n) {
          if (mounted) setState(() => _alinan = n);
        },
      );
      if (mounted) setState(() => _asama = _Asama.hazir);
    } on GuncellemeHatasi catch (e) {
      if (mounted) {
        setState(() {
          _asama = _Asama.bosta;
          _hata = e.kod;
        });
      }
    }
  }

  Future<void> _sonra(Guncelleyici g) async {
    await g.temizle();
    if (mounted) setState(() => _asama = _Asama.bosta);
  }

  Future<void> _kur(Guncelleyici g) async {
    setState(() => _asama = _Asama.kuruluyor);
    try {
      await (await ref.read(kurucuProvider.future)).kur(g);
    } on GuncellemeHatasi catch (e) {
      if (mounted) {
        setState(() {
          _asama = _Asama.hazir;
          _hata = e.kod;
        });
      }
    }
  }

  static String _mb(int bayt) => (bayt / (1024 * 1024)).toStringAsFixed(0);

  @override
  Widget build(BuildContext context) {
    final g = ref.watch(guncelleyiciProvider).value;
    final tema = Theme.of(context);
    final buyuk = ButtonStyle(
      minimumSize: WidgetStateProperty.all(const Size(48, 48)),
    );
    if (g == null) {
      return const Card(
        child: ListTile(
          title: Text('Güncelleme'),
          subtitle: Text('Yükleniyor...'),
        ),
      );
    }
    final teklif = g.teklif;
    final son = g.sonDenetim;
    final hata = _hata ?? (_asama == _Asama.bosta ? g.hataKodu : null);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Sürüm $uygulamaSurumu', style: tema.textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              son == null
                  ? 'Henüz denetlenmedi.'
                  : 'Son denetim: ${DateFormat('d MMM y HH:mm', 'tr').format(son.toLocal())}',
              style: TextStyle(color: tema.colorScheme.outline),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Yeni sürümleri denetle'),
              subtitle: const Text(
                'Günde en çok bir kez yalnız github.com/tungarix/habit-tracker '
                'adresine sürüm sorar; kişisel veri göndermez.',
              ),
              value: g.denetim ?? false,
              onChanged: _asama == _Asama.bosta
                  ? (acik) async {
                      await g.denetimYaz(acik);
                      if (acik) {
                        await _denetle(g);
                      } else if (mounted) {
                        setState(() {});
                      }
                    }
                  : null,
            ),
            if (_asama == _Asama.bosta || _asama == _Asama.denetliyor)
              Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton.icon(
                  style: buyuk,
                  onPressed: _asama == _Asama.bosta ? () => _denetle(g) : null,
                  icon: const Icon(Icons.refresh),
                  label: Text(
                    _asama == _Asama.denetliyor
                        ? 'Denetleniyor...'
                        : 'Şimdi denetle',
                  ),
                ),
              ),
            if (hata != null) ...[
              const SizedBox(height: 8),
              Semantics(
                liveRegion: true,
                child: Text(
                  '${guncellemeHataMetni(hata)} ($hata)',
                  style: TextStyle(color: tema.colorScheme.error),
                ),
              ),
            ],
            if (teklif != null) ...[
              const Divider(height: 24),
              Text(
                'Yeni sürüm ${teklif.surum} (≈ ${_mb(teklif.zipBoyut)} MB)',
                style: tema.textTheme.titleSmall,
              ),
              const SizedBox(height: 4),
              const Text(
                'Bu sürüm imzalı değil; yalnız SHA-256 ile doğrulandı.',
              ),
              const SizedBox(height: 8),
              if (_asama == _Asama.indiriyor) ...[
                Semantics(
                  label: 'İndirme ilerlemesi',
                  child: LinearProgressIndicator(
                    value: teklif.zipBoyut > 0
                        ? _alinan / teklif.zipBoyut
                        : null,
                  ),
                ),
                const SizedBox(height: 4),
                Text('${_mb(_alinan)} / ${_mb(teklif.zipBoyut)} MB'),
                const SizedBox(height: 8),
                OutlinedButton(
                  style: buyuk,
                  onPressed: () => _iptal?.iptalEt(),
                  child: const Text('İptal'),
                ),
              ] else if (_asama == _Asama.hazir ||
                  _asama == _Asama.kuruluyor) ...[
                Text(
                  'Güncelleme hazır. Uygulama kapanıp ${teklif.surum} ile '
                  'yeniden açılacak; verilerine dokunulmaz. Çalışan bir odak '
                  'sayacın varsa o seans kaydedilmez.',
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    FilledButton(
                      style: buyuk,
                      onPressed: _asama == _Asama.hazir ? () => _kur(g) : null,
                      child: const Text('Kapat ve güncelle'),
                    ),
                    OutlinedButton(
                      style: buyuk,
                      onPressed: _asama == _Asama.hazir
                          ? () => _sonra(g)
                          : null,
                      child: const Text('Sonra'),
                    ),
                  ],
                ),
              ] else
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    FilledButton(
                      style: buyuk,
                      onPressed: _asama == _Asama.bosta
                          ? () => _indir(g)
                          : null,
                      child: const Text('İndir ve doğrula'),
                    ),
                    OutlinedButton(
                      style: buyuk,
                      onPressed: () => surumNotlariniAc(teklif),
                      child: const Text('Sürüm notları'),
                    ),
                  ],
                ),
            ],
          ],
        ),
      ),
    );
  }
}
