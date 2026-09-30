# Contributing · Katkıda bulunma

[English](#english) · [Türkçe](#türkçe)

Thanks for looking at Habit Tracker. Bug reports, small fixes and well-argued
suggestions are all welcome, in English or Turkish. By taking part you agree to
follow the [Code of Conduct](CODE_OF_CONDUCT.md). Security problems go through
the private channel in [SECURITY.md](SECURITY.md), not a public issue.

---

## English

### Before you write code

- **Open an issue first** for anything bigger than a typo or an obvious bug
  fix, so we can agree on the direction before you spend the time.
- **The app is local-only on purpose.** No server, account, login or cloud /
  multi-device sync. A pull request that adds one of them will be declined,
  however good the code is. Everything else is open for discussion.
- Bug reports: say which version you run (the release you downloaded) and what
  you did. **Never attach your own database or a backup with real data.**

### Set up (Windows)

You need the [Flutter SDK](https://docs.flutter.dev/get-started/install)
(stable channel), plus Visual Studio Build Tools with the "Desktop development
with C++" workload for the Windows build. `flutter doctor` tells you what is
missing.

```powershell
flutter pub get
dart run build_runner build   # drift code generation, after changing tables
flutter run -d windows
```

### Checks: the same ones CI runs

```powershell
flutter analyze
flutter test
flutter build windows --release
```

A pull request should pass all three. CI runs them for you on every push.

### Rules that matter

The architecture and its reasons are in the [README](README.md#mimari)
(Turkish). The ones you will meet first:

- **`core/` is pure logic and imports nothing from Flutter or any GUI code.**
  `test/core_purity_test.dart` enforces it. `features/` draws the UI and
  calls `core/`; it does no calculations of its own.
- **The tracking day does not start at midnight.** It starts at
  `day_start_hour` (04:00 by default). All date maths goes through `dayOf()` in
  `core/date_utils.dart`, and the UI reads "today" from `todayProvider`. Never
  build a day from a raw `DateTime.now()`.
- **Every migration step must be idempotent:** check that a column or table
  exists before adding it. This comes from a real failure (a half-applied
  upgrade left the database permanently locked). `test/migration_test.dart`
  covers it. A schema change also bumps `schemaVersion`.
- **Generated code is committed.** After changing drift tables, run
  `dart run build_runner build` and include the updated `database.g.dart`.
- **Code and doc comments are in English; user-facing text is Turkish.**
  Comments explain *why*, not *what*.
- **New behaviour comes with a test**, next to the existing ones in `test/`.

### Pull requests

- Keep them small and about one thing. Link the issue.
- Update the README where it describes the behaviour you changed.
- Don't commit build output, local files or personal data.
- By contributing you agree that your work is released under the
  [MIT License](LICENSE).

---

## Türkçe

Habit Tracker'a baktığın için sağ ol. Hata bildirimi, küçük düzeltme ve
gerekçesi olan öneri, Türkçe ya da İngilizce, hepsi hoş karşılanır. Katılırken
[Davranış Kuralları](CODE_OF_CONDUCT.md)'na uymayı kabul edersin. Güvenlik
sorunları herkese açık issue'ya değil, [SECURITY.md](SECURITY.md)'deki özel
kanala gider.

### Kod yazmadan önce

- Yazım hatası ya da bariz bir hata düzeltmesinden büyük her şey için **önce
  issue aç**; zamanını harcamadan yönü birlikte netleştirelim.
- **Uygulama bilerek yalnızca yerel.** Sunucu, hesap, login ya da bulut / çoklu
  cihaz senkronu yok. Bunlardan birini ekleyen bir pull request kod ne kadar iyi
  olursa olsun kabul edilmez. Gerisi tartışmaya açık.
- Hata bildiriminde hangi sürümü kullandığını (indirdiğin sürüm) ve ne
  yaptığını yaz. **Kendi veritabanını ya da gerçek veri içeren bir yedeği asla
  ekleme.**

### Kurulum (Windows)

[Flutter SDK](https://docs.flutter.dev/get-started/install) (stable kanalı) ve
Windows derlemesi için "Desktop development with C++" iş yükü olan Visual Studio
Build Tools gerekir. Eksik olanı `flutter doctor` söyler.

```powershell
flutter pub get
dart run build_runner build   # drift kod üretimi, tabloları değiştirince
flutter run -d windows
```

### Kontroller: CI'ın çalıştırdıklarının aynısı

```powershell
flutter analyze
flutter test
flutter build windows --release
```

Pull request'in üçünü de geçmeli. CI her push'ta bunları senin yerine çalıştırır.

### Önemli kurallar

Mimari ve gerekçeleri [README](README.md#mimari)'de. İlk karşılaşacakların:

- **`core/` saf mantıktır; Flutter ya da herhangi bir arayüz kodu import etmez.**
  `test/core_purity_test.dart` bunu zorlar. `features/` arayüzü çizer ve
  `core/`'u çağırır; kendi başına hesap yapmaz.
- **İzleme günü gece yarısında başlamaz.** `day_start_hour`'da (varsayılan
  04:00) başlar. Tüm tarih hesapları `core/date_utils.dart`'taki `dayOf()`'tan
  geçer, arayüz "bugün"ü `todayProvider`'dan okur. Ham `DateTime.now()`'dan gün
  üretme.
- **Her migration adımı idempotent olmalı:** sütun ya da tabloyu eklemeden önce
  varlığını kontrol et. Bu gerçek bir arızadan geliyor (yarım uygulanan bir
  yükseltme veritabanını kalıcı olarak kilitledi). `test/migration_test.dart`
  bunu tutuyor. Şema değişikliği `schemaVersion`'ı da artırır.
- **Üretilen kod commit'lenir.** drift tablolarını değiştirince
  `dart run build_runner build` çalıştır ve güncellenen `database.g.dart`'ı ekle.
- **Kod ve doc yorumları İngilizce; kullanıcıya görünen metinler Türkçe.**
  Yorum *neden*'i anlatır, *ne*'yi değil.
- **Yeni davranış bir testle gelir**, `test/` altında mevcut olanların yanında.

### Pull request'ler

- Küçük ve tek konulu tut. İlgili issue'yu bağla.
- Değiştirdiğin davranışı anlatan yerlerde README'yi güncelle.
- Derleme çıktısı, yerel dosya ya da kişisel veri commit'leme.
- Katkıda bulunarak çalışmanın [MIT Lisansı](LICENSE) ile yayımlanmasını kabul
  edersin.
