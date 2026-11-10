# Güncelleme imzası (Ed25519)

Uygulama içi güncelleyici, indirdiği `SHA256SUMS.txt` dosyasını release'teki `SHA256SUMS.txt.sig`
(ham 64 bayt Ed25519 imzası) ile, koda gömülü AÇIK anahtara karşı doğrular
(`lib/data/update/imza.dart`). İmza yok, bozuk ya da başka anahtarla atılmışsa zip hiç indirilmez
ve kurulum reddedilir. Böylece GitHub hesabı ele geçirilip zip ile `SHA256SUMS.txt` birlikte
değiştirilse bile, özel anahtar olmadan kabul edilen bir güncelleme üretilemez.

Sınır: özel anahtar GitHub Actions sırrında (`HABIT_UPDATE_SIGNING_KEY`) durur. Yalnız release
varlıklarını değiştirebilen saldırgan bunu yapamaz; ama depoda iş akışı yazabilen biri sırrı
okuyabilir. İş akışı dosyalarını bu yüzden dal koruması / inceleme arkasında tut.

## Anahtar çifti üretmek (bir kez)

```
dart run scripts/guncelleme_imza.dart uret <repo-disi-klasor>
```

Klasör yalnız mevcut Windows kullanıcısına açılır. Özel anahtar `guncelleme-ozel-anahtar.b64`
dosyasına yazılır (ekrana basılmaz); ekrana yalnız AÇIK anahtar basılır ve
`guncellemeAcikAnahtari` sabitine yapıştırılır.

## GitHub sırrını tanımlamak (Arda yapar)

Dosyanın içeriğini `HABIT_UPDATE_SIGNING_KEY` adlı repo sırrı olarak ekle (GitHub > Settings >
Secrets and variables > Actions, ya da `gh secret set HABIT_UPDATE_SIGNING_KEY < dosya`).
Sır yoksa `release.yml` imza adımında düşer; release oluşmaz.

## Yedek (Arda yapar)

Özel anahtar kaybolursa güncelleme zinciri kopar: yeni anahtarlı bir sürümü mevcut kurulumlar
kabul etmez, kullanıcıların elle indirmesi gerekir. Anahtar dosyasının en az bir kopyasını
farklı bir yerde, repodan ve bu bilgisayarın diskinden bağımsız olarak sakla (ör. şifreli
bir USB bellek ya da parola yöneticisinin güvenli notu). Kopyayı gizli tut: bulut klasörüne ya da
repoya düz metin bırakma.

## Elle imzalamak / denemek

```
$env:HABIT_UPDATE_SIGNING_KEY = (Get-Content <anahtar-dosyasi>)
dart run scripts/guncelleme_imza.dart imzala SHA256SUMS.txt SHA256SUMS.txt.sig
```

Betik imzayı gömülü açık anahtarla doğrular; yanlış anahtar hata verir. Testler gerçek anahtarı
kullanmaz, her çalışmada yeni bir test anahtarı üretir.
