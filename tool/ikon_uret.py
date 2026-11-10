"""Uygulama ve tepsi ikonlarını yeni logodan üretir.

Kaynak: assets/marka/habit-tracker-logo.png (siyah zeminli logo; yazısız işaret
kırpılır). Çıktı:
  windows/runner/resources/app_icon.ico  16,24,32,48,64,128,256 px
  assets/tray_icon.ico                   16,20,24,32,48,64 px

Kullanım (depo kökünde): python tool/ikon_uret.py [--onizleme KLASOR]
Gerekli: Pillow. Sonuç belirlidir: aynı kaynak, aynı ikon.

Yöntem: işaret, kaynağın zemin rengi çıkarılarak ışık katmanı olarak ayrılır;
alfa = en parlak kanal, renk = alfaya bölünmüş (glow korunur). Küçük boyutlarda
(<=32 px) glow alfa eğrisiyle kısılır, halka ve kutu çizgisi kalınlaştırılır.
"""

from __future__ import annotations

import argparse
import struct
import sys
from io import BytesIO
from pathlib import Path

from PIL import Image, ImageChops, ImageDraw, ImageFilter

KOK = Path(__file__).resolve().parent.parent
KAYNAK = KOK / "assets" / "marka" / "habit-tracker-logo.png"
APP_ICO = KOK / "windows" / "runner" / "resources" / "app_icon.ico"
TRAY_ICO = KOK / "assets" / "tray_icon.ico"
APP_BOYUTLAR = (16, 24, 32, 48, 64, 128, 256)
TRAY_BOYUTLAR = (16, 20, 24, 32, 48, 64)

# Halka+kutu işaretinin kaynaktaki merkezi ve kırpma yarı genişliği (glow dahil).
MERKEZ = (620, 468)
YARI = 305

# boyut -> (glow eşiği 0-255, alfa gamma, kalınlaştırma yarıçapı [kırpma pikseli]).
# Eşik arttıkça glow azalır; gamma < 1 soluk halka izini güçlendirir.
KUCUK = {
    16: (70, 0.60, 9),
    20: (60, 0.65, 8),
    24: (55, 0.70, 7),
    32: (40, 0.80, 5),
}


def zemin_rengi(im: Image.Image) -> tuple[int, int, int]:
    """Kaynağın kenar piksellerinin ortancası (siyaha yakın zemin)."""
    w, h = im.size
    nok = [im.getpixel((x, y)) for x in range(0, w, 41) for y in (3, h - 4)]
    nok += [im.getpixel((x, y)) for y in range(0, h, 41) for x in (3, w - 4)]
    return tuple(sorted(p[i] for p in nok)[len(nok) // 2] for i in range(3))  # type: ignore[return-value]


def isaret_rgba(kaynak: Image.Image, zemin: tuple[int, int, int]) -> Image.Image:
    """Yazısız işareti arka plandan ayırır: RGBA, alfa = ışık, renk alfasız."""
    x, y = MERKEZ
    kirp = kaynak.crop((x - YARI, y - YARI, x + YARI, y + YARI)).convert("RGB")
    isik = ImageChops.subtract(kirp, Image.new("RGB", kirp.size, zemin))
    r, g, b = isik.split()
    alfa = ImageChops.lighter(ImageChops.lighter(r, g), b)
    bant = [[] for _ in range(3)]
    # Alfaya bölme (premultiply'ı geri al); alfa 0 ise renk önemsiz.
    for i, b in enumerate(isik.split()):
        bant[i] = [min(255, v * 255 // a) if a else 0 for v, a in zip(b.tobytes(), alfa.tobytes())]
    cikti = Image.merge("RGB", [Image.frombytes("L", kirp.size, bytes(b)) for b in bant])
    cikti.putalpha(alfa)
    return cikti


def kucuk_isle(isaret: Image.Image, esik: int, gamma: float, yaricap: int) -> Image.Image:
    """Glow'u kısar (alfa eğrisi), çizgileri kalınlaştırır (en büyük filtre)."""
    lut = [round(255 * (max(0.0, (i - esik) / (255 - esik)) ** gamma)) for i in range(256)]
    r, g, b, a = isaret.split()
    a = a.point(lut)
    bantlar = [r, g, b, a]
    for _ in range(yaricap):
        bantlar = [bn.filter(ImageFilter.MaxFilter(3)) for bn in bantlar]
    return Image.merge("RGBA", bantlar)


def zemin_levha(boyut: int, renk: tuple[int, int, int], yaricap_orani: float = 0.225) -> Image.Image:
    """Yuvarlatılmış koyu kare; köşeler saydam, kenarlar 4x örneklemeyle yumuşak."""
    ss = 4
    maske = Image.new("L", (boyut * ss, boyut * ss), 0)
    ImageDraw.Draw(maske).rounded_rectangle(
        (0, 0, boyut * ss - 1, boyut * ss - 1), radius=boyut * ss * yaricap_orani, fill=255
    )
    maske = maske.resize((boyut, boyut), Image.LANCZOS)
    levha = Image.new("RGBA", (boyut, boyut), renk + (255,))
    levha.putalpha(maske)
    return levha


def ikon_ciz(boyut: int, isaret: Image.Image, zemin: tuple[int, int, int]) -> Image.Image:
    """Tek boyutlu ikon: levha + ortalanmış işaret (güvenli kenar boşluğuyla)."""
    kucuk = boyut in KUCUK
    # İşaretin levhaya oranı: küçükte kenar boşluğu az (piksel kıt), büyükte bol.
    oran = 0.98 if kucuk else 0.84
    if kucuk:
        isaret = kucuk_isle(isaret, *KUCUK[boyut])
    ic = max(1, round(boyut * oran))
    isaret = isaret.resize((ic, ic), Image.LANCZOS)
    levha = zemin_levha(boyut, zemin)
    kat = Image.new("RGBA", (boyut, boyut), (0, 0, 0, 0))
    kat.paste(isaret, ((boyut - ic) // 2, (boyut - ic) // 2))
    # Işık levhanın saydam köşelerine taşmasın: alfa levhayla çarpılır.
    kat.putalpha(ImageChops.multiply(kat.getchannel("A"), levha.getchannel("A")))
    return Image.alpha_composite(levha, kat)


def ico_yaz(yol: Path, kareler: list[Image.Image]) -> None:
    """ICO yazar: 256 px PNG, diğerleri BMP/DIB (eski araçlarla en uyumlusu)."""
    veriler = []
    for im in kareler:
        w, h = im.size
        if w >= 256:
            tampon = BytesIO()
            im.save(tampon, "PNG")
            veriler.append((w, h, 32, tampon.getvalue()))
            continue
        piksel = im.transpose(Image.FLIP_TOP_BOTTOM).tobytes("raw", "BGRA")
        and_satir = ((w + 31) // 32) * 4
        baslik = struct.pack("<IiiHHIIiiII", 40, w, h * 2, 1, 32, 0, len(piksel), 0, 0, 0, 0)
        veriler.append((w, h, 32, baslik + piksel + bytes(and_satir * h)))
    cikti = bytearray(struct.pack("<HHH", 0, 1, len(veriler)))
    ofset = 6 + 16 * len(veriler)
    for w, h, bit, veri in veriler:
        cikti += struct.pack("<BBBBHHII", w % 256, h % 256, 0, 0, 1, bit, len(veri), ofset)
        ofset += len(veri)
    for *_, veri in veriler:
        cikti += veri
    yol.write_bytes(bytes(cikti))


def uret(onizleme: Path | None = None) -> None:
    kaynak = Image.open(KAYNAK).convert("RGB")
    zemin = zemin_rengi(kaynak)
    isaret = isaret_rgba(kaynak, zemin)
    print(f"zemin rengi: #{zemin[0]:02x}{zemin[1]:02x}{zemin[2]:02x}")
    for yol, boyutlar in ((APP_ICO, APP_BOYUTLAR), (TRAY_ICO, TRAY_BOYUTLAR)):
        kareler = [ikon_ciz(b, isaret, zemin) for b in boyutlar]
        ico_yaz(yol, kareler)
        print(f"{yol.relative_to(KOK)}: {', '.join(str(b) for b in boyutlar)} px")
        if onizleme:
            onizleme.mkdir(parents=True, exist_ok=True)
            for b, im in zip(boyutlar, kareler):
                im.save(onizleme / f"{yol.stem}_{b}.png")


if __name__ == "__main__":
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--onizleme", type=Path, help="her boyutu PNG olarak bu klasöre de yaz")
    a = ap.parse_args()
    if not KAYNAK.exists():
        sys.exit(f"kaynak yok: {KAYNAK}")
    uret(a.onizleme)
