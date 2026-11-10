import 'dart:io';

import 'package:flutter/material.dart';

import '../../data/data_location.dart';
import '../../data/update/uygula.dart';

/// `--guncelle-uygula=1` ile açılan yeni sürümün tek işi: dosyaları değiştirip eskisini yeniden başlatmak.
/// Veritabanı, tepsi ve pencere yöneticisi AÇILMAZ.
Future<void> uygulayiciCalistir(List<String> args) async {
  final veri = await appDataDirectory();
  final a = UygulaArgumanlari.coz(args, veri);
  if (a == null) exit(2); // geçersiz argüman: hiçbir şeye dokunma
  runApp(
    const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('Güncelleniyor, lütfen bekle...'),
            ],
          ),
        ),
      ),
    ),
  );
  await uygula(
    yeni: File(Platform.resolvedExecutable).parent,
    hedef: a.hedef,
    sonuc: a.sonuc,
    pid: a.pid,
  );
  exit(0);
}
