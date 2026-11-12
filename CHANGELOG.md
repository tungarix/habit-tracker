# Değişiklikler

Eski sürümlerin notları GitHub Releases sayfasındadır.

## 1.4.4 (2026-11-12)

- Tepsi simgesine sağ tıklayınca menü açılıyor: Çıkış menüsü hiç açılmıyordu, bu yüzden uygulama
  tepsideyken kapatılamıyordu. (nativeapi menüyü varsayılan olarak kapalı tutuyor; açıkça açıldı.)

## 1.4.3 (2026-11-12)

- Ekran okuyucu: bugün satırında hedefin altındaki kısmi miktar "yapılmadı" yerine
  "devam ediyor" okunur (gün bitmedi).

## 1.4.2 (2026-11-12)

Kod incelemesi turu: yeni özellik yok, hata düzeltmeleri.

- Seri: sayılabilir alışkanlıkta bugün girilen kısmi miktar seriyi artık sıfırlamıyor.
- Panel: odak sayacı pencere daralınca kaybolmuyor, süre duvar saatiyle ölçülüyor ve plandan
  uzun yazılmıyor; hafta yüzdesi atlanan günleri saymıyor.
- Windows'ta akşam hatırlatıcısı çalışıyor: nativeapi bildirimi bu yapıda kapalıydı (WinUI3),
  hatırlatıcı artık Windows toast'ı ile gösterilir (`lib/shared/windows_bildirim.dart`).
- Uygulama ikinci kez açılınca yeni kopya başlamaz, açık pencere öne gelir.
- Görevde Sil onay ister; tepsiden Çıkış çalışan odak seansını kaydeder; alışkanlığın hedefi
  düşünce yeni hedefe ulaşmış eski ✗ günler ✓ olur.
- Ad, başlık, açıklama ve miktar alanları senkron sınırlarıyla aynı sınırlara bağlandı.
- Yedek: bozuk tarihli JSON yedek reddedilir; otomatik yedek yeni yazdığı dosyayı budamaz.
- Aynı hücreye iki hızlı tıklama hata vermez; ısı şeridinde ✓ günü her zaman dolu görünür.
- Wi-Fi eşitleme ve güncelleme ekranı beklenmedik hatada takılı kalmaz.
- Tepsi yoksa X düğmesi pencereyi erişilmez bırakmaz; simge durumundaki pencere tepsiden açılır.
- Ekran okuyucu: bugün satırı ve ızgara hücreleri durumu okur.

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
