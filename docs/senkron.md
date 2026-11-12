# Habit Tracker senkron dosyası (`.habitsync`): biçim ve birleştirme kuralları

> **Durum: v1.4.0 için yazıldı** (sürüm hazırlanıyor; etiket ve yayın henüz yok).
> Mobil uygulama (`habit-tracker-mobil`) aynı kuralları kopyalar; kurallar
> **yalnız burada** yazılır, iki taraf bu belgeye uyar.

Masaüstü ve mobil bu belgedeki tek biçimi konuşur. Ağ, hesap ve sunucu yok: kullanıcı
dosyayı kendisi taşır (Paylaş, USB, Drive, Bluetooth). Her dışa aktarma **tam durumdur**
(delta değil). İçe aktarma, dosyadaki her kaydı yerelle birleştirir. Aynı dosyayı iki kez
içe aktarmak hiçbir şeyi değiştirmez (idempotent). Kural kaynağı Takvim'in `senkron.md`
dosyasıdır; burada bu verinin şekline uyarlanmıştır.

## 1. Dosya

UTF-8 JSON, uzantı `.habitsync`. Anahtarlar İngilizce, alt çizgili küçük harf.

```json
{
  "format": "habit-sync",
  "version": 1,
  "created_at": "2026-11-10T09:30:00Z",
  "device": {"name": "Masaüstü", "app": "habit-tracker-desktop"},
  "settings": {
    "day_start_hour": {"value": 4, "updated_at": "2026-11-01T08:00:00Z"}
  },
  "habits": [
    {"uid": "…", "name": "Kitap", "description": null, "color_value": 4283215696,
     "icon_code_point": 57344, "category": "zihin", "kind": "bool", "target": 1,
     "created_at": "…", "archived_at": null, "sort_order": 0,
     "scheduled_weekdays": "1,3,5", "updated_at": "…"}
  ],
  "entries": [
    {"habit_uid": "…", "date": "2026-11-09", "status": "done", "value": 1,
     "created_at": "…", "updated_at": "…"}
  ],
  "moods": [
    {"date": "2026-11-09", "mood": 4, "note": null, "created_at": "…", "updated_at": "…"}
  ],
  "tasks": [
    {"uid": "…", "title": "Rapor", "status": "todo", "priority": 1, "due_day": null,
     "created_at": "…", "completed_at": null, "updated_at": "…"}
  ],
  "sessions": [
    {"uid": "…", "kind": "focus", "started_at": "…", "ended_at": "…", "duration_s": 1500,
     "day": "2026-11-09", "task_uid": null, "updated_at": "…"}
  ],
  "deleted": [
    {"kind": "entry", "key": "<habit uid>|2026-11-08", "deleted_at": "2026-11-09T07:00:00Z"}
  ]
}
```

- Zamanlar her zaman UTC ve **sabit genişlikli** `YYYY-MM-DDTHH:MM:SSZ` (saniye
  hassasiyeti, kesir yok). Gün alanları (`date`, `day`, `due_day`) `YYYY-MM-DD`.
- `uid`: 1–64 karakter, `[A-Za-z0-9._:@-]`. Uygulamalar UUID v4 üretir.
- Anahtarlar: alışkanlık, görev ve seans için `uid`; hücre için `habit_uid|date`; mood için
  `date`. `deleted[].kind`: `habit` | `entry` | `mood` | `task` | `session`;
  `deleted[].key` o türün anahtarıdır.
- Enum değerleri: hücre `status` `done` | `missed` | `skipped`; alışkanlık `kind` `bool` |
  `count`; görev `status` `todo` | `doing` | `done`, `priority` 0–2; seans `kind` `focus` |
  `break`; `mood` 1–5.
- Dosyaya **konmayanlar** (cihaza özel): tema, hatırlatıcı saati ve `focus_running`, pencere
  konumu, yerel tamsayı `id`'ler. `Settings`'ten yalnız `day_start_hour` taşınır.
- Bilinmeyen alanlar yok sayılır (ileri uyum). `version` bilinenden büyükse dosya reddedilir
  ("uygulamayı güncelle"). Baştaki UTF-8 BOM kabul edilir.

## 2. Sınırlar

İki uygulama da bunları **aynen** uygular; aşan dosya reddedilir, hiçbir şey değişmez. Sabit
adları kodla aynıdır (`lib/data/sync/sync_format.dart`); bir test bu tabloyu kodla karşılaştırır.

| Sabit | Değer | Anlamı |
|---|---|---|
| `syncMaxFileBytes` | 16777216 | Dosya boyutu, bayt (16 MiB). Çözmeden önce denetlenir. |
| `syncMaxRecords` | 250000 | Dosyadaki toplam kayıt: alışkanlık + hücre + mood + görev + seans + silinen. |
| `syncMaxHabits` | 10000 | Dosyadaki alışkanlık sayısı. Eşleştirme ikinci dereceden olduğu için tür başına sınır şart. |
| `syncMaxTasks` | 10000 | Dosyadaki görev sayısı. Aynı gerekçe. |
| `syncMaxFutureSecs` | 86400 | `updated_at` / `deleted_at` içe aktaran cihazın saatinden en çok bu kadar ileride olabilir (1 gün). Daha ilerisi LWW'yi kalıcı zehirler. |
| `syncMaxJsonDepth` | 8 | En çok iç içe `[`/`{` düzeyi. Gerçek dosya 3 düzeydir. Metin çözülmeden sayılır. |
| `syncMaxTextLength` | 10000 | Serbest metin (açıklama, not) uzunluğu, UTF-16 birimi. |
| `syncMaxHabitName` | 100 | Alışkanlık adı. Tablo kısıtıyla aynı. |
| `syncMaxTaskTitle` | 200 | Görev başlığı. Tablo kısıtıyla aynı. |
| `syncMaxCount` | 1000000000 | `target` ve hücre `value` üst sınırı. Arayüz girişi aynı sınırla kısılır. |

Ek olarak sayısal alanların aralıkları vardır: `target` 1–10⁹, hücre `value` 0–10⁹,
`duration_s` 0–604800 (7 gün), `sort_order` ±10⁶, `day_start_hour` 0–12, `color_value`
0–0xFFFFFFFF.

## 3. Doğrulama (iki taraf da uygular)

Dosya, veritabanına dokunulmadan önce baştan sona denetlenir; **tek kayıt bozuksa dosyanın
tamamı reddedilir**. Denetimler: biçim ve sürüm; sınırlar (§2); her türde yinelenen anahtar
(aynı `uid`, aynı `habit_uid|date`, aynı mood günü, aynı silinen); zorunlu alanlar ve türleri;
enum değerleri; gerçek takvim günü (`2026-02-31` reddedilir); zaman biçimi; `scheduled_weekdays`
için `1,3,5` biçimi; uzunluklar; `updated_at` ve `deleted_at` değerlerinin gelecekte olmaması (`syncMaxFutureSecs`). Gelecek damgalı dosya kırpılmaz, reddedilir: kırpılırsa aynı dosyayı iki kez içe aktarmak değişiklik yapardı. Reddedilen dosya ya da içe aktarma sırasındaki herhangi bir
hata **hiçbir şeyi değiştirmez**: birleştirme tek transaction'da çalışır.

## 4. Birleştirme (içe aktarma)

Anahtar her yerde `uid` ya da doğal anahtardır (yerel tamsayı id'ler cihazdan cihaza farklıdır).

**Sıra:** ayar → alışkanlıklar → görevler → hücreler → mood'lar → seanslar → silinenler.
Silinenler en sonda uygulanır.

**Kayıt kuralı (son yazan kazanır, LWW):** aynı anahtar için yerel `updated_at` ile dosyadaki
`updated_at` karşılaştırılır. Dosyadaki *kesin olarak* yeniyse yerel kayıt dosyadakiyle
değiştirilir; eşit ya da eskiyse yerel kalır. Yerelde yoksa eklenir. İçe aktarılan kaydın
yerel `updated_at`'i **dosyadaki değer** olur ("şimdi" yazılmaz); böylece aynı dosyayı tekrar
içe aktarmak hiçbir şeyi değiştirmez.

**Silme kuralı:**
- Yerelde kayıt var, dosyanın `deleted` listesinde de var: `deleted_at`, yerel `updated_at`'ten
  **kesin olarak** yeniyse yerel kayıt silinir. Eşitlikte ya da kayıt daha yeniyse **kayıt
  kalır** (veri kaybetmemek için).
- Yerelde silme izi var, dosyada kayıt canlı geliyor: kaydın `updated_at`'i silme izinin
  `deleted_at`'inden küçükse kayıt eklenmez (silinmiş kalır); eşit ya da büyükse kayıt
  canlanır ve silme izi kalkar.
- Silmeyi uygularken yerel silme izine **dosyadaki `deleted_at`** yazılır (şimdi değil), yoksa
  silme cihazlar arasında sonsuza dek yankılanır. İz zaten daha yeniyse dokunulmaz.

**Silinenler (mezar taşları):** her cihaz sildiklerini kalıcı tutar; budama yok (satırlar çok
küçük). İzler `silinenler(kind, anahtar, deletedAt)` tablosunda, SQLite tetikleyicileriyle
tutulur (§6).

**Alışkanlık silinince** hücreleri de gider (CASCADE). Hücreler için ayrı iz yazılmaz; alışkanlığın
izi yeter. Karşı taraftan gelen o alışkanlığın hücreleri, alışkanlık yerelde silinmişse **atlanır**.

**Görev ↔ seans:** görevler seanslardan önce işlenir. Seans, görevi `task_uid` ile taşır;
`task_uid` yerelde yoksa ya da görev silinmişse seansın görevi boş (`taskId` null) olur; seans
silinmez. Bir görev silinince yerel seansları da görevsiz kalır (mevcut kural).

**Yetim hücre:** `habit_uid` ne dosyada ne yerelde bulunan hücre eklenmez; "atlandı" sayılır.

**Gün başlangıç saati:** `day_start_hour` tek bir alan olarak LWW ile birleşir; yerel damga
`Settings` içindeki `dayStartHourUpdatedAt` satırındadır (tetikleyici tutar). Hiç ayarlanmamış
cihaz (damga yok) diğerinin değerini ezmez; sürüm yükseltme sırasında mevcut bir değer o anın
damgasını alır.

**Sonuç raporu:** türe göre `{eklenen, güncellenen, silinen, atlanan}` ve ilk eşleştirmede
benimsenen kayıt sayısı. Arayüz tek satır özet gösterir.

## 5. İlk eşleştirme (uid yokken)

Veri JSON yedekle taşınmışsa iki taraf v5'e ayrı ayrı çıkar ve **farklı rastgele uid**'ler alır.
Bu durumda ilk senkron kayıtları ikilememelidir. Dosyadaki `uid` yerelde bulunamazsa (ve yerelde
o uid için silme izi yoksa), yerel satır mevcut yedek eşleme mantığıyla aranır:

- **Alışkanlık ve görev:** aynı ad/başlık **ve** aynı saniyedeki `created_at` (`_findKnown`
  mantığı).
- **Seans:** `kind + started_at + duration_s + day` (`_sessionKey`).

Eşleşen satır **dosyadaki uid'i benimser** (uid değişir, `updated_at` değişmez, ikinci bir kopya
oluşmaz); ardından normal LWW uygulanır. Dosyanın kendi uid'lerinden birine sahip yerel satırlar
ve bu içe aktarmada zaten benimsenmiş satırlar aday sayılmaz. Benimseyen alışkanlığın "boşa
çekilmiş hücre" izleri yeni uid'e taşınır. Hücreler ve mood'lar doğal anahtarla (`habit_uid|date`,
`date`) eşleştiği için ek kurala gerek yoktur.

Adı aynı ama `created_at` saniyesi farklı iki alışkanlık **iki ayrı** alışkanlıktır.

## 6. Veritabanı şeması v5 (masaüstü ve mobilde aynı migration)

- **uid:** `habits`, `tasks`, `focus_sessions` tablolarına `uid TEXT` (nullable; SQLite `ADD
  COLUMN` ile UNIQUE eklemeye izin vermez). Mevcut satırlar `UPDATE` ile UUID v4 alır, ardından
  `CREATE UNIQUE INDEX IF NOT EXISTS` çalışır. Tablo tanımı aynı index adlarını kullanır
  (`habits_uid_idx`, `tasks_uid_idx`, `focus_sessions_uid_idx`); taze kurulum ile yükseltilmiş
  kurulum aynı şemayı verir (`test/migration_v5_test.dart` karşılaştırır). Yeni satırların uid'ini
  `AFTER INSERT` tetikleyicisi üretir; hiçbir yazma yolu unutamaz.
- **updated_at:** beş tabloda (`habits`, `habit_entries`, `mood_entries`, `tasks`,
  `focus_sessions`) `INTEGER NOT NULL DEFAULT 0` (unix saniyesi); mevcut satırlarda `created_at`
  (görevde `completed_at`, seansta `ended_at`) ile doldurulur. `AFTER INSERT` tetikleyicisi 0
  gelen değeri "şimdi" yapar; `AFTER UPDATE` tetikleyicisi, `updated_at` ve `uid` değişmeden
  yapılan bir yazmada "şimdi" yazar. Senkron içe aktarma `updated_at`'i açıkça verdiği için
  tetikleyiciye takılmaz; uid benimsemek de damgayı oynatmaz.
- **silinenler:** `silinenler(kind, anahtar, deleted_at, PRIMARY KEY(kind, anahtar))`. Beş
  tablonun `AFTER DELETE` tetikleyicileri doldurur; aynı anahtarla yeni kayıt eklenince
  `AFTER INSERT` tetikleyicisi izi siler. Hücre anahtarı `habit_uid|date`; alışkanlık zaten
  silinmişse (cascade) hücre için iz yazılmaz.
- **Tetikleyici metni** tek yerde durur: `lib/data/database/sync_schema.dart`. Mobil bu dosyayı
  olduğu gibi kopyalar. Tetikleyicilerde `INSERT OR REPLACE` kullanılmaz (dıştaki upsert'in
  çakışma kipi onu ezer); upsert yazılır.
- **Idempotent migration:** her adım yapmadan önce sütun/tablo/index var mı diye bakar; yarım
  kalmış bir yükseltme bir sonraki açılışta tamamlanır. v1→v5, v2→v5, v3→v5, v4→v5 hepsi test
  edilir.

## 7. Yedek biçimi v5 (JSON yedek, `.habitsync` değil)

`backupVersion` 5. Yedek `uid`, `updatedAt` (alışkanlık, hücre, mood, görev, seans), `habitUid`
(hücre), `taskUid` (seans) alanlarını ve üst düzey `deleted` listesini (`kind`, `key`,
`deletedAt`) taşır.

- v1–v4 yedekleri okunmaya devam eder; uid'siz satırlar §5'teki ilk eşleştirmeyle sonra
  eşleşir.
- **Tamamen değiştir:** v5 yedekte uid ve `updatedAt` değerleri korunur; `deleted` listesi geri
  yazılır (dosyada hâlâ canlı olanlar hariç). Yedekte olmayan satırların silme izi kalır: geri
  yükleme sonrası senkron onları karşı taraftan da siler. v1–v4 yedekte satırlar yeni uid alır,
  sonraki senkron §5 ile ikilemeden eşleştirir.
- **Birleştir:** `updatedAt` dosyadaki değerde bırakılır; "şimdi" yazılmaz, yoksa eski yedek
  yeni veriyi ezerdi. Eşleşme önce `uid` ile, yoksa mevcut kuralla yapılır. `deleted` listesi
  birleştirmede **uygulanmaz** (birleştirme yalnız ekler/günceller). v1–v4 dosyasında `updatedAt`
  yoktur; eşleşen satır güncellenince şimdiki zamanı alır.
- Yedek sürümü bilinenden büyükse içe aktarma reddedilir.

## 8. Gün başlangıç saati hakkında not

Bir işaretin hangi güne düştüğü gün başlangıç saatine (varsayılan 04:00) bağlıdır. İşaretler
dosyada **gün metniyle** (`2026-11-09`) gider, saatle değil; yani gece yapılan bir işaret iki
cihazda aynı güne yazılır. Ama iki cihazda saat farklıysa gece yapılan *yeni* işaretler farklı
güne düşer. Bu yüzden ayar da senkronlanır (LWW); bir senkrondan sonra iki cihaz aynı saati
kullanır. Bir cihazda saati değiştirmek eski kayıtların gününü değiştirmez.

## 9. Bilinen sınırlar

- **Saat farkı:** iki cihazın saati birbirinden farklıysa "son yazan" yanılabilir. Kabul
  edilmiştir; v1'de çözülmez.
- **Saniye çözünürlüğü, eşit damga:** aynı saniyede iki cihazda yapılan farklı düzenlemede her
  taraf kendi değerini korur (kalıcı ayrışma olabilir; sonraki düzenleme düzeltir). Silme/düzenleme
  eşitliğinde kayıt kalır.
- **Görev silinince** seansların `updated_at`'i yerelde "şimdi" olur (FK `SET NULL` bir
  güncellemedir). Bu zararsızdır; içerik aynıdır, bir tur fazladan "güncellendi" sayılabilir.
- **Silinenler tablosu büyür** (budama yok). Satır başına birkaç on bayt.
- Silmeyi uygularken karşı tarafın o kayıt için hiç izi yoksa, iz yine de yazılır (üçüncü bir
  cihaza silmeyi taşımak için).
- `.habitsync` yalnız kullanıcı verisini taşır; ayarlardan sadece gün başlangıç saati.

## 10. Masaüstü arayüzü

"Yedek & Ayarlar" ekranında "Telefonla senkron: dosya dışa/içe aktar" bölümü: iki düğme
("Telefon için dışa aktar", "Telefondan içe aktar") ve sonuç özeti (tek satır). Yeni sekme yok.
Dosya adı `habit-YYYYMMDD-SSDD.habitsync`.

## 11. Testler

`test/migration_v5_test.dart` (migration, şema eşitliği, tetikleyiciler, gerçek veri kopyası),
`test/sync_test.dart` (biçim/doğrulama, Takvim a–f senaryolarının uyarlaması, ek senaryolar,
ölçek), `test/sync_purity_test.dart` (sync kodu Flutter import etmez, sınırlar bu belgeyle aynı).
