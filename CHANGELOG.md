# Değişiklikler

Eski sürümlerin notları GitHub Releases sayfasındadır.

## 1.4.1 (2026-11-11)

- Yeni uygulama ve tepsi ikonu (yeni logo). Kaynak `assets/marka/habit-tracker-logo.png`;
  `python tool/ikon_uret.py` ikonları yeniden üretir. Tepsi ikonunda küçük boyutlarda
  (16-32 px) glow kısıldı, çizgiler kalınlaştırıldı.

## 1.4.0 (2026-11-10)

- **Telefonla senkron**: iki yönlü, son değişiklik kazanır, silmeler taşınır, tekrar
  uygulamak güvenlidir. İki yol: `.habitsync` dosyası (kurallar `docs/senkron.md`) ve
  Wi-Fi + QR eşleştirme (aşağıda).
- **QR + Wi-Fi eşleştirme**: Ayarlar > "Telefonla eşleştir (Wi-Fi)". Geçici HTTPS sunucu,
  sertifika parmak izi QR'da, tek kullanımlık jeton, 3 dakika süre, yalnız özel ağ
  adresleri, masaüstünde iki onay (telefon kimliği, veri özeti) ve birleştirmeden önce
  yerel yedek. Bulut ve hesap yok. Ayrıntı: `docs/wifi-senkron.md`.
- **Uygulama içi güncelleme**: Ayarlar'da Güncelleme bölümü; zip SHA-256 ile, `SHA256SUMS.txt`
  ise Ed25519 imzasıyla doğrulanır (`SHA256SUMS.txt.sig`); imzasız ya da bozuk imzalı sürüm
  kurulmaz. `release.yml` imzayı `HABIT_UPDATE_SIGNING_KEY` sırrıyla üretir. Ayrıntı:
  `docs/guncelleme-imzasi.md`. Yeni bağımlılık: `pinenacl` 0.6.0 (saf Dart).
- **Veritabanı şeması v5**: `uid`, `updated_at`, silinenler tablosu ve tetikleyiciler. Mevcut
  veri korunur; v1, v2, v3 ve v4 veritabanları yükseltilir (gerçek kullanıcı veritabanı
  kopyalarıyla denendi).
- **JSON yedek biçimi v5** (uid, updatedAt, silinenler). v1-v4 yedekleri okunmaya devam eder.
- Düzeltme: v1 şemasından yükseltme `value` sütunu yüzünden hata veriyordu; artık tamamlanır.
- Düzeltmeler (inceleme): yinelenen `Authorization` başlığı, jeton yarışı, "işleniyor" süresi,
  port aralığı, sıralama damgası, güncelleyici hata mesajı.
- CI ve release iş akışlarında Flutter 3.47.5'e sabitlendi; PR şablonuna "mobilde
  `esitle.ps1` çalıştır" maddesi eklendi.
