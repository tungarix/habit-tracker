import 'dart:io';

import 'sozlesme.dart';

/// Bu makinenin özel IPv4 adresleri (en çok [adresEnFazla]); loopback, CGNAT,
/// genel adresler ve IPv6 dışarıda. Boşsa özel bir ağa bağlı değil demektir.
Future<List<String>> ozelAdaylar() async {
  final out = <String>[];
  for (final ni in await NetworkInterface.list(type: InternetAddressType.IPv4)) {
    for (final a in ni.addresses) {
      if (ozelIpv4mu(a.address) && !out.contains(a.address)) out.add(a.address);
    }
  }
  return out.take(adresEnFazla).toList();
}
