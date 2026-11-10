# Faz 4 tasarımı: QR + Wi-Fi senkron ve masaüstü uygulama içi güncelleme

> **Durum: tasarım; masaüstü tarafı v1.4.0 için uygulandı** (`lib/core/wifi_sync/`, `lib/features/eslestir/`), yayımlanmadı. Aşağıdaki "doğrulanmadı" notları tasarım anındandır. Bu belge şunlara
> dayanır: mobil `PLAN.md`, `SABAH-OZET.md`, `tool/spike_tls/` (ve `docs/gece-raporu/04b-tls-spike.md`),
> mobil `lib/platform/guncelleme/*`, masaüstü v5 çalışma kopyası (`docs/senkron.md`, `lib/data/sync/*`,
> `.github/workflows/release.yml`, `windows/`), Takvim'in `docs/senkron-wifi.md` protokolü. Dosyalar
> okundu; "doğrulanmadı" yazan her şey denenmemiştir. Yayımlamaya, imza anahtarına, GitHub'a dokunulmaz.

İçindekiler: 0 Kararlar · A QR + Wi-Fi senkron (A1-A10) · B Masaüstü güncelleyici (B1-B7) ·
C Dosya bölümü · D Testler ve ortak sözleşme · E İş sırası, açık kararlar, denenmeyenler.

## 0. Kararlar ve PLAN'dan sapmalar

| Konu | Karar | Neden |
|---|---|---|
| QR'ı kim okur | Uygulamanın kendi tarayıcısı (`mobile_scanner`) + yedek olarak bağlantıyı yapıştırma | PLAN'daki App Link (`aktenak.tech/h#...`) site tarafı (`assetlinks.json`), imza parmak izi ve uzaktan tetiklenebilir bir derin bağlantı gerektirir. Uygulama içi tarama bunların hiçbirini istemez; bağlantı yalnız kullanıcı "QR'ı tara"ya basınca işlenir. |
| Kamera izni | `CAMERA` eklenir, yalnız "QR'ı tara"ya basınca istenir | PLAN "kamera izni yok" diyordu; bu madde değişir (`PLAN.md` Faz 2 §5 ve Faz 4 güncellenmeli). Tarama dışında kamera hiç açılmaz. |
| Jeton | Gerçekten **tek kullanımlık**: ilk `POST /v1/session` jetonu yakar, sonraki istekler oturum anahtarıyla gider | Takvim'de jeton oturum boyunca geçerliydi. Burada QR'ın fotoğrafı ilk bağlantıdan sonra işe yaramaz. |
| Masaüstü onayı | İki yerde: (1) telefon bağlanınca "bu senin telefonun mu?", (2) telefondan gelen veri için özet + onay | (1) QR ekranını gören biri (ekran paylaşımı, omuz üstü) masaüstünün verisini çekemesin. |
| Özet | Her iki yanda uygulamadan önce "N eklenecek, M güncellenecek, K silinecek" | Birleştirme mantığı **kuru çalıştırılarak** hesaplanır (A7); ikinci bir sayma kodu yazılmaz. |
| Sunucu kütüphanesi | `dart:io` `HttpServer.bindSecure` (elle HTTP ayrıştırıcı yok) | Elle yazılmış HTTP ayrıştırıcı kendi başına risk. Bedeli: bağlantı düzeyinde sınırlar zayıf (A3, "Bilinen sınır"). |
| Güncelleyici paketi | Windows zip'i; kurucu yok | `release.yml` yalnız zip + `SHA256SUMS.txt` üretiyor (B1). |
| Güncelleme uygulayıcısı | Yeni sürümün kendi exe'si `--guncelle-uygula` ile yardımcı olur | PowerShell/cmd betiği yok, ek exe yok (B4). |

## A. QR + Wi-Fi senkron

### A1. Akış (tek oturum, iki yönlü)

Masaüstü = geçici sunucu, telefon = istemci. Bulut, hesap, kalıcı sunucu yok. `.habitsync` dosya
yolu (docs/senkron.md) yedek olarak aynen kalır; bu belge dosyanın **nasıl taşındığını** anlatır,
biçimi ve birleştirme kurallarını değiştirmez.

1. Masaüstü: Yedek & Ayarlar > "Telefonla eşleştir (Wi-Fi)". Özel ağ adresi bulunur, sertifika üretilir,
   sunucu açılır, **QR + bağlantı metni + geri sayım (3 dk) + İptal** gösterilir.
2. Telefon: "QR'ı tara" > kamera izni > QR okunur ve doğrulanır > **Onay 1** ("«ARDA-PC» · 192.168.1.20
   ile eşleşilsin mi?"). Bu onaya kadar ağ isteği yok.
3. Telefon `POST /v1/session` (jeton). Jeton yanar. Masaüstü **Onay 2**'yi gösterir: "«Pixel 7»
   (192.168.1.35) bağlanmak istiyor. Bu senin telefonun mu?" (60 sn). Hayır/süre dolması = oturum kapanır.
4. Telefon `GET /v1/state`: masaüstünün tam durumu (`.habitsync`). Telefon dosyayı **kuru çalıştırır**
   ve **Onay 3** gösterir: "Masaüstünden: 12 eklenecek, 3 güncellenecek, 1 silinecek. Sonra telefondaki
   tüm veri bilgisayara gönderilecek." [Birleştir ve gönder] [Vazgeç].
5. Telefon birleştirir (kendi verisini günceller), kendi **tam durumunu** `POST /v1/state` ile yollar.
6. Masaüstü dosyayı doğrular, kuru çalıştırır, **Onay 4**: "Telefondan: 2 eklenecek, 0 güncellenecek,
   0 silinecek. Uygulansın mı?" (60 sn). Onay > birleştirir > `200` + rapor. Sunucu kapanır.

Sıra/tekrar güvenlidir: birleştirme idempotent (senkron.md §3). Adım 4 uygulandı, adım 6 reddedildi
ise telefon güncel, masaüstü değişmemiştir; iki cihaz bozulmaz, yalnız bir yönde eşitlenmiştir ve
arayüz bunu açıkça yazar. Her iki yanda **birleştirmeden hemen önce yerel JSON yedek** alınır
(masaüstü: `yedekler/` altında `aktenak-sync-<tarih>.json`; yedek alınamazsa birleştirme yapılmaz).

### A2. QR içeriği ve bağlantı

Tek satır metin (kamera uygulamasıyla okunursa yalnız metin görünür; açılacak bir şey yok):

```
habitsync://p?v=1&a=192.168.1.20,10.0.0.5&p=51734&f=<43 kar>&t=<32 hex>&e=1783000000&n=ARDA-PC
```

| Alan | Anlam | Kural |
|---|---|---|
| `v` | protokol sürümü | `1`. Büyükse istemci "Uygulamayı güncelle" der, bağlanmaz. |
| `a` | adres(ler) | 1-3 farklı IPv4, virgüllü, noktalı dörtlü (baştaki sıfır yok). Her biri **özel aralıkta** olmalı (A3). |
| `p` | port | 49152-65535 |
| `f` | sertifika parmak izi | sunucu sertifikasının **DER** baytlarının SHA-256'sı, base64url, dolgusuz, tam 43 karakter |
| `t` | tek kullanımlık jeton | 32 küçük hex (128 bit, `Random.secure()`) |
| `e` | bitiş | unix saniyesi (UTC). Yalnız arayüz ipucu; gerçek süre sunucudadır (A6). |
| `n` | bilgisayar adı | en çok 40 karakter, yalnız gösterim; kontrol ve çift yönlü yazı karakterleri (U+202A-202E, U+2066-2069, U+200E/F) atılır. Güvenlik kararı vermez. |

Ayrıştırma (`sozlesme.dart`, iki taraf aynı kodu kullanır): toplam uzunluk ≤ 400; şema tam `habitsync`,
ana makine tam `p`; kullanıcı bilgisi/yol/fragment yok; aynı anahtar iki kez geçerse **ret**; bilinmeyen
anahtar yok sayılır; her alan yukarıdaki kalıba uymazsa ret. Ret nedeni kullanıcıya genel metinle
gösterilir ("Bu QR kod Habit Tracker eşleştirmesine ait değil").

Masaüstü aynı metni QR'ın altında seçilebilir yazı + "Kopyala" düğmesiyle de gösterir (QR okuyamayan,
TalkBack kullanan ya da kamerası olmayan için). Uyarı: "Bu bağlantı bir parola gibidir; yalnız kendi
telefonuna ver."

### A3. Sunucu (masaüstü)

**Adres seçimi.** `NetworkInterface.list(type: IPv4)` ile arayüzler taranır; yalnız şunlar adaydır:
10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16, 169.254.0.0/16 (link-local). Loopback, genel adresler,
100.64.0.0/10 (CGNAT/Tailscale), IPv6, `0.0.0.0` **dışarıda**. Dart'ta "varsayılan yol" bilgisi
yok (spike notu 8); bu yüzden en çok 3 aday alınır, QR hepsini taşır, telefon sırayla dener. Aday
yoksa oturum başlamaz: "Özel bir ağa bağlı değilsin. Wi-Fi'a bağlan ya da dosya ile senkronu kullan."
Sunucu `0.0.0.0`'a değil, **her adaya ayrı** bağlanır; aynı port önce birinde alınır, diğer adreslerde
o port boş değilse o adres listeden düşer.

**Kaynak denetimi.** Gelen bağlantının uzak adresi özel aralıkta değilse bağlantı yanıtsız kapatılır
(genel adresten bir şey gelmemeli; yönlendirici açığı olsa bile).

**TLS.** Oturum başına bellekte: ECDSA P-256 anahtar, kendinden imzalı sertifika (CN `habit-sync`,
SAN = aday IP'ler, `notBefore` = şimdi − 1 saat, `notAfter` = şimdi + 24 saat, rastgele seri).
`SecurityContext.useCertificateChainBytes/usePrivateKeyBytes` ile bellekten yüklenir; **özel anahtar
diske yazılmaz**. `basic_utils` PEM çıktısındaki CRLF temizlenir (spike'ta ilk hata buydu). Sertifika
tarihleri güvenlik kararı vermez (istemci parmak izine bakar); yalnız hijyen.

**Durum makinesi** (`EslestirmeDenetleyici`, arayüzden bağımsız, saf Dart):

| Durum | Girilir | İzin verilen istek |
|---|---|---|
| `bekliyor` | sunucu açıldı | `POST /v1/session` |
| `baglantiOnayi` | geçerli jeton geldi (jeton yandı) | yok (istemci `session` yanıtını bekler) |
| `hazir` | masaüstü kullanıcısı Evet dedi | `GET /v1/state`, `POST /v1/state`, `POST /v1/end` |
| `birlesmeOnayi` | `POST /v1/state` geçerli, özet gösterildi | yok (POST yanıtı bekler) |
| `isleniyor` | Evet; birleştirme sürüyor | yok; İptal **yok sayılır**, veri birleşir |
| terminal: `tamam` · `reddedildi` · `iptal` · `sureDoldu` · `hata` | | sunucu kapanır, oturum anahtarı ölür |

Terminal duruma geçişte önce jeton/oturum anahtarı silinir, sonra dinleyiciler `close(force: true)`.
Uygulama/pencere kapanınca da aynı yol (`dispose`).

**Sınırlar** (sabit adları `sozlesme.dart`'ta; bir test bu tabloyu kodla karşılaştırır):

| Sabit | Değer | Anlam |
|---|---|---|
| `wifiProtokolSurumu` | 1 | |
| `qrOmruSn` | 180 | QR'ın geçerlilik süresi (jeton bu süre içinde kullanılmazsa ölür) |
| `onayBeklemeSn` | 60 | Onay 2 ve Onay 4 için ayrı ayrı; bekleme oturum süresine eklenir |
| `oturumEnFazlaSn` | 600 | Mutlak üst sınır (QR + iki onay + aktarım) |
| `jetonBayt` / `oturumBayt` | 16 / 32 | rastgele; oturum anahtarı base64url 43 kar. |
| `sessionGovdeEnFazla` | 1024 | `POST /v1/session` gövdesi |
| `stateGovdeEnFazla` | `syncMaxFileBytes` (16 MiB) | iki yönde |
| `istekEnFazla` | 20 | oturum başına toplam istek; aşılırsa oturum kapanır |
| `ipBasinaHata` / `toplamHata` | 5 / 50 | yetkisiz denemeler: 5'te o IP engellenir (yanıtsız kapatılır, oturum sürer), 50'de oturum kapanır |
| `eszamanliIpBasina` / `eszamanliToplam` | 2 / 8 | **işlenen istek** sayısı; aşan `429 cok_istek` alır |
| `govdeOkumaSn` | 30 | kimlik doğrulandıktan sonra gövdeyi okumak için toplam süre (elle sayaç, `Stream.timeout` değil) |
| `adresEnFazla` | 3 | QR'daki adres sayısı |
| istemci zaman aşımları | bağlanma 4 sn/adres, `session` 75, `GET` 30, `POST state` 90 | masaüstü onayı beklerken kesilmesin |

**Kimlik.** `Authorization: Bearer <jeton|oturum>`; sabit zamanlı karşılaştırma (elle XOR döngüsü);
eksik/yanlış = `401 yetkisiz` ve o IP'nin sayacı artar, başka hiçbir şey sızmaz. Oturum anahtarı,
`session` isteğini yapan IP'ye bağlanır (başka IP kullanamaz). Kimlik, yola bakmadan önce denetlenir:
bilinmeyen yola yetkisiz istek 404 değil 401 alır.

**Genel HTTP kuralları.** Yalnız HTTPS, HTTP/1.1, her yanıt `Connection: close`, `Cache-Control: no-store`,
`Content-Type: application/json; charset=utf-8`; `Server` başlığı yok; CORS başlığı yok. POST için
`Content-Type: application/json` zorunlu (`415`), `Content-Length` zorunlu (`411`; chunked kabul
edilmez), sınır aşılırsa gövde okunmadan `413`. `Expect: 100-continue` ve `Upgrade` işlenmez
(doğrulanmadı: Dart'ın 100 Continue'yu kendiliğinden gönderip göndermediği testle bakılacak).
Diğer yol `404 yok`, diğer metot `405 metot`.

**Günlük.** Dosyaya günlük yazılmaz. Bellekte, arayüzde "Ayrıntılar"da görünen olay listesi tutulur
(oturum açıldı, bağlantı geldi, onay/ret, sonuç, istek sayısı). Jeton, oturum anahtarı, parmak izi ve
dosya içeriği hiçbir çıktıya girmez (test: bütün çıktı yakalanıp bu değerler aranır).

**Bilinen sınır (kabul).** `HttpServer.bindSecure` TLS el sıkışmasını kendi içinde yapar; bağlantıyı
**kimlik doğrulanana kadar 10 sn'de kesme** ve **IP başına bağlantı sayma** (Takvim'deki gibi) burada
yapılamaz. Yarı açık bağlantı yığan LAN'daki biri oturumu kilitleyemez ama sunucu kaynağı yiyebilir;
oturum en çok 10 dk yaşar ve masaüstünde İptal vardır. Bu sınır **ölçülecek** (E bölümü): 100 yarı açık
TLS bağlantısı varken meşru istemci hâlâ bağlanabiliyor mu. Yetmezse ikinci aşama: ham `ServerSocket` +
`SecureSocket.secureServer` ve kendi 10 sn zamanlayıcısı; elle HTTP ayrıştırma gerektireceği için ancak
ölçüm kötü çıkarsa.

**Sertifika üretimi riski (açık, kapı koşulu).** Spike çıktısında imza algoritması alanı `ecdsa-with-SHA256`
+ NULL parametre gibi göründü (standart parametre yok der). Dart masaüstü istemcisi kabul etti; **Android
Dart istemcisinin kabul ettiği denenmedi**. Dart iki yanda da kendi BoringSSL'ini kullandığı için riskin
düşük olması beklenir ama kanıtlanmadı. Faz 4 "bitti" sayılmadan önce emülatörde sertifika kabulü
denenmeli. Yedek sıra: (1) `basic_utils` ile RSA 2048 (birkaç sn, `Isolate.run`), (2) DER'i elle yazmak,
(3) hiçbiri. Git'in `openssl.exe`'si yalnız geliştirici makinesinde sertifikayı incelemek için; uygulamaya
gömülmez.

### A4. Uç noktalar ve JSON şemaları

Alan adları İngilizce snake_case (senkron.md ile aynı), hata kodları Türkçe ASCII (Takvim ve mobil
güncelleyici ile aynı gelenek). Bilinmeyen alanlar yok sayılır.

**`POST /v1/session`** - `Authorization: Bearer <jeton>`

```json
// istek (<= 1 KiB)
{"protocol": 1,
 "client": {"name": "Pixel 7", "app": "habit-tracker-mobile", "version": "0.3.0"},
 "sync_version": 1}
// 200 yanıt (masaüstü Onay 2'yi verdikten sonra; en çok 60 sn bekletir)
{"protocol": 1, "session": "<43 kar base64url>",
 "server": {"name": "ARDA-PC", "app": "habit-tracker-desktop", "version": "1.5.0"},
 "sync_version": 1, "remaining_s": 540}
```
`client.name` ≤ 40 kar. (temizlenir), `app` ∈ {`habit-tracker-mobile`}. `protocol` ≠ 1 veya
`sync_version` sunucunun bildiğinden büyükse `400 protokol_surumu` (jeton yine yanar). Ret: `403 reddedildi`;
süre: `408 sure_doldu`.

**`GET /v1/state`** - `Bearer <oturum>`. 200 gövde: masaüstünün `.habitsync` JSON'u (senkron.md §1),
`Content-Type: application/json`. Oturumda en çok 2 kez.

**`POST /v1/state`** - `Bearer <oturum>`, gövde: telefonun `.habitsync` JSON'u. Doğrulama `parseSync`
(senkron.md §2-3; **aynı sınırlar**, hiçbiri gevşetilmez). Oturumda tek geçerli POST.
```json
// 200
{"result": "merged",
 "report": {"habit":   {"added":0,"updated":0,"deleted":0,"skipped":0},
            "entry":   {"added":0,"updated":0,"deleted":0,"skipped":0},
            "mood":    {"added":0,"updated":0,"deleted":0,"skipped":0},
            "task":    {"added":0,"updated":0,"deleted":0,"skipped":0},
            "session": {"added":0,"updated":0,"deleted":0,"skipped":0},
            "setting": {"added":0,"updated":0,"deleted":0,"skipped":0},
            "adopted": 0}}
```
`SyncReport` ile birebir. Onay beklerken ikinci POST: `409 mesgul` (doğrulamaya hiç girmez); onay
beklerken masaüstü İptal: bekleyen POST'a `409 iptal`; ret: `403 reddedildi`; süre: `408 sure_doldu`.

**`POST /v1/end`** - `Bearer <oturum>`, gövde `{"reason": "cancel" | "done"}`. `200 {}`, oturum kapanır.
Telefon vazgeçince masaüstünün 60 sn beklememesi içindir.

**Hata gövdesi (hepsi):** `{"error": "<kod>"}`. Başka alan yok: ne ayrıntı, ne yığın izi, ne yol, ne sürüm.

### A5. Hata kodları

| HTTP | Kod | Anlam | Telefondaki metin |
|---|---|---|---|
| 400 | `istek_bozuk` | JSON/başlık bozuk, beklenen alan yok | "Bilgisayarla anlaşılamadı. İki uygulamayı da güncelle." |
| 400 | `protokol_surumu` | sürüm uyuşmuyor | "Uygulama sürümleri uyumsuz. Telefondaki ve bilgisayardaki uygulamayı güncelle." |
| 400 | `senkron_bozuk` | dosya doğrulamayı geçmedi (biçim, sınır, kayıt, gelecek damga) | "Dosya geçersiz; hiçbir şey değişmedi." |
| 400 | `senkron_surumu` | dosya biçimi daha yeni (`SyncVersionException`) | "Dosya daha yeni bir sürümden. Uygulamayı güncelle." |
| 401 | `yetkisiz` | jeton/oturum yanlış, yanmış ya da süresi dolmuş | "Bağlantı geçersiz ya da kullanılmış. Bilgisayarda yeniden 'Telefonla eşleştir'e bas." |
| 403 | `reddedildi` | masaüstü kullanıcısı Hayır dedi | "Bilgisayar eşleştirmeyi reddetti." |
| 404 | `yok` | bilinmeyen yol | genel |
| 405 | `metot` | yanlış metot | genel |
| 408 | `sure_doldu` | onay/gövde süresi bitti | "Süre doldu." |
| 409 | `mesgul` | başka POST onay bekliyor | "Bilgisayar meşgul, biraz sonra dene." |
| 409 | `iptal` | masaüstü oturumu iptal etti | "Bilgisayarda eşleştirme iptal edildi." |
| 409 | `sira_hatali` | durum makinesine aykırı istek | genel |
| 411 | `uzunluk_gerekli` | `Content-Length` yok | genel |
| 413 | `cok_buyuk` | gövde sınırı aşıldı | "Veri çok büyük; dosya ile senkronu dene." |
| 415 | `tur_hatali` | `Content-Type` JSON değil | genel |
| 429 | `cok_istek` | eşzamanlı istek sınırı | "Bilgisayar meşgul, biraz sonra dene." |
| 500 | `ic_hata` | yedek alınamadı ya da birleştirme beklenmedik biçimde düştü (masaüstü uygulaması eklemesi; tasarımda yoktu) | "Bilgisayarda bir hata oldu; hiçbir şey değişmedi." |

`SyncVersionException` dışındaki her `SyncException` `senkron_bozuk` olur; iç mesaj (kayıt sırası vb.)
ağdan **geçmez**, yalnız yerel arayüzde gösterilir.

İstemci tarafı (ağa hiç çıkmadan ya da TLS aşamasında; sunucu göndermez): `qr_gecersiz`, `qr_suresi_doldu`
(yalnız uyarı), `adres_izinsiz`, `wifi_degil`, `ag_ulasilamiyor`, `parmak_izi_uyusmadi`, `zaman_asimi`,
`yanit_bozuk`, `kamera_izni`, `yedek_alinamadi`. Metinler: "Bilgisayara ulaşılamadı. İkisi de aynı
Wi-Fi'da mı? Misafir ağlar cihazları birbirinden ayırabilir. Windows Güvenlik Duvarı'nda 'Özel ağlar'
iznini de kontrol et." / `parmak_izi_uyusmadi`: "Güvenlik uyarısı: bağlanılan cihaz QR'daki cihaz
değil. Bağlantı kesildi, hiçbir veri gönderilmedi." Kullanıcıya hiçbir yerde ham istisna, IP dışında
adres ya da yığın izi gösterilmez.

### A6. İstemci (telefon)

`lib/platform/wifi/istemci.dart`, saf Dart + `dart:io`:
- `HttpClient(context: SecurityContext(withTrustedRoots: false))`; `badCertificateCallback` yalnız
  `base64url(sha256(cert.der)) == f` **ve** `host` QR'daki adreslerden biri **ve** port `p` ise true. Sistem
  güven deposu yok. `findProxy = (_) => 'DIRECT'` (sistem/ortam vekili jetonu görmesin). `followRedirects =
  false` (her yönlendirme hatadır). `autoUncompress = false`. Tek bağlantı, `Connection: close`.
- Bağlanmadan önce yeniden doğrular: her adres özel aralıkta mı (`sozlesme.dart`); değilse `adres_izinsiz`.
- Adresler sırayla denenir (4 sn); ilk TLS + `session` başarısı kullanılır, sonra yalnız o adres.
- Yanıt gövdeleri sınırlı okunur: `Content-Length` > sınır ise hiç okunmaz; akışta sınır aşılırsa kesilir.
  Yanıt JSON'u şemaya göre doğrulanır; `GET /v1/state` gövdesi dosya içe aktarmayla **aynı** `parseSync`'ten geçer.
- `e` süresi geçtiyse (yerel saatle, 120 sn hoşgörü) yalnız uyarı: "QR'ın süresi dolmuş olabilir." (saat farkı
  yanlış alarm verebilir; sunucu tarafı asıl hakem, kapalı sunucu `ag_ulasilamiyor` görünür).
- Ön denetim: `Kopru.agTuru()` `'wifi'` değilse tarama başlamaz ("Önce Wi-Fi'a bağlan; mobil veriyle bilgisayara
  ulaşılamaz"). Mevcut `agTuru` yeniden kullanılır.
- Jeton ve oturum anahtarı yalnız bellekte tutulur; ekran kapanınca/uygulama arka plana gidince oturum
  `POST /v1/end` ile (mümkünse) kapatılır, durum sıfırlanır.

### A7. Kuru çalıştırma ve özet ekranları

Gerekli tek değişiklik **paylaşılan** `sync_import.dart`'a eklenen:
```dart
Future<SyncReport> previewSyncBytes(AppDatabase db, Uint8List bytes)
```
`importSyncBytes` ile aynı `_Merge`'i bir transaction içinde çalıştırır, raporu alır ve **özel bir
istisnayla transaction'ı geri sardırır** (veri değişmez; tetikleyicilerin yazdığı `silinenler` izleri de
geri alınır). Böylece "eklenecek/güncellenecek/silinecek" sayıları gerçek birleştirmeyle aynı koddan çıkar.
Notlar: (a) önizleme ile uygulama arasında kullanıcı yerel veri değiştirirse son rapor biraz farklı
çıkabilir; özet "şu an için" diye yazılır; (b) alışkanlık silinirken hücreleri de
gider, özet "1 alışkanlık (ve kayıtları) silinecek" der; (c) drift `watch()` akışlarının geri sarılan
transaction'da tetiklenmediği **doğrulanacak** (test: önizleme sırasında dinleyici sıfır olay almalı).

Özet ekranı: üstte üç büyük sayı (Eklenecek / Güncellenecek / Silinecek), altında türe göre kırılım
(alışkanlık, işaret, ruh hali, görev, seans). `Silinecek > 0` ise ayrı uyarı satırı ve varsayılan odak
"Vazgeç"te; `Silinecek ≥ 50` ise ek açıklama ("Bu eşleştirmede çok kayıt silinecek; yedek alındı").
Üç sayı da yoksa: "Değişiklik yok, her şey zaten güncel." ve tek [Tamam].

### A8. İzin ve ağ akışları

**Windows (masaüstü).** Sunucu özel adrese ilk kez bağlandığında Windows Defender Güvenlik Duvarı ilk
sefer sorabilir. Uygulama güvenlik duvarı kuralını **kendisi değiştirmez** (yönetici ister, sistem ayarı).
QR'ın altında tek cümle: "Windows izin sorarsa **Özel ağlar**'a izin ver." Telefon 20 sn içinde bağlanmazsa
açılan yardım metni: aynı Wi-Fi mi; ağ profili "Genel" ise "Özel"e al; "Windows Güvenlik Duvarı > Uygulamaya
izin ver > Aktenak Habit Tracker > Özel"; misafir/AP yalıtımlı ağlar; bilgisayar ve telefon farklı alt
ağdaysa. Sunucu adresi/port arayüzde yazı olarak da görünür. Doğrulanmadı: Windows'un kapatılan istemin
ardından engelleme kuralı yazıp yazmadığı (gerçek makinede denenecek).

**Android (telefon).**

| İzin | Tür | Ne zaman |
|---|---|---|
| `INTERNET` | normal (kurulumda) | zaten var (Faz 2) |
| `ACCESS_NETWORK_STATE` | normal | zaten var (`agTuru`) |
| `CAMERA` | **çalışma zamanı** | yalnız "QR'ı tara"ya basınca, önce açıklama ekranı: "Kamera yalnız QR kodu okumak için açılır; görüntü kaydedilmez ve hiçbir yere gönderilmez." |
| `ACCESS_LOCAL_NETWORK` | çalışma zamanı | **şimdi gerekmez**; `targetSdk` 37'ye çıkarken (PLAN notu) manifeste eklenir ve bağlanmadan önce istenir. Doğrulanmadı: davranış hedef sürüm yükseltilince gerçek cihazda sınanacak. |

Manifest: `<uses-permission CAMERA/>` + `<uses-feature android:name="android.hardware.camera" android:required="false"/>`
(kamerasız cihazda kurulum engellenmesin). `usesCleartextTraffic="false"` aynen kalır: `dart:io` soketleri
ağ güvenlik yapılandırmasına bağlı değildir, bağlantı zaten HTTPS; çelişki yok. Reddedilirse: "Kamera izni verilmedi" +
[Yeniden dene] + [Uygulama ayarlarını aç] (`Kopru`'ya küçük bir `uygulamaAyarlariniAc` kanalı:
`ACTION_APPLICATION_DETAILS_SETTINGS`) + "Bağlantıyı yapıştır" yolu açık kalır. `permission_handler` **kullanılmaz**
(37 sorunu, hafızada kayıtlı); izin `mobile_scanner`'ın kendi akışıyla istenir. Tarayıcı ilk geçerli QR'da
durdurulup kamera serbest bırakılır, sonra ağ isteği başlar.

Erişilebilirlik: tarama ekranında "QR'ı tara" ve "Bağlantıyı yapıştır" aynı önemde iki düğme; tüm düğmeler
≥ 48 dp; geri sayım ve durum değişimleri `Semantics(liveRegion: true)`; QR'ın kendisi masaüstünde
`Semantics(label: 'Eşleştirme QR kodu, telefonla tara; yazılı bağlantı aşağıdadır')`. Renk tek başına durum
taşımaz.

### A9. Paketler (asgari)

| Paket | Yer | Neden | Alternatif ve neden değil |
|---|---|---|---|
| `qr` (saf Dart) | masaüstü | QR matrisi üretir; `CustomPainter` ile ~40 satırda çizilir (sessiz bölge, yüksek karşıtlık, `Semantics`). | `qr_flutter` zaten `qr`'a dayanır; üstüne bir katman eklemek yerine doğrudan `qr`. |
| `basic_utils` | masaüstü | Saf Dart ECDSA anahtar + CSR + kendinden imzalı sertifika (spike'ta çalıştı). Geçişli: `pointycastle`, `archive` (B7'de zip için yeniden kullanılır), `http`, `crypto`, ... (spike kilidinde görüldü). | Elle DER yazmak (yedek plan); Git `openssl.exe` (kullanıcı makinesinde yok). |
| `mobile_scanner` | mobil | Kamera + QR çözümleme (CameraX + ML Kit). Kendi izin akışı var. Paketli (bundled) model tercih edilir: Google Play Hizmetleri'ne bağımlı olmaz. APK'ya birkaç MB ekler (APK zaten büyük; güncelleyici sınırı 150 MB, **ilk CI çıktısında yeniden kontrol**). | `camera` + `zxing2` (daha çok elle kod); `qr_code_scanner` (bakımsız). |
| (yok) SHA-256 | iki taraf | Mevcut saf Dart `sha256.dart` yeniden kullanılır; `crypto` doğrudan bağımlılık yapılmaz. | |
| (yok) HTTP | iki taraf | `dart:io` | `http`/`dio`: gereksiz. |

Sürümler `pub get` sırasında seçilip **tam sürüme sabitlenir**; `mobile_scanner`'ın minSdk/AGP/KGP
gereksinimi mevcut araç zinciriyle (Flutter 3.47.5, yerel Gradle önbelleği) **derlenerek doğrulanmalı**
(`home_widget` KGP uyarısı gibi bir sürpriz çıkabilir). Doğrulanmadı.

### A10. Tehdit modeli (Wi-Fi senkron)

Korunan varlıklar: kullanıcının alışkanlık/görev/ruh hali verisi; LAN'daki konum; masaüstü ve telefon bütünlüğü.

| Saldırgan / durum | Önlem | Kalan risk |
|---|---|---|
| Aynı ağda pasif dinleyici | TLS; içerik görünmez | Yok (trafik varlığı görünür) |
| Aynı ağda ortadaki adam | Sertifika **parmak iziyle sabitlenir**; parmak izi kanal dışı (ekran) gelir; sertifika oturum başına yeni, anahtar bellekte | Yok (QR görülmediyse) |
| Port tarayan / jeton deneyen | 128 bit jeton; IP başına 5, toplam 50 hata; QR ömrü 3 dk; yalnız özel IP'ye bağlı; rastgele port; genel kaynak adres yanıtsız kapatılır | Jeton tahmini ihmal edilebilir |
| QR'ı gören (omuz üstü, ekran paylaşımı, fotoğraf) | Jeton tek kullanımlık; veri çıkışı için **masaüstü Onay 2**; Onay 2 adı + IP gösterir, tanınmazsa Hayır; gerçek telefon hata alırsa kullanıcı fark eder | Saldırgan kullanıcıyı Onay 2'de "Evet"e kandırırsa veri gider. Onay metni bunu söyler |
| Masaüstü gibi davranan sahte sunucu | Telefon yalnız kullanıcının taradığı/yapıştırdığı QR'a bağlanır, uzaktan tetiklenebilir derin bağlantı **yok**; Onay 1 | Kullanıcı saldırganın QR'ını tarar ve onay verirse telefon verisi gider |
| Telefon gibi davranıp masaüstüne veri basan | Jeton + Onay 2 + dosya `parseSync` + Onay 4 (özet) + öncesinde yedek | Onaylanan kötü veri LWW'ye girer; yedek geri dönüş sağlar |
| Kötü niyetli/dev dosya (CPU, bellek) | Aynı sınırlar (16 MiB, 250k kayıt, tür başına 10k, derinlik 8), gövde okunmadan 413, tek eşzamanlı POST | Doğrulama ana isolate'te çalışır; gerçek veri küçük. `Isolate.run` ölçümle eklenir |
| Gelecek damgalı dosya (LWW zehirleme) | `syncMaxFutureSecs` ile tüm dosya reddi (senkron.md) | Yok |
| Slowloris / yarı açık bağlantı | Gövde toplam 30 sn, oturum ömrü 10 dk, `HttpServer` zaman aşımları | **Bağlantı düzeyi sınır yok (A3 sınırı)**; ölçülecek |
| Hata iletisi/günlük sızıntısı | Hata gövdesi yalnız kod; günlük dosyası yok; çıktı taraması testi | Yok |
| Vekil / VPN | `findProxy: DIRECT`; VPN LAN'ı kesiyorsa `ag_ulasilamiyor` | Kullanıcı VPN'i kapatmalı |
| Aynı oturumu tekrar oynatma | Jeton `session` ile yanar, oturum anahtarı IP'ye bağlı, sunucu bitince ölür | Yok |

Kabul edilen: LAN'daki zararlı yazılımlı bir **masaüstü ya da telefon** zaten verinin sahibidir. Bu
tasarım hesap/bulut/kimlik sunmaz; güven yalnız "aynı kullanıcı iki ekrana da bakıyor" varsayımına dayanır.

## B. Masaüstü uygulama içi güncelleme

### B1. Mevcut yayın biçimi (masaüstü `release.yml`, okundu)

- Tetik: `v*` etiketi. Önce `scripts/guvenlik_kapisi.py <etiket>` (`guvenlik/incelemeler/<etiket>.md` kayıtlı ve
  güncel değilse derleme başlamaz), sonra `flutter test`, `flutter build windows --release` (Flutter 3.47.5 sabit).
- Varlıklar: **yalnız** `aktenak-habit-tracker-<etiket>-windows.zip` (etiket `v` ile: `...-v1.4.0-windows.zip`; zip
  kökünde `Release/*` içeriği doğrudan durur, üst klasör yok) ve `SHA256SUMS.txt` (`<64 hex>  <ad>`, ascii).
  Kurucu (MSI/Inno) **yok**. Build provenance attestation üretilir ama uygulama içinden doğrulanamaz.
- Release `--draft` açılır: Arda yayımlayana kadar `releases/latest` görmez. **Bu, insan kapısıdır** ve güncelleyici
  ona güvenir.
- İmza yok (Authenticode yok); README SmartScreen uyarısını anlatır. "Portable": kullanıcı zip'i bir yere açar.
  Başlangıçta çalıştırma kaydı `Platform.resolvedExecutable` yolunu yazar (yani **yerinde güncelleme** yolu
  değiştirmemeli).
- Veri uygulama klasöründe değil: `%APPDATA%\com.aktenak\aktenak_habit_tracker` (`appDataDirectory`). Güncelleme
  veri klasörüne **dokunmaz**.
- Yok olanlar: sürüm sabiti (`pubspec.yaml`'da `1.3.3+8` tek yer), uygulama içi güncelleyici, `Settings` içinde
  güncelleme anahtarları. Sürüm sabiti ve eşitlik testi eklenecek (mobildeki `lib/surum.dart` + `surum_test.dart`).
- Odak sayacı durumu widget içinde bellekte (`focus_card.dart`, `Timer`); uygulama kapanırsa çalışan sayaç kaydedilmez.

**Önemli fark (mobil ile):** Android, aynı imzayla olmayan APK'yı kurmayı kendisi reddeder; Windows'ta
böyle bir ikinci kapı **yok**. Masaüstünde güvenin dayanağı yalnız GitHub'daki release bütünlüğü + TLS +
SHA-256'dır. `SHA256SUMS.txt` zip ile **aynı yerden** geldiği için bozulmayı yakalar, repo/hesap
ele geçirilmesini yakalamaz. Bu yüzden B6'da önerilen sertleştirme var.

### B2. Mobil güvenlik modelinden uyarlama

| Mobil (`lib/platform/guncelleme/`) | Masaüstü karşılığı |
|---|---|
| Yalnız `api.github.com`, `github.com`, `objects.githubusercontent.com`, `release-assets.githubusercontent.com`; `github.com` için yol `/<depo>/releases/` | **Aynı küme**, `depo = tungarix/habit-tracker`. Her yönlendirme adımı aynı denetimden geçer (elle izleme, en çok 5), https, port 443, kullanıcı bilgisi yok, `..`/`%2e`/`%5c`/`%2f` yok, ASCII dışı yok. |
| `Habit-Tracker-<sürüm>.apk` beklenen ad | `aktenak-habit-tracker-v<sürüm>-windows.zip` (tam ad; ikinci aynı adlı varlık yok sayılır) |
| `SHA256SUMS.txt` zorunlu, satır belirsizse ret | Aynı (`ozetCoz` birebir). CRLF kabul. |
| Boyut sınırı 150 MB, beyan edilenden fazla yazılmaz | Zip sınırı **200 MiB** (`GUNCELLEME_MAKS_BAYT`, yalnız geliştirmede dart-define). Açılmış boyut sınırı 600 MiB, dosya sayısı ≤ 3000 (B4). Gerçek zip boyutu ölçülüp sınır buna göre ayarlanır (**ölçülmedi**). |
| Yalnız kararlı `X.Y.Z`, taslak/ön sürüm yok, sayısal karşılaştırma, eşit/eski = teklif yok | Aynı (`surumCoz`, `dahaYeniMi`). `+build` yok sayılır. `releases/latest` sıralaması tarihe göredir; sürüm karşılaştırması geri sürüme düşmeyi önler. |
| İlk çalıştırma onayı; denetim kapalı/sorulmamışsa ağ isteği YOK; günde en çok bir | Aynı. Anahtarlar `Settings`: `update_check` (`1`/`0`/yok), `update_record` (JSON). Cihaza özel, senkronlanmaz. "Şimdi denetle" günlük sınıra takılmaz. ETag ile koşullu istek. |
| Kullanıcı tetikler, otomatik kurulum yok | Aynı: **iki ayrı tıklama** (İndir; sonra Kapat ve güncelle). |
| Kurulumdan hemen önce dosya yeniden özetlenir | Aynı: açmadan önce zip, açtıktan sonra hazırlık klasörü yeniden denetlenir (B4). |
| `User-Agent: HabitTracker/<sürüm>`, çerez/kimlik yok | Aynı |
| Ağ türü kuralı (yalnız Wi-Fi) | Yok (masaüstünde ölçülü bağlantı bilgisi güvenilir değil); indirme boyutu onay penceresinde yazılır. |
| `PackageInstaller` + Android imza denetimi | **Karşılığı yok**; B4 uygulayıcı + B6 sertleştirme |

### B3. Kullanıcı akışı

1. İlk açılışta (bu özelliği taşıyan ilk sürümde) tek seferlik pencere: "Yeni sürümleri denetleyeyim mi? Uygulama
   yalnız github.com/tungarix/habit-tracker adresine sürüm sorar; kişisel veri göndermez." [Denetle] [Denetleme].
   Seçim Ayarlar'dan değişir. Seçilene kadar ağ isteği yok.
2. Yedek & Ayarlar > "Güncelleme": sürüm, son denetim, açık/kapalı anahtarı, [Şimdi denetle]. Denetim açıksa uygulama
   açılışta ve saatlik zamanlayıcıda (mevcut otomatik yedek gibi) günde en çok bir kez sorar; tepsideki uygulama günlerce
   açık kalabilir.
3. Yeni sürüm varsa kart: "Yeni sürüm 1.5.0 (≈ 38 MB)" (boyut release varlığından okunur; 38 yalnız örnek) + [Sürüm notları]
   (tarayıcıda, yalnız izinli GitHub adresi, `rundll32 url.dll,FileProtocolHandler` ile, ek paket yok) + [İndir ve doğrula].
4. İndirme: ilerleme çubuğu, İptal. Bitince SHA-256 ve zip yapısı doğrulanır; hazırlık klasörüne açılır. Başarısızlıkta
   dosyalar silinir, kod gösterilir.
5. Hazır: "Güncelleme hazır. Uygulama kapanıp 1.5.0 ile yeniden açılacak. Verilerine dokunulmaz." Uyarılar: çalışan odak sayacı
   varsa ("kapanırsa bu seans kaydedilmez"), Wi-Fi eşleştirme oturumu açıksa (önce kapatılır). [Kapat ve güncelle] [Sonra].
   "Sonra" hazırlığı siler (bir sonraki sefer yeniden indirilir; yarım kurulum durumu tutulmaz).
6. [Kapat ve güncelle]: (a) yedek (`yedekler/`), (b) sunucu/zamanlayıcılar durur, (c) pencere konumu kaydedilir, (d) veritabanı
   kapanır, (e) yardımcı başlatılır, (f) uygulama **tepsideki Çıkış ile aynı yoldan** kapanır (`setPreventClose(false)` + `destroy`;
   `exit(0)` yok). Pencerenin X'i tepsiye gizlediği için "kapat"ın gerçek çıkış olması şarttır.
7. Yeni sürüm açılınca sonuç dosyası okunur: "1.5.0'a güncellendi." ya da "Güncelleme uygulanamadı (kod); eski sürüm geri
   yüklendi." Dosya silinir, `.eski` temizlenir.

### B4. Uygulayıcı (kendini değiştirme sorunu)

Çalışan exe/DLL'lerin üzerine yazılamaz. Seçilen yol: **yeni sürümün kendi exe'si yardımcı olur.**
`hazirlik\yeni\` içindeki tam paket çalıştırılır:

```
hazirlik\yeni\aktenak_habit_tracker.exe --guncelle-uygula=1 --hedef "<kurulum klasörü>" --pid <eski süreç> --sonuc "<sonuç dosyası>"
```
`main(args)` en başta (veritabanı, tepsi, pencere yöneticisi **açılmadan**) bu bayrağı yakalar ve yalnız küçük bir
"Güncelleniyor, lütfen bekle..." penceresi açar. Mantık saf Dart (`uygula.dart`), sahte klasörlerle test edilir:

1. Argümanlar doğrulanır: `--hedef` mutlak yol ve içinde `aktenak_habit_tracker.exe` var; `--sonuc` veri klasöründe;
   komut satırındaki değerler **kabukta komut olarak çalıştırılmaz** (kabuk yok, `Process.start` argüman listesiyle).
2. Eski süreç bitene kadar bekler: `aktenak_habit_tracker.exe`'yi `...exe.eski` olarak **yeniden adlandırmayı** 250 ms
   aralıkla dener (çalışırken Windows reddeder), en çok 30 sn. Olmazsa vazgeç: `uygulama_mesgul`, eski exe'yi yeniden başlat.
3. "Sahip olunan küme" değiştirilir: kökteki `*.exe`, `*.dll` ve `data\` klasörü. Her eski öğe `hedef\.eski\...` altına
   **taşınır**, yenisi kopyalanır. Bu kümenin dışındaki dosyalara (kullanıcı notu vb.) dokunulmaz.
4. Hata (disk dolu, kilit, izin): taşınanlar geri taşınır, sonuç `geri_alindi`, eski exe başlatılır.
5. Başarı: yeni exe `hedef` içinden başlatılır (`ProcessStartMode.detached`), sonuç `tamam` yazılır, yardımcı çıkar.
   `hazirlik\` ve `.eski` temizliği yeni uygulamanın ilk açılışında yapılır.

Reddedilen alternatifler: çalışırken yeniden adlandırıp kopyalama (süreç içinde, çökme ortası karışık kurulum);
PowerShell/cmd betiği (yürütme ilkesi, yola gömme/kaçış hataları, virüs yazılımı sezgisi); ayrı küçük exe
(`windows/runner` değişikliği, ikinci derleme hedefi).

**Geri alma sınırı.** Dosya geri alma yalnız yeni uygulama **bir kez açılıp** veritabanını yükseltmeden önce
güvenlidir; sonrasında eski exe yeni şemayı tanımayabilir. Bu yüzden yedek (B3 6a) şart ve geri alma yalnız
kopyalama aşaması için vardır. Sözleşme `--guncelle-uygula=1` sürümlüdür; yeni sürümün kodu eski sürümün
çağırdığı biçimi anlamak zorundadır.

**Önkoşullar** (indirmeden önce denetlenir): kurulum klasörü yazılabilir mi (geçici dosya yazıp silerek; değilse
`klasor_yazilamaz`: "Bu klasöre yazılamıyor (ör. Program Files). Yeni sürümü elle indir."); kurulum klasörü ağ
sürücüsü/UNC ise reddedilir. Disk dolu `FileSystemException` (Windows hata 112) `disk_dolu` olur.

**Zip açma** (`paket.dart`, `archive` ile, **yalnız hazırlık klasörüne**): her girdi açılmadan önce denetlenir: `\` → `/`
çevrilir, mutlak yol/sürücü harfi/`..`/boş ad/ayrılmış Windows adı (`CON`, `NUL`...)/NTFS akış (`:`) reddedilir;
sembolik bağ ve özel girdi reddedilir; çözülen yol hazırlık klasörünün içinde mi (`p.isWithin`); dosya sayısı ≤ 3000,
toplam açılmış boyut ≤ 600 MiB (sıkıştırma bombası), tek dosya ≤ 300 MiB. Açtıktan sonra zorunlu dosyalar var mı:
`aktenak_habit_tracker.exe`, `flutter_windows.dll`, `data\app.so`, `data\icudtl.dat`; yoksa `paket_bozuk` (bu liste bir
derleme çıktısından **doğrulanmadı**, kod yazılırken gerçek `build\windows\x64\runner\Release` ile karşılaştırılacak).
Hazırlık klasörü `%LOCALAPPDATA%\com.aktenak\aktenak_habit_tracker\guncelleme\` altındadır (kullanıcıya özel).

Not: Windows'un "internetten indirildi" işareti (Mark-of-the-Web) bizim yazdığımız dosyalara konmaz; SmartScreen
yeni exe için sormaz. Doğrulamayı biz yaptık, ama kullanıcı SmartScreen'in ek uyarısını da görmez (B6).

### B5. Hata kodları (güncelleyici)

Mobil kodlar aynen: `ag_hatasi`, `limit` (403/429), `bozuk_yanit`, `adres_izinsiz`, `boyut_uyusmuyor`, `ozet_bulunamadi`,
`ozet_uyusmuyor`, `izin_yok` (dosya sistemi). Masaüstüne özgü yeni: `paket_bozuk` (zip yapısı/zorunlu dosya),
`klasor_yazilamaz`, `disk_dolu`, `uygulama_mesgul` (eski süreç kapanmadı / odak sayacı / eşleştirme açık),
`uygulama_basarisiz` (uygulayıcı geri aldı), `surum_dusuk` (indirilen sürüm mevcut olandan yeni değil). Arayüzde yalnız
Türkçe açıklama + kısa kod gösterilir; ham istisna gösterilmez.

### B6. Tehdit modeli (güncelleyici) ve önerilen sertleştirme

| Saldırgan | Önlem | Kalan risk |
|---|---|---|
| Ağ üstünde MITM / DNS | TLS, sunucu izin listesi, yönlendirme denetimi | GitHub CA güveni (sistem kökleri) |
| CDN/depolama bozulması | Boyut + SHA-256 | Yok |
| Başka repo/ad taklidi | `github.com/tungarix/habit-tracker/releases/` yol ön eki; tam varlık adı | Yok |
| Eski sürüme geri düşürme | Yalnız KESİN daha yüksek sürüm | Yok |
| Kötü zip (zip-slip, bomba) | B4 girdi denetimi ve sınırlar | Yok |
| Doğrulamadan sonra dosyayı değiştiren yerel süreç | Yeniden özet + kullanıcıya özel hazırlık klasörü | Aynı kullanıcı hesabındaki kötü yazılım zaten her şeyi yapabilir |
| **Release/hesap ele geçirilir** (zararlı zip + eşleşen SHA256SUMS) | Mevcut modelde **yok**. Taslak (draft) → Arda yayımlar kapısı insan denetimidir | **Asıl açık.** Aşağıdaki öneri |
| Kullanıcının bilmeden güncellenmesi | Denetim izni, indirme tıklaması, kapatma tıklaması ayrı | Yok |
| Güncelleme sırasında veri kaybı | Önceden yedek, veri klasörüne dokunmama, geri alma | Yükseltilmiş şemaya geri dönüş yok (B4) |

**Öneri (karar Arda'nın): `SHA256SUMS.txt` için Ed25519 ayrık imza.** Release iş akışı `SHA256SUMS.txt.sig` üretir (özel anahtar
GitHub'da değil, çevrimdışı/Arda'da; gizli anahtar CI'a konursa kazanç azalır), uygulamaya yalnız **genel anahtar** gömülür,
güncelleyici imzayı özet dosyasına karşı doğrular. Böylece GitHub hesabı ele geçirilse bile anahtar olmadan zararlı güncelleme
kabul edilmez. Bedel: anahtar yönetimi (kaybolursa güncelleme zinciri kopar, mobil imza anahtarıyla aynı uyarı), saf Dart Ed25519 için
bir kütüphane (`pointycastle` zaten geçişli bağımlılık; **Ed25519 desteği sürümünde var mı doğrulanmadı**, yoksa küçük bir paket).
**Bu görevde imza anahtarı üretilmez.** İmza doğrulaması gelene kadar güncelleme kartında şu satır görünür: "Bu sürüm imzalı değil;
yalnız SHA-256 ile doğrulandı." İmza gelince bu satır zorunlu ret olur.

### B7. Paketler

Yeni doğrudan bağımlılık: **yok denecek kadar az.** Zip için `archive` (saf Dart) gerekir; masaüstünde `basic_utils` (A9) geçişli olarak
zaten getirir (spike kilidinde var), ama doğrudan kullanıldığı için `pubspec.yaml`'a açıkça yazılır ve tam sürüme sabitlenir. SHA-256: mevcut saf
`sha256.dart`. HTTP: `dart:io`. URL açma: `Process.start('rundll32', ...)`. `url_launcher` eklenmez. Alternatif olarak
Windows'un `tar.exe`'si (bsdtar) bağımlılıksız zip açar ama girdi denetimini bizim yazmamıza izin vermez; reddedildi.

## C. Modül ve dosya bölümü

**Paylaşılan (kaynak masaüstü, `tool/esitle.ps1` mobile kopyalar, SHA-256 `kaynak_ozet.json`'da):**

| Dosya | İçerik |
|---|---|
| `lib/core/sha256.dart` | Saf SHA-256 (`Sha256Akis`, `sha256`, `onaltilik`) + `base64url` parmak izi. Mobilde `platform/guncelleme/sha256.dart` bu dosyayı `export` eder (tek kopya). |
| `lib/data/sync/wifi/sozlesme.dart` | Sabitler (A3 tablosu), hata kodları (enum + HTTP eşlemesi), QR kodlama/ayrıştırma, özel IPv4 denetimi, ad temizleme, JSON modelleri (`OturumIstegi/Yaniti`, `HataYaniti`, `SonucYaniti`). **Flutter import etmez** (saflık testi). |
| `lib/data/sync/sync_import.dart` | `previewSyncBytes` eklenir (A7). Mevcut dosya; değişiklik iki yanda aynı. |
| `test/wifi_sozlesme_test.dart`, `test/wifi_purity_test.dart`, `test/ortak/wifi_vektorler.json` | Ortak sözleşme testleri (D). |

**Yalnız masaüstü (`habit-tracker`):**

| Dosya | İçerik |
|---|---|
| `lib/data/sync/wifi/sertifika.dart` | `basic_utils` ile oturum sertifikası + özel anahtar (bellekte), PEM→DER, parmak izi. Tek `basic_utils` kullanan dosya. |
| `lib/data/sync/wifi/sunucu.dart` | `HttpServer.bindSecure`, yönlendirme, kimlik, sınırlar, gövde okuma. Saf Dart + `dart:io` + veri katmanı. |
| `lib/data/sync/wifi/eslestirme_denetleyici.dart` | Durum makinesi, onay `Completer`'ları, zamanlayıcılar, olay listesi. Arayüzden bağımsız. |
| `lib/data/sync/wifi/ag_adresleri.dart` | `NetworkInterface` taraması ve aday seçimi (`sozlesme.dart`'taki özel IP denetimiyle). |
| `lib/features/eslestir/eslestir_ekrani.dart`, `qr_cizici.dart`, `onay_pencereleri.dart` | QR + geri sayım + iptal, Onay 2 ve Onay 4 pencereleri, yardım metni. Giriş: Yedek & Ayarlar ekranına bölüm. |
| `lib/data/auto_backup.dart` | `yedekAl(etiket)` küçük eklemesi (senkron/güncelleme öncesi). Budama yalnız kendi önekini siler (mevcut kural). |
| `lib/surum.dart` + `test/surum_test.dart` | Sürüm sabiti = pubspec. |
| `lib/data/update/saf.dart` | `izinliSunucular`, `adresUygun`, `surumCoz`, `dahaYeniMi`, `yayinCoz` (zip adı), `ozetCoz`. Mobildekinin uyarlaması. |
| `lib/data/update/ag.dart`, `guncelleyici.dart`, `ayarlar.dart` | Mobildeki sınıfların uyarlaması (`Ag`, `Guncelleyici`, `GuncellemeAyarlari`); `Settings` anahtarları `update_check`, `update_record`. |
| `lib/data/update/paket.dart` | Zip girdi denetimi + hazırlık klasörüne açma + zorunlu dosya denetimi. |
| `lib/data/update/uygula.dart` | Uygulayıcı mantığı (B4), saf Dart. |
| `lib/features/update/guncelleme_bolumu.dart`, `guncelleme_pencereleri.dart` | Arayüz (B3). |
| `lib/main.dart` | `--guncelle-uygula` dalı en başta; açılışta sonuç dosyası + `.eski` temizliği + saatlik denetim. |
| `lib/shared/desktop_integration.dart` | Tepsideki "Çıkış" yolu tek yerden çağrılabilir hâle gelir (`TrayService.quit()`), güncelleme bunu kullanır. |
| `docs/wifi-senkron.md` | Bu belgenin kopyası (A ve B bölümleri kalıcı spec olur). |

**Yalnız mobil (`habit-tracker-mobil`):**

| Dosya | İçerik |
|---|---|
| `lib/platform/wifi/istemci.dart` | Sabitlemeli `HttpClient`, adım adım oturum (A6), hata eşlemesi. Saf Dart + `dart:io`. |
| `lib/platform/wifi/qr_tarayici.dart` | `mobile_scanner` sarmalayıcı (arayüz + sahte uygulama; testler gerçek kamera istemez). |
| `lib/features/settings/wifi_eslestir_ekrani.dart` | Açıklama/izin ekranı, tarama, Onay 1, ilerleme, Onay 3, sonuç. Giriş: Ayarlar'daki senkron bölümü. |
| `lib/platform/kopru.dart` + `MainActivity.kt` | `uygulamaAyarlariniAc` kanalı. |
| `android/app/src/main/AndroidManifest.xml` | `CAMERA`, `uses-feature camera required=false`. |
| `lib/platform/guncelleme/saf.dart` | Değişmez (yalnız ortak vektör testi eklenir). |
| `pubspec.yaml` | `mobile_scanner` (tam sürüm); `basic_utils` yalnız **dev_dependency** (e2e, D). |
| `test/fixtures/wifi_test_sertifika.pem` | Yalnız test için üretilmiş, ürünle ilgisiz geçici sertifika + anahtar (istemci testleri `basic_utils`'siz çalışsın). |
| `tool/esitle.ps1`, `tool/kaynak_ozet.json` | Yeni paylaşılan dosyalar listeye girer (sapma değil, kopya). |
| `tool/e2e/wifi_e2e.ps1`, `tool/e2e/wifi_e2e_test.dart` | Gerçek sunucu + gerçek istemci, D. |

## D. Testler ve ortak sözleşme

Kural (Windows): `flutter test` rastgele `0xC0000005` ile çöker; "did not complete" **yeniden denenir**, gerçek test hatası
yeniden denenmez (`tool/test_calistir.ps1` mantığı). Testler geçici veritabanı kullanır, gerçek `%APPDATA%`'ya yazmaz.

**Ortak sözleşme nasıl korunur.** Üç katman:
1. **Tek kaynak, kopya + özet:** `sozlesme.dart`, `sha256.dart`, `sync_*.dart` masaüstünde yazılır, `esitle.ps1` ile mobile kopyalanır;
   `uyum_test.dart` SHA-256'ları `kaynak_ozet.json` ile karşılaştırır. Ayrışma CI'da kırmızı olur.
2. **Belge ↔ kod testi:** `wifi_sozlesme_test.dart`, `docs/wifi-senkron.md`'deki sabit tablosunu ve hata kodu tablosunu ayrıştırıp
   kodla karşılaştırır (senkron.md'deki sınır tablosu testiyle aynı desen).
3. **Vektör dosyası:** `test/ortak/wifi_vektorler.json` (iki repoda aynı): geçerli/geçersiz QR dizeleri (çift anahtar, genel IP, 44 karakterli
   parmak izi, sürüm 2, uzun ad, bidi karakteri...), beklenen ayrıştırma sonuçları, özel/genel IP listesi, hata kodu ↔ HTTP eşlemesi. Güncelleyici
   için `test/ortak/guncelleme_vektorleri.json`: `surumCoz`, `dahaYeniMi` (0.10.0 > 0.9.0, `1.0`, `v1.0.0-beta`), `ozetCoz` (CRLF, çift satır,
   `*` ayracı), `adresUygun` (başka depo, `%2e%2e`, port 444, `http`). **İki repo da aynı dosyayı çalıştırır**; mobil `saf.dart` ile masaüstü
   `saf.dart` aynı vektörlerde aynı cevabı vermek zorunda.

**Masaüstü birim testleri.**
- `wifi_sertifika_test`: DER ayrıştırılır (SAN IP'leri, geçerlilik penceresi, anahtar türü), parmak izi 43 kar., her oturumda farklı.
- `wifi_sunucu_test` (gerçek `HttpServer`, `127.0.0.1`, **yalnız testte** loopback izinli bayrak; üretim kurucusu loopback'i reddeder; kısa süreli
  sabitler enjekte edilir): yanlış/eksik jeton 401; jeton yeniden kullanımı 401; yanlış parmak izi el sıkışmada ret; durum makinesi sırası
  (`sira_hatali`); 411/413 (gövde okunmadan), 415, 404/405; IP başına 5 hatada engel, 50'de kapanma; eşzamanlı sınır 429; onay kabul/ret/zaman
  aşımı/iptal sırasında bekleyen POST'un yanıtı; `isleniyor` iken iptalin yok sayılması; oturum süresi sonunda kapanma; dışarı sızan çıktıda
  (hata gövdeleri, olay listesi) jeton/oturum/parmak izi/dosya içeriği yok; uygulama kapanınca sunucunun kapanması.
- `sync_onizle_test`: `previewSyncBytes` veriyi ve `silinenler`'i değiştirmez, raporu `importSyncBytes` ile aynı çıkarır, `watch()` akışı tetiklenmez.
- `guncelleme_*_test`: yerel sahte GitHub (Dart, `ekSunucular` ile; mobildeki `guncelleme_sahte_github.py` mantığı): yeni/aynı/eski sürüm, taslak,
  ön sürüm, eksik varlık, aşırı büyük boyut, izinsiz yönlendirme, kötü SHA, çift satır SHA, limit (403/429), 304; `paket_test`: zip-slip, mutlak
  yol, `\`, ayrılmış ad, bomba, eksik exe; `uygula_test`: geçici klasörlerde başarı, kilitli dosya (açık `RandomAccessFile`) ile `uygulama_mesgul`,
  yarıda hata > geri alma, sahip olunan küme dışındaki dosyalara dokunulmaması, `--hedef` doğrulaması.

**Mobil birim/arayüz testleri.** `wifi_istemci_test` (test sertifikasıyla süreç içi sahte sunucu: doğru pin, yanlış pin, adres sırası, yönlendirme
ret, vekil yok, gövde sınırı, yanıt şeması, hiçbir hatada ham istisna metni yok), `wifi_eslestir_ekrani_test` (sahte tarayıcı + sahte istemci:
izin reddi yolu, Onay 1 öncesi ağ isteği yok, özet sayıları, Vazgeç yolu veriyi değiştirmez), erişilebilirlik (`Semantics`, 48 dp, %200 yazı).

**Uçtan uca (`tool/e2e/wifi_e2e.ps1`).** İki repo aynı Dart paket adına sahip olduğundan tek süreçte ikisi birden içe aktarılamaz. Betik
masaüstü checkout'tan (`HABIT_MASAUSTU_YOLU`, CI'da etiket) `sunucu.dart`, `sertifika.dart`, `eslestirme_denetleyici.dart`, `ag_adresleri.dart`
dosyalarını `tool/e2e/masaustu_kopya/` içine kopyalar (git'te yok); bunlar `package:aktenak_habit_tracker/data/...` ile içe aktardığı için mobilin
(SHA ile eşit) kopyalarına çözülür. `wifi_e2e_test.dart` gerçek sunucu + gerçek mobil istemci + iki geçici veritabanı (`Dev` yardımcısı) ile:
1. boş telefon ↔ dolu masaüstü; 2. iki yanda farklı düzenleme (LWW) ve iki yönde silme izi; 3. ikinci eşleştirme "değişiklik yok" (idempotent);
4. JSON ile taşınmış veri (ilk eşleştirme) ikilenmez; 5. yanlış pin: sıfır veri yazımı; 6. jeton yeniden kullanımı; 7. masaüstü reddi: telefon güncel,
masaüstü değişmemiş, mesaj doğru; 8. Onay 2 zaman aşımı; 9. 16 MiB + 1 POST > 413; 10. gün başlangıç saati farklıyken eşleştirme (senkron.md §8).
Bu test `127.0.0.1` üzerinde çalışır: **gerçek LAN, güvenlik duvarı, Android sertifika kabulü ve kamera kanıtlamaz.**

## E. İş sırası, açık kararlar, denenmeyenler

**İş sırası** (her adım kendi testiyle; yayın yok):
1. `sozlesme.dart` + `sha256.dart` taşıma + ortak vektörler. 2. `sertifika.dart` (üretim kodu) + **Android emülatöründe sertifika kabul denemesi**
(kapı koşulu). 3. `sunucu.dart` + denetleyici + testler; yarı açık bağlantı ölçümü. 4. `previewSyncBytes`. 5. Masaüstü arayüzü (QR, onaylar).
6. Mobil istemci + arayüz + kamera; manifest. 7. E2E betiği. 8. Masaüstü sürüm sabiti, `saf/ag/guncelleyici/paket/uygula` + testleri + arayüz.
9. `/security-review` ve `guvenlik/incelemeler/` kaydı (yeni dosyalar kapsamda). 10. Gerçek cihaz denemesi (aşağıdaki liste).
11. Yayın düzeni (PLAN): bu belgedeki hiçbir şey yayın adımı içermez.

**Açık kararlar (Arda).**
1. QR'ı uygulama içinde tarama (öneri) mı, PLAN'daki App Link mi? (Öneri: uygulama içi; App Link sonradan eklenebilir.)
2. `CAMERA` izninin eklenmesi (PLAN'ı değiştirir).
3. Güncelleyicinin Ed25519 imza doğrulaması: şimdi mi (yayından önce), sonra mı? Anahtar üretimi ayrı onay ister.
4. Güncelleme özelliğini taşıyan **ilk** sürüm kullanıcıya elle kurulur; uygulama içi güncelleme ancak ondan sonraki sürümlere işler. Yani güncelleyici
   mümkünse ilk Wi-Fi/sync sürümüyle birlikte çıkmalı (sürüm numaraları: PLAN'a göre masaüstü 1.5.0 + mobil 0.3.0, güncelleyici önce).
5. Güncelleme sırasında odak sayacı çalışıyorsa yalnız uyar mı, engelle mi? (Öneri: uyar.)

**Yapılmadı / denenmedi (dürüst liste).**
- Hiçbir kod, test, derleme çalıştırılmadı; yalnız kaynaklar okundu. Spike yalnız `127.0.0.1` üzerinde, Windows masaüstü istemcisiyle denendi.
- Sertifikanın Android'de kabulü, özel LAN IP'sinde bağlantı, Windows Güvenlik Duvarı istemi/ret davranışı, gerçek telefonda kamera izni ve tarama,
  TalkBack, AP yalıtımlı ağ, Android hotspot senaryosu: **denenmedi**.
- `HttpServer`'ın yarı açık TLS bağlantılarına davranışı, başlık boyut sınırı, `Expect: 100-continue`: **ölçülmedi**.
- `mobile_scanner`/`basic_utils`/`archive` sürüm ve araç zinciri uyumu: **doğrulanmadı**; Ed25519 için `pointycastle` desteği: **doğrulanmadı**.
- Gerçek release zip boyutu ve içindeki dosya listesi (B4 zorunlu dosyalar) bir derleme çıktısından **doğrulanmadı**; `Compress-Archive` yolu ayırıcısı
  (`/` mi `\` mi) yalnız savunmacı biçimde (ikisi de normalize) ele alındı.
- `ACCESS_LOCAL_NETWORK` davranışı yalnız PLAN notundan alındı.
- Güncelleme uygulayıcısı gerçek bir kurulumda (portable klasör, tepsi, başlangıç kaydı, SmartScreen) denenmedi.
