<!-- English or Turkish, both are fine. / Türkçe ya da İngilizce, ikisi de olur. -->

## What and why · Ne ve neden

<!-- One or two sentences. Link the issue: "Closes #123". -->
<!-- Bir iki cümle. İlgili issue'yu bağla: "Closes #123". -->

## Checklist · Kontrol listesi

- [ ] I opened or found an issue for this and it fits the app's local-only scope (no server, account, login or cloud sync). / Bunun için bir issue var ve uygulamanın yalnızca-yerel kapsamına uyuyor.
- [ ] `flutter analyze`, `flutter test` and `flutter build windows --release` pass. / Üçü de geçiyor.
- [ ] New behaviour has its own test in `test/`. / Yeni davranışın `test/` altında kendi testi var.
- [ ] `core/` still imports nothing from Flutter or UI code (`core_purity_test.dart` passes). / `core/` hâlâ Flutter ya da arayüz kodu import etmiyor.
- [ ] Dates go through `dayOf()` / `todayProvider`, not a raw `DateTime.now()`. / Tarihler `dayOf()` / `todayProvider`'dan geçiyor.
- [ ] If I changed the schema: `schemaVersion` is bumped, the migration step is idempotent, and `database.g.dart` is regenerated and included. / Şema değiştiyse: `schemaVersion` artırıldı, migration idempotent, `database.g.dart` yeniden üretilip eklendi.
- [ ] If I changed `lib/core/` or `lib/data/` (database, repositories, sync): `tool/esitle.ps1` must be run in the mobile app (`habit-tracker-mobil`) too. / `lib/core/` ya da `lib/data/` (veritabanı, repository, senkron) değiştiyse mobil uygulamada (`habit-tracker-mobil`) `tool/esitle.ps1` çalıştırılmalı.
- [ ] README updated where it describes the changed behaviour. / Değişen davranışı anlatan yerlerde README güncellendi.
- [ ] No build output, local files or personal data in the diff. / Diff'te derleme çıktısı, yerel dosya ya da kişisel veri yok.
