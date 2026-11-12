import 'dart:convert';
import 'dart:io';

/// nativeapi'nin Windows bildirimi WinUI3 derlemesi ister (bu yapıda kapalı: isSupported
/// false). Yerine Windows PowerShell 5.1 ile sistem toast'ı gösterilir.
const _aumid = 'com.aktenak.habit_tracker';

/// nativeapi etiket sınırı 1-16 karakter [A-Za-z0-9_-]; "evening-reminder-YYYY-MM-DD" (27) reddedilir.
String hatirlaticiEtiketi(String ymd) => 'rem${ymd.replaceAll('-', '')}';

String _xml(String s) => s
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;');

String _ps(String s) => s.replaceAll("'", "''");

// Raw string: PowerShell'in `$` ve `\` karakterleri Dart'a takılmaz.
const _sablon = r'''
$ErrorActionPreference = 'Stop'
$k = 'HKCU:\Software\Classes\AppUserModelId\@AUMID@'
if (-not (Test-Path $k)) {
  New-Item $k -Force | Out-Null
  New-ItemProperty $k -Name DisplayName -Value 'Aktenak' -PropertyType String | Out-Null
}
[void][Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType = WindowsRuntime]
[void][Windows.Data.Xml.Dom.XmlDocument, Windows.Data.Xml.Dom.XmlDocument, ContentType = WindowsRuntime]
$x = New-Object Windows.Data.Xml.Dom.XmlDocument
$x.LoadXml('@XML@')
[Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier('@AUMID@').Show([Windows.UI.Notifications.ToastNotification]::new($x))
''';

/// Toast'u gösteren PowerShell betiği. Başlıkta "Aktenak" görünsün diye uygulamanın kendi
/// AppUserModelId kaydı HKCU altına bir kez yazılır (yönetici izni gerekmez).
String toastBetigi(String baslik, String mesaj) {
  final xml = '<toast><visual><binding template="ToastGeneric">'
      '<text>${_xml(baslik)}</text><text>${_xml(mesaj)}</text>'
      '</binding></visual></toast>';
  return _sablon.replaceAll('@AUMID@', _aumid).replaceAll('@XML@', _ps(xml));
}

/// Gösterildiyse true. Hata sessizce false döner (hatırlatıcı uygulamayı çökertmemeli).
Future<bool> windowsToastGoster(String baslik, String mesaj) async {
  try {
    final utf16 = <int>[
      for (final u in toastBetigi(baslik, mesaj).codeUnits) ...[u & 0xff, u >> 8],
    ];
    final r = await Process.run('powershell.exe', [
      '-NoProfile',
      '-NonInteractive',
      '-ExecutionPolicy',
      'Bypass',
      '-EncodedCommand',
      base64.encode(utf16),
    ]);
    return r.exitCode == 0;
  } catch (_) {
    return false;
  }
}
