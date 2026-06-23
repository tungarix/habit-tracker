# Aktenak Habit Tracker — Proje Blueprint'i

> Bu belge Claude Code'a doğrudan verilebilir. Repo köküne `BLUEPRINT.md` olarak koy.
> Amaç: etkileyici değil, **her gün açılıp kullanılacak** bir uygulama.

---

## 0. Tasarım İlkesi (en önemli kısım)

Bu projenin başarısı koddan değil, **sürtünmesizlikten** gelir. Her karar şu testten geçmeli:

> "Bu özellik, uygulamayı her gün açıp kullanmamı kolaylaştırıyor mu, yoksa kurulumu/bakımı mı artırıyor?"

Bu yüzden:
- **Backend yok.** Sunucu, hesap, login yok. Sıfır bakım.
- **Cihazlar arası taşıma = JSON yedek dosyası.** Sync değil, dosya. İstediğin an dışa aktar, başka cihazda içe aktar.
- **MVP gerçekten minimum.** Önce her gün kullanılabilen tek bir ekran, sonra süsler.

---

## 1. Kapsam

### MVP'de VAR
- Alışkanlık oluşturma / düzenleme / arşivleme (ad, açıklama, renk, ikon)
- Günlük **evet/hayır** işaretleme (yaptım / yapmadım)
- **Streak** (mevcut seri) ve **en uzun seri**
- **İstatistik & grafik**: tamamlanma oranı, takvim ısı haritası (heatmap), zaman içinde trend
- **JSON dışa/içe aktarım** (yedek + cihazlar arası taşıma)
- Masaüstü (Windows + Linux) hedefi

### MVP'de YOK (sonraki fazlar)
- Sayısal hedefler (30 dk, 50 şınav vb.) — Faz sonrası
- Çok cihaz canlı sync, bulut, hesap sistemi
- Bildirim/hatırlatma — Faz sonrası
- Android/iOS build — kod tabanı zaten hazır olacak, sadece derleme fazı

---

## 2. Teknoloji Yığını

| Katman | Seçim | Neden |
|---|---|---|
| Framework | **Flutter** (Dart) | Tek kod tabanı → masaüstü + sonra mobil. Dart'ı zaten biliyorsun. |
| İlk hedef | **Windows + Linux desktop** | Senin önceliğin. |
| Veritabanı | **drift** (SQLite üstüne, tip-güvenli, reaktif) | Reaktif sorgular grafik/streak için ideal. Masaüstünde `sqlite3_flutter_libs` ile sorunsuz. |
| State yönetimi | **Riverpod** | Test edilebilir, temiz. (İstemezsen `provider` da olur.) |
| Grafik | **fl_chart** | Bar, line ve özel heatmap için yeterli. |
| Dosya işlemleri | **file_picker** + **path_provider** | JSON yedek kaydet/yükle. |

`pubspec.yaml` ana bağımlılıklar:
```yaml
dependencies:
  flutter:
    sdk: flutter
  drift: ^2.x
  sqlite3_flutter_libs: ^0.5.x
  path_provider: ^2.x
  path: ^1.x
  flutter_riverpod: ^2.x
  fl_chart: ^0.69.x
  file_picker: ^8.x
  intl: ^0.19.x

dev_dependencies:
  drift_dev: ^2.x
  build_runner: ^2.x
```

---

## 3. Veri Modeli

İki tablo yeter.

**habits**
| alan | tip | not |
|---|---|---|
| id | INTEGER PK | otomatik |
| name | TEXT | zorunlu |
| description | TEXT? | opsiyonel |
| colorValue | INTEGER | ARGB int |
| iconCodePoint | INTEGER | ikon |
| createdAt | DATETIME | |
| archivedAt | DATETIME? | null = aktif |
| sortOrder | INTEGER | sıralama |
| scheduledWeekdays | TEXT | örn "1,2,3,4,5" (boşsa her gün) |

**habit_entries** (her gün için bir kayıt)
| alan | tip | not |
|---|---|---|
| id | INTEGER PK | |
| habitId | INTEGER FK → habits.id | |
| date | TEXT (YYYY-MM-DD) | gün |
| done | BOOLEAN | |
| createdAt | DATETIME | |

> **Benzersiz kısıt:** `(habitId, date)` — bir alışkanlığa bir günde tek kayıt.

### Streak mantığı
- **Mevcut seri:** bugünden geriye doğru, planlı günlerde kesintisiz `done = true` sayısı.
- **En uzun seri:** tüm geçmişte en uzun kesintisiz dizi.
- Planlı olmayan günler seriyi **bozmaz** (atlanır).

---

## 4. JSON Yedek Formatı (dış çıktı)

Dışa aktarım = tek bir `.json` dosyası. İçe aktarım bunu okur (mevcut veriyle birleştirir veya değiştirir — kullanıcıya sor).

```json
{
  "format": "aktenak-habit-tracker",
  "version": 1,
  "exportedAt": "2026-06-23T10:00:00Z",
  "habits": [
    {
      "id": 1,
      "name": "Sabah egzersizi",
      "description": "Şınav + bar",
      "colorValue": 4280391411,
      "iconCodePoint": 58126,
      "createdAt": "2026-06-01T08:00:00Z",
      "archivedAt": null,
      "sortOrder": 0,
      "scheduledWeekdays": "1,2,3,4,5"
    }
  ],
  "entries": [
    { "habitId": 1, "date": "2026-06-20", "done": true },
    { "habitId": 1, "date": "2026-06-21", "done": false }
  ]
}
```

İçe aktarımda iki seçenek sun: **Birleştir** (aynı tarih+habit varsa üzerine yaz) veya **Tamamen değiştir**.

---

## 5. Ekranlar

1. **Bugün** (ana ekran) — bugünün alışkanlık listesi, her birinin yanında işaret kutusu + mevcut seri rozeti. Tek dokunuşla yaptım/yapmadım.
2. **Alışkanlıklar** — liste + ekle/düzenle/arşivle.
3. **İstatistik** — bir alışkanlık seç → heatmap (takvim), tamamlanma oranı, trend grafiği, mevcut/en uzun seri.
4. **Yedek** — Dışa aktar / İçe aktar butonları.

Navigasyon: masaüstünde sol kenar `NavigationRail` (4 sekme).

---

## 6. Klasör Yapısı

```
lib/
  main.dart
  app.dart
  core/
    theme.dart
    constants.dart
    date_utils.dart
  data/
    database/
      database.dart        # drift @DriftDatabase
      tables.dart          # Habits, HabitEntries
      daos/
    repositories/
      habit_repository.dart
      backup_repository.dart   # JSON export/import
    models/
  features/
    today/
    habits/
    stats/
      widgets/heatmap.dart
    backup/
  shared/
    widgets/
```

---

## 7. Yol Haritası (faz faz — her fazı bitince KULLAN, sonra devam et)

- **Faz 0 — İskelet.** `flutter create`, masaüstü etkinleştir, drift kur, tema, boş 4 sekme. Çalışan boş uygulama.
- **Faz 1 — MVP (asıl hedef).** Habit CRUD + Bugün ekranında evet/hayır işaretleme + streak rozeti. **Burada dur ve birkaç gün gerçekten kullan.**
- **Faz 2 — İstatistik.** Heatmap + tamamlanma oranı + en uzun seri + trend grafiği.
- **Faz 3 — Yedek.** JSON dışa/içe aktarım.
- **Faz 4 — Mobil & ekstralar.** Android build, hatırlatma bildirimi, sayısal hedefler (gerçekten istersen).

> Kural: Faz 1 günde açılıp kullanılmıyorsa Faz 2'ye geçme. Sürdürülebilirlik testini geçemeyen özellik eklenmiyor.

---

## 8. Claude Code ile Çalışma

### Kurulum
```bash
flutter create aktenak_habit_tracker
cd aktenak_habit_tracker
flutter config --enable-windows-desktop --enable-linux-desktop
# Bu BLUEPRINT.md dosyasını repo köküne kopyala
git init && git add . && git commit -m "Faz 0: iskelet"
```

### Claude Code'a verecek ilk prompt (örnek)
> "BLUEPRINT.md'yi oku. Faz 0'ı uygula: pubspec bağımlılıklarını ekle, drift veritabanını `tables.dart` ve `database.dart` ile kur, 4 sekmeli boş NavigationRail iskeletini ve temel temayı oluştur. build_runner'ı çalıştır ve `flutter run -d windows` (veya linux) ile derlenir hale getir."

### Çalışma disiplini
- **Her fazı ayrı commit et.** Faz biter → çalıştır → commit → sonraki faz.
- Her fazda Claude Code'a "BLUEPRINT.md'deki Faz N'i uygula" de; o belgeyi referans alsın.
- Bir şey çalışmazsa Claude Code'a hata çıktısını yapıştır, baştan yazdırma.
- Faz 1 bitince **gerçekten kullan**. Eksik gördüğün ufak şeyleri not al, Faz 2'ye onları taşı.

---

*Aktenak — yerel-öncelikli, sahip olduğun veri, sürdürülebilir araç.*
