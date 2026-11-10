# Değişiklikler

Bu dosya yeni tutulmaya başlandı; eski sürümlerin notları GitHub Releases sayfasındadır.

## Yayımlanmadı: taslak (1.4.0 adayı)

> **Bu sürüm çıkmadı.** Aşağıdakiler `mobil-senkron-v5` dalında hazırlanıyor; sürüm numarası,
> etiket ve yayın Arda'nın kararıdır. `pubspec.yaml` sürümü bilerek değiştirilmedi.

- Telefonla senkron: `.habitsync` dosyası ile iki yönlü, son değişiklik kazanır (Ayarlar'da
  iki düğme). Kurallar: `docs/senkron.md`.
- Veritabanı şeması v5: `uid`, `updated_at`, silinenler tablosu ve tetikleyiciler. Mevcut veri
  korunur; v1, v2, v3 ve v4 veritabanları yükseltilir.
- JSON yedek biçimi v5 (uid, updatedAt, silinenler). v1–v4 yedekleri okunmaya devam eder.
- Düzeltme: v1 şemasından yükseltme `value` sütunu yüzünden hata veriyordu (v1 veritabanında
  `habit_entries.value` yok); artık yükseltme tamamlanır.
- CI ve release iş akışlarında Flutter sürümü 3.47.5'e sabitlendi; PR şablonuna "mobilde
  `esitle.ps1` çalıştır" maddesi eklendi.
