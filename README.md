# Aktenak — Habit Tracker

Local-first, no-backend habit tracker. Built with Flutter (desktop-first: Windows + Linux).
See [BLUEPRINT.md](BLUEPRINT.md) for the full design rationale.

## Özellikler (mevcut durum)

- **Bugün**: günün alışkanlıkları, tek dokunuşla yaptım/yapmadım, mevcut seri (🔥) rozeti, günlük ilerleme çubuğu.
- **Alışkanlıklar**: oluştur / düzenle / arşivle / sil. Ad, açıklama, renk, ikon ve planlı günler (haftanın günleri; boş = her gün).
- **İstatistik**: mevcut & en uzun seri, tamamlanma oranı, takvim ısı haritası (heatmap), haftalık trend.
- **Yedek**: tüm veriyi tek bir `.json` dosyasına dışa aktar; içe aktarırken **Birleştir** veya **Tamamen değiştir** seç.

Veri tamamen yerel: drift (SQLite) ile cihazda saklanır. Sunucu, hesap, login yok.

## Mimari

```
lib/
  main.dart            # ProviderScope + locale init
  app.dart             # MaterialApp + NavigationRail/NavigationBar kabuğu
  core/                # constants, date_utils, streak (saf mantık), theme
  data/
    database/          # drift tabloları + AppDatabase (+ database.g.dart)
    models/            # HabitTodayView
    repositories/      # habit_repository, backup_repository
    providers.dart     # Riverpod sağlayıcıları
  features/
    today/ habits/ stats/ backup/
  shared/widgets/      # HabitAvatar, StreakBadge
```

Seri/istatistik mantığı `lib/core/streak.dart` içinde saf fonksiyonlar olarak durur ve
`test/widget_test.dart` ile birim test edilir.

## Geliştirme

Flutter SDK bu projede `C:\Users\user\flutter` altına kurulu (PATH'te değil). Komutlardan önce:

```powershell
$env:Path = "C:\Users\user\flutter\bin;" + $env:Path
```

Sık kullanılanlar:

```powershell
flutter pub get
dart run build_runner build           # drift kod üretimi (tabloları değiştirince)
flutter analyze
flutter test
```

## Masaüstünde çalıştırma (önkoşullar)

`flutter run -d windows` için iki şey gerekir (bu makinede henüz kurulu değil):

1. **Visual Studio** + "Desktop development with C++" iş yükü (Windows masaüstü derlemesi için zorunlu).
2. **Geliştirici Modu** (eklenti symlink'leri için): `start ms-settings:developers`.

Bunlar kurulduktan sonra:

```powershell
flutter run -d windows   # veya: flutter run -d linux
```

Kod analiz ve testten temiz geçiyor; eksik olan tek şey yukarıdaki yerel derleme zinciri.
