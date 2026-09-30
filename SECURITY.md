# Security Policy · Güvenlik Politikası

[English](#english) · [Türkçe](#türkçe)

---

## English

Aktenak Habit Tracker is a local-first desktop app: no server, no account,
no login, no network sync. Your habits, moods, tasks and focus sessions stay in
a local SQLite file. That keeps the attack surface small, but not empty: the
app reads JSON backups you import, writes JSON backups you export, and can
register itself to start with Windows.

### Supported versions

Only the [latest release](https://github.com/tungarix/habit-tracker/releases/latest)
gets security fixes. If you are on an older version, update first and check
whether the problem is still there.

### Reporting a vulnerability

**Please do not open a public issue for a security problem.**

Use GitHub's private reporting instead:
**[Report a vulnerability](https://github.com/tungarix/habit-tracker/security/advisories/new)**
(repository → *Security* tab → *Report a vulnerability*). Only the maintainer
sees the report.

Helpful to include:

- the app version (the release you downloaded, e.g. v1.2.1),
- what you did, what you expected, what happened,
- the impact as you see it (what could an attacker read, change or break),
- a minimal JSON backup file that reproduces it, if relevant.

**Do not attach your own database or a backup with real personal data**; a
small made-up example is enough.

This is a one-person project, so replies are best effort. I will try to answer
within about a week, and to credit you in the release notes unless you prefer
not to be named.

### What counts

For example: a crafted JSON backup that crashes the app, corrupts or silently
overwrites data on import, or reads or writes files outside the app's data;
the start-with-Windows entry pointing somewhere it should not; or a release
file that does not match its published checksum and attestation.

### What does not count

- Someone who already has access to your Windows account and can read the app's
  local database file. It is plain, unencrypted SQLite by design; it is your own
  data on your own machine.
- The Windows SmartScreen warning. The app is not code-signed; this is a known,
  documented limit.
- Problems that only exist in a build you compiled or modified yourself.

### Verifying a download

Each release ships a `SHA256SUMS.txt` and a GitHub build provenance
attestation. With the [GitHub CLI](https://cli.github.com/) installed:

```powershell
Get-FileHash .\aktenak-habit-tracker-v1.2.1-windows.zip -Algorithm SHA256
gh attestation verify .\aktenak-habit-tracker-v1.2.1-windows.zip -R tungarix/habit-tracker
```

Compare the hash with `SHA256SUMS.txt`. Use the file name of the release you
downloaded.

---

## Türkçe

Aktenak Habit Tracker yerel-öncelikli bir masaüstü uygulaması: sunucu yok,
hesap yok, login yok, ağ üzerinden senkron yok. Alışkanlıkların, mood kayıtların,
görevlerin ve odak seansların yerel bir SQLite dosyasında kalır. Bu saldırı
yüzeyini küçültür ama sıfırlamaz: uygulama içe aktardığın JSON yedeklerini okur,
dışa aktardıklarını yazar ve Windows başlangıcında açılacak şekilde kendini
kaydedebilir.

### Desteklenen sürümler

Güvenlik düzeltmeleri yalnızca
[son sürüme](https://github.com/tungarix/habit-tracker/releases/latest) gelir.
Eski bir sürümdeysen önce güncelle, sorun hâlâ varsa bildir.

### Açık bildirme

**Güvenlik sorunu için lütfen herkese açık issue açma.**

Bunun yerine GitHub'ın özel bildirimini kullan:
**[Güvenlik açığı bildir](https://github.com/tungarix/habit-tracker/security/advisories/new)**
(depo → *Security* sekmesi → *Report a vulnerability*). Bildirimi yalnızca
bakımcı görür.

Şunları yazarsan işim kolaylaşır:

- uygulama sürümü (indirdiğin sürüm, ör. v1.2.1),
- ne yaptın, ne bekledin, ne oldu,
- sence etkisi ne (saldırgan neyi okuyabilir, değiştirebilir, bozabilir),
- gerekiyorsa sorunu yeniden üreten küçük bir JSON yedek dosyası.

**Kendi veritabanını ya da gerçek kişisel veri içeren bir yedeği EKLEME**;
küçük, uydurma bir örnek yeter.

Bu tek kişilik bir proje; yanıt vermek elimden geldiği kadar. Yaklaşık bir hafta
içinde cevap vermeye, istemezsen adını yazmamak koşuluyla sürüm notlarında sana
teşekkür etmeye çalışırım.

### Neler kapsamda

Örneğin: uygulamayı çökerten, içe aktarmada veriyi bozan ya da sessizce ezen
veya uygulamanın veri klasörü dışındaki dosyaları okuyup yazan hazırlanmış bir
JSON yedek; Windows başlangıç kaydının olmaması gereken bir yere işaret etmesi;
yayımlanan özet ve attestation'a uymayan bir sürüm dosyası.

### Neler kapsam dışı

- Windows hesabına zaten erişimi olan ve uygulamanın yerel veritabanı dosyasını
  okuyabilen biri. Bu dosya bilerek şifrelenmemiş, düz bir SQLite dosyası; kendi
  bilgisayarındaki kendi verin.
- Windows SmartScreen uyarısı. Uygulama imzalı değil; bu bilinen ve belgelenmiş
  bir sınır.
- Yalnızca kendi derlediğin ya da değiştirdiğin bir sürümde görülen sorunlar.

### İndirmeyi doğrulama

Her sürümde `SHA256SUMS.txt` ve GitHub build provenance attestation'ı var.
[GitHub CLI](https://cli.github.com/) kuruluysa:

```powershell
Get-FileHash .\aktenak-habit-tracker-v1.2.1-windows.zip -Algorithm SHA256
gh attestation verify .\aktenak-habit-tracker-v1.2.1-windows.zip -R tungarix/habit-tracker
```

Çıkan özeti `SHA256SUMS.txt` ile karşılaştır. Dosya adı olarak indirdiğin
sürümünkini kullan.
