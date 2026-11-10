// SHA-256 (FIPS 180-4). dart:io'da yok; yeni paket eklememek için burada (test vektörleriyle sınanır).
// Akışlı: onlarca MB'lık APK'yı belleğe topla-kopyala yapmadan özetlemek için (`Sha256Akis`);
// `sha256` tek seferlik kısayoldur ve Wi-Fi eşleştirmenin sertifika parmak izi de bunu kullanır.
import 'dart:typed_data';

const _k = <int>[
  0x428a2f98,
  0x71374491,
  0xb5c0fbcf,
  0xe9b5dba5,
  0x3956c25b,
  0x59f111f1,
  0x923f82a4,
  0xab1c5ed5,
  0xd807aa98,
  0x12835b01,
  0x243185be,
  0x550c7dc3,
  0x72be5d74,
  0x80deb1fe,
  0x9bdc06a7,
  0xc19bf174,
  0xe49b69c1,
  0xefbe4786,
  0x0fc19dc6,
  0x240ca1cc,
  0x2de92c6f,
  0x4a7484aa,
  0x5cb0a9dc,
  0x76f988da,
  0x983e5152,
  0xa831c66d,
  0xb00327c8,
  0xbf597fc7,
  0xc6e00bf3,
  0xd5a79147,
  0x06ca6351,
  0x14292967,
  0x27b70a85,
  0x2e1b2138,
  0x4d2c6dfc,
  0x53380d13,
  0x650a7354,
  0x766a0abb,
  0x81c2c92e,
  0x92722c85,
  0xa2bfe8a1,
  0xa81a664b,
  0xc24b8b70,
  0xc76c51a3,
  0xd192e819,
  0xd6990624,
  0xf40e3585,
  0x106aa070,
  0x19a4c116,
  0x1e376c08,
  0x2748774c,
  0x34b0bcb5,
  0x391c0cb3,
  0x4ed8aa4a,
  0x5b9cca4f,
  0x682e6ff3,
  0x748f82ee,
  0x78a5636f,
  0x84c87814,
  0x8cc70208,
  0x90befffa,
  0xa4506ceb,
  0xbef9a3f7,
  0xc67178f2,
];

const _m32 = 0xffffffff;

int _sag(int x, int n) => ((x >> n) | (x << (32 - n))) & _m32;

/// Parça parça beslenen SHA-256. `ekle` istenen boyutta çağrılabilir; `bitir` bir kez çağrılır.
class Sha256Akis {
  final _h = Uint32List.fromList(const [
    0x6a09e667,
    0xbb67ae85,
    0x3c6ef372,
    0xa54ff53a,
    0x510e527f,
    0x9b05688c,
    0x1f83d9ab,
    0x5be0cd19,
  ]);
  final _w = Uint32List(64);
  final _blok = Uint8List(64);
  var _dolu = 0;
  var _toplam = 0;
  var _bitti = false;

  void ekle(List<int> veri) {
    if (_bitti) throw StateError('bitir çağrıldı');
    _toplam += veri.length;
    var i = 0;
    while (i < veri.length) {
      final n = (64 - _dolu < veri.length - i) ? 64 - _dolu : veri.length - i;
      _blok.setRange(_dolu, _dolu + n, veri, i);
      _dolu += n;
      i += n;
      if (_dolu == 64) {
        _isle(_blok);
        _dolu = 0;
      }
    }
  }

  Uint8List bitir() {
    if (_bitti) throw StateError('bitir iki kez çağrıldı');
    _bitti = true;
    final bit = _toplam * 8;
    _blok[_dolu++] = 0x80;
    if (_dolu > 56) {
      _blok.fillRange(_dolu, 64, 0);
      _isle(_blok);
      _dolu = 0;
    }
    _blok.fillRange(_dolu, 64, 0);
    ByteData.sublistView(_blok)
      ..setUint32(56, bit ~/ 0x100000000)
      ..setUint32(60, bit & _m32);
    _isle(_blok);
    final cikti = Uint8List(32);
    final cd = ByteData.sublistView(cikti);
    for (var i = 0; i < 8; i++) {
      cd.setUint32(i * 4, _h[i]);
    }
    return cikti;
  }

  void _isle(Uint8List blok) {
    final w = _w;
    final bd = ByteData.sublistView(blok);
    for (var i = 0; i < 16; i++) {
      w[i] = bd.getUint32(i * 4);
    }
    for (var i = 16; i < 64; i++) {
      final s0 = _sag(w[i - 15], 7) ^ _sag(w[i - 15], 18) ^ (w[i - 15] >> 3);
      final s1 = _sag(w[i - 2], 17) ^ _sag(w[i - 2], 19) ^ (w[i - 2] >> 10);
      w[i] = (w[i - 16] + s0 + w[i - 7] + s1) & _m32;
    }
    var a = _h[0],
        b = _h[1],
        c = _h[2],
        d = _h[3],
        e = _h[4],
        f = _h[5],
        g = _h[6],
        hh = _h[7];
    for (var i = 0; i < 64; i++) {
      final t1 =
          (hh +
              (_sag(e, 6) ^ _sag(e, 11) ^ _sag(e, 25)) +
              ((e & f) ^ (~e & _m32 & g)) +
              _k[i] +
              w[i]) &
          _m32;
      final t2 =
          ((_sag(a, 2) ^ _sag(a, 13) ^ _sag(a, 22)) +
              ((a & b) ^ (a & c) ^ (b & c))) &
          _m32;
      hh = g;
      g = f;
      f = e;
      e = (d + t1) & _m32;
      d = c;
      c = b;
      b = a;
      a = (t1 + t2) & _m32;
    }
    _h[0] += a;
    _h[1] += b;
    _h[2] += c;
    _h[3] += d;
    _h[4] += e;
    _h[5] += f;
    _h[6] += g;
    _h[7] += hh;
  }
}

/// Tek seferlik özet (32 bayt).
Uint8List sha256(List<int> veri) => (Sha256Akis()..ekle(veri)).bitir();

/// Küçük harfli onaltılık gösterim (`SHA256SUMS.txt` biçimi).
String onaltilik(List<int> bayt) =>
    [for (final b in bayt) b.toRadixString(16).padLeft(2, '0')].join();
