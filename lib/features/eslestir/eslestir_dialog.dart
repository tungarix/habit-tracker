import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;

import '../../core/wifi_sync/sunucu.dart';
import '../../data/providers.dart';
import '../../data/sync/sync_export.dart';
import '../../data/sync/sync_format.dart';
import '../../data/sync/sync_import.dart';
import 'qr_cizici.dart';

/// "Telefonla eşleştir (Wi-Fi)": QR gösterir, iki onayı alır, sonucu yazar.
Future<void> eslestirDialogAc(BuildContext context) => showDialog<void>(
  context: context,
  barrierDismissible: false,
  builder: (_) => const EslestirDialog(),
);

class EslestirDialog extends ConsumerStatefulWidget {
  /// [sunucuFabrikasi] yalnız testte: gerçek ağ adresi yerine loopback vb.
  const EslestirDialog({super.key, this.sunucuFabrikasi});

  final EslestirmeSunucusu Function({
    required Future<Uint8List> Function() durumAl,
    required Future<SyncReport> Function(Uint8List) onizle,
    required Future<SyncReport> Function(Uint8List) uygula,
    required Future<void> Function() yedekAl,
  })?
  sunucuFabrikasi;

  @override
  ConsumerState<EslestirDialog> createState() => _EslestirDialogState();
}

class _EslestirDialogState extends ConsumerState<EslestirDialog> {
  EslestirmeSunucusu? _s;
  String? _baslatHatasi;
  EslestirmeDurum _durum = EslestirmeDurum.bekliyor;
  StreamSubscription<EslestirmeDurum>? _abone;
  Timer? _saat;
  DateTime _basladi = DateTime.now();

  @override
  void initState() {
    super.initState();
    // Sunucu geri çağrıları pencere kapandıktan sonra da çalışabilir; `ref`
    // oradan okunamaz, bu yüzden bağımlılıklar şimdi alınır.
    final db = ref.read(databaseProvider);
    final repo = ref.read(backupRepositoryProvider);
    final dataDir = ref.read(dataDirectoryProvider.future);

    Future<Uint8List> durumAl() async =>
        Uint8List.fromList(utf8.encode(await exportSync(db)));
    Future<void> yedekAl() async {
      final klasor = Directory(p.join((await dataDir).path, 'yedekler'));
      await klasor.create(recursive: true);
      final ad = 'aktenak-sync-${DateFormat('yyyyMMdd-HHmmss').format(DateTime.now())}.json';
      await File(p.join(klasor.path, ad)).writeAsString(await repo.exportJson(), flush: true);
    }

    onizle(Uint8List b) => previewSyncBytes(db, b);
    uygula(Uint8List b) async {
      final r = await importSyncBytes(db, b);
      ref.invalidate(dayStartHourProvider); // gün başlangıcı dosyayla gelmiş olabilir
      return r;
    }

    final s =
        widget.sunucuFabrikasi?.call(durumAl: durumAl, onizle: onizle, uygula: uygula, yedekAl: yedekAl) ??
        EslestirmeSunucusu(
          durumAl: durumAl,
          onizle: onizle,
          uygula: uygula,
          yedekAl: yedekAl,
          sunucuAdi: Platform.localHostname,
          surum: 'masaustu',
        );
    _s = s;
    _abone = s.durumlar.listen((d) {
      if (mounted) setState(() => _durum = d);
    });
    _saat = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
    s.baslat().then((_) {
      if (mounted) setState(() => _basladi = DateTime.now());
    }, onError: (Object e) {
      if (mounted) {
        setState(() => _baslatHatasi = e is StateError
            ? e.message
            : 'Eşleştirme sunucusu açılamadı.');
      }
    });
  }

  @override
  void dispose() {
    _saat?.cancel();
    _abone?.cancel();
    _s?.kapat();
    super.dispose();
  }

  void _kapat() => Navigator.of(context).pop();

  @override
  Widget build(BuildContext context) {
    final s = _s!;
    final bitti = _durum.bitti || _baslatHatasi != null;
    return PopScope(
      canPop: false, // Esc / geri tuşu yanlışlıkla oturumu bitirmesin; İptal düğmesi var
      child: AlertDialog(
        title: const Text('Telefonla eşleştir (Wi-Fi)'),
        content: SizedBox(
          width: 400,
          child: SingleChildScrollView(child: _icerik(context, s)),
        ),
        actions: _eylemler(s, bitti),
      ),
    );
  }

  List<Widget> _eylemler(EslestirmeSunucusu s, bool bitti) {
    final stil = FilledButton.styleFrom(minimumSize: const Size(48, 48));
    final metin = TextButton.styleFrom(minimumSize: const Size(48, 48));
    if (bitti) {
      return [FilledButton(style: stil, onPressed: _kapat, child: const Text('Kapat'))];
    }
    switch (_durum) {
      case EslestirmeDurum.baglantiOnayi:
        return [
          TextButton(style: metin, onPressed: () => s.baglantiyiOnayla(false), child: const Text('Hayır')),
          FilledButton(style: stil, onPressed: () => s.baglantiyiOnayla(true), child: const Text('Evet, bu benim telefonum')),
        ];
      case EslestirmeDurum.birlesmeOnayi:
        final degisiklikYok = !(s.ozet?.changed ?? true);
        return [
          if (!degisiklikYok)
            TextButton(style: metin, onPressed: () => s.birlesmeyiOnayla(false), child: const Text('Vazgeç')),
          FilledButton(
            style: stil,
            onPressed: () => s.birlesmeyiOnayla(true),
            child: Text(degisiklikYok ? 'Tamam' : 'Uygula'),
          ),
        ];
      case EslestirmeDurum.isleniyor:
        return const [];
      default:
        return [
          TextButton(style: metin, onPressed: s.iptalEt, child: const Text('İptal')),
        ];
    }
  }

  Widget _icerik(BuildContext context, EslestirmeSunucusu s) {
    if (_baslatHatasi != null) {
      return Text(_baslatHatasi!);
    }
    switch (_durum) {
      case EslestirmeDurum.bekliyor:
        return s.qr == null ? _bekleme('Hazırlanıyor…') : _qrGorunumu(context, s);
      case EslestirmeDurum.baglantiOnayi:
        final i = s.istemci;
        return _canli(
          '«${i?.ad}» (${i?.ip}) bağlanmak istiyor. Bu senin telefonun mu?\n\n'
          'Tanımıyorsan Hayır de: Evet dersen bu bilgisayardaki tüm veri o cihaza gönderilir.',
        );
      case EslestirmeDurum.hazir:
        return _bekleme('Telefonla veri alışverişi sürüyor…');
      case EslestirmeDurum.birlesmeOnayi:
        return _ozet(context, s.ozet!);
      case EslestirmeDurum.isleniyor:
        return _bekleme('Birleştiriliyor, lütfen bekle…');
      case EslestirmeDurum.tamam:
        return _canli('Eşleştirme tamam. ${s.sonuc?.summary() ?? ''}\nTelefon da güncellendi.');
      case EslestirmeDurum.reddedildi:
        return _canli('Eşleştirme reddedildi. Bu bilgisayarda hiçbir şey değişmedi.');
      case EslestirmeDurum.iptal:
        return _canli('Eşleştirme iptal edildi. Bu bilgisayarda hiçbir şey değişmedi.');
      case EslestirmeDurum.sureDoldu:
        return _canli('Süre doldu. Bu bilgisayarda hiçbir şey değişmedi. İstersen yeniden başlat.');
      case EslestirmeDurum.hata:
        return _canli('Eşleştirme tamamlanamadı. Bu bilgisayarda hiçbir şey değişmedi ya da değişiklik geri alındı. Yeniden dene.');
    }
  }

  Widget _canli(String t) => Semantics(liveRegion: true, child: Text(t));

  Widget _bekleme(String t) => Semantics(
    liveRegion: true,
    child: Row(
      children: [
        const SizedBox.square(dimension: 24, child: CircularProgressIndicator(strokeWidth: 3)),
        const SizedBox(width: 16),
        Expanded(child: Text(t)),
      ],
    ),
  );

  Widget _qrGorunumu(BuildContext context, EslestirmeSunucusu s) {
    final q = s.qr!;
    final metin = q.kodla();
    final kalan = s.qrBitis!.difference(DateTime.now()).inSeconds.clamp(0, 9999);
    final yardim = DateTime.now().difference(_basladi).inSeconds >= 20;
    final stil = Theme.of(context).textTheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Telefondaki Habit Tracker\'da Wi-Fi ile eşleştirmeyi aç, "QR\'ı tara"ya bas ve bu kodu okut.'),
        const SizedBox(height: 12),
        Center(child: QrCizici(metin: metin)),
        const SizedBox(height: 8),
        Semantics(
          liveRegion: true,
          child: Text(
            'Kalan süre: ${kalan ~/ 60}:${(kalan % 60).toString().padLeft(2, '0')}',
            style: stil.titleSmall,
          ),
        ),
        const SizedBox(height: 8),
        Text('Adres: ${q.adresler.join(', ')}  ·  Port: ${q.port}', style: stil.bodySmall),
        const SizedBox(height: 8),
        const Text('Kamera yoksa bağlantıyı kopyalayıp telefona yapıştır:'),
        const SizedBox(height: 4),
        SelectableText(metin, style: stil.bodySmall?.copyWith(fontFamily: 'Consolas')),
        const SizedBox(height: 4),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
            icon: const Icon(Icons.copy),
            label: const Text('Kopyala'),
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: metin));
              if (!context.mounted) return;
              ScaffoldMessenger.maybeOf(context)?.showSnackBar(
                const SnackBar(content: Text('Bağlantı kopyalandı.')),
              );
            },
          ),
        ),
        Text(
          'Bu bağlantı bir parola gibidir; yalnız kendi telefonuna ver. '
          'Windows izin sorarsa "Özel ağlar"a izin ver.',
          style: stil.bodySmall,
        ),
        if (yardim) ...[
          const SizedBox(height: 12),
          Text('Telefon bağlanamıyor mu?', style: stil.titleSmall),
          const Text(
            '• Telefon ve bilgisayar aynı Wi-Fi\'da olmalı (misafir ağlar çoğu zaman engeller).\n'
            '• Windows\'ta ağ profili "Genel" ise "Özel"e al.\n'
            '• Windows Güvenlik Duvarı > Uygulamaya izin ver > Aktenak Habit Tracker > Özel.\n'
            '• VPN açıksa kapat.',
          ),
        ],
      ],
    );
  }

  Widget _ozet(BuildContext context, SyncReport r) {
    final stil = Theme.of(context).textTheme;
    Widget satir(String ad, SyncCounts c) => c.changed == 0
        ? const SizedBox.shrink()
        : Text('$ad: ${c.added} eklenecek, ${c.updated} güncellenecek, ${c.deleted} silinecek');
    if (!r.changed) {
      return _canli('Telefondan gelen veride değişiklik yok, her şey zaten güncel.');
    }
    return Semantics(
      liveRegion: true,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Telefondan gelen veri bu bilgisayarla birleştirilecek.', style: stil.bodyMedium),
          const SizedBox(height: 8),
          Text(
            '${r.added} eklenecek · ${r.updated} güncellenecek · ${r.deleted} silinecek',
            style: stil.titleMedium,
          ),
          const SizedBox(height: 8),
          satir('Alışkanlık', r.habit),
          satir('İşaret', r.entry),
          satir('Ruh hali', r.mood),
          satir('Görev', r.task),
          satir('Odak seansı', r.session),
          satir('Ayar', r.setting),
          if (r.deleted > 0) ...[
            const SizedBox(height: 8),
            Text(
              'Dikkat: ${r.deleted} kayıt silinecek (silinen alışkanlığın işaretleri de gider). '
              'Uygulamadan önce otomatik yedek alınır.',
              style: stil.bodyMedium?.copyWith(color: Theme.of(context).colorScheme.error),
            ),
          ],
          const SizedBox(height: 8),
          Text('Sayılar şu an için geçerlidir; uygulanınca telefon da bu bilgisayarın verisiyle güncel olur.', style: stil.bodySmall),
        ],
      ),
    );
  }
}
