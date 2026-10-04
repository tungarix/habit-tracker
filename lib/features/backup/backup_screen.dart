import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants.dart';
import '../../data/providers.dart';
import '../../data/repositories/backup_repository.dart';
import '../../shared/desktop_integration.dart';

/// Export / import the whole database as a single JSON file.
class BackupScreen extends ConsumerStatefulWidget {
  const BackupScreen({super.key});

  @override
  ConsumerState<BackupScreen> createState() => _BackupScreenState();
}

class _BackupScreenState extends ConsumerState<BackupScreen> {
  bool _busy = false;
  bool? _launchAtLogin; // null while the OS hasn't answered yet

  BackupRepository get _repo => ref.read(backupRepositoryProvider);

  @override
  void initState() {
    super.initState();
    if (LaunchAtLoginSetting.isSupported) {
      // Reads the real OS setting rather than trusting a cached flag — the
      // user may have removed it from Windows' own startup-apps list.
      setState(() => _launchAtLogin = LaunchAtLoginSetting.isEnabled);
    }
  }

  Future<void> _toggleLaunchAtLogin(bool value) async {
    setState(() => _launchAtLogin = value); // optimistic
    final ok = LaunchAtLoginSetting.setEnabled(value);
    if (!ok && mounted) {
      setState(() => _launchAtLogin = !value); // revert, OS refused it
      _toast('Windows başlangıç ayarı değiştirilemedi.');
    }
  }

  Future<void> _export() async {
    setState(() => _busy = true);
    try {
      final json = await _repo.exportJson();
      final path = await FilePicker.saveFile(
        dialogTitle: 'Yedeği kaydet',
        fileName: _repo.suggestedFileName(),
        type: FileType.custom,
        allowedExtensions: const ['json'],
        bytes: Uint8List.fromList(utf8.encode(json)),
      );
      if (path == null) return; // cancelled
      // On desktop, file_picker returns the chosen path but does not write the
      // bytes itself, so write them here. (No-op cost on platforms that did.)
      final file = File(path);
      if (!await file.exists() || (await file.readAsString()) != json) {
        await file.writeAsString(json);
      }
      _toast('Yedek kaydedildi:\n$path');
    } catch (e) {
      _toast('Dışa aktarım başarısız: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _import() async {
    final result = await FilePicker.pickFiles(
      dialogTitle: 'Yedek seç',
      type: FileType.custom,
      allowedExtensions: const ['json'],
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;

    final mode = await _askMergeOrReplace();
    if (mode == null) return;

    setState(() => _busy = true);
    try {
      final picked = result.files.single;
      final content = picked.bytes != null
          ? utf8.decode(picked.bytes!)
          : await File(picked.path!).readAsString();
      final imported = await _repo.importJson(
        content,
        replace: mode == _ImportMode.replace,
      );
      _toast(
        'İçe aktarıldı: ${imported.habits} alışkanlık, '
        '${imported.entries} kayıt, ${imported.moods} mood, '
        '${imported.tasks} görev, ${imported.sessions} seans.',
      );
    } catch (e) {
      _toast('İçe aktarım başarısız: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<_ImportMode?> _askMergeOrReplace() {
    return showDialog<_ImportMode>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('İçe aktarma modu'),
        content: const Text(
          'Mevcut verilerle nasıl birleştirilsin?\n\n'
          '• Birleştir: aynı alışkanlık/görev güncellenir, farklı olanlar yeni olarak '
          'eklenir. Aynı gün+alışkanlık kaydının üzerine yazılır; aynı odak seansı '
          'tekrar eklenmez.\n'
          '• Tamamen değiştir: mevcut tüm veriler silinir.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('İptal'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, _ImportMode.merge),
            child: const Text('Birleştir'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            onPressed: () => Navigator.pop(context, _ImportMode.replace),
            child: const Text('Tamamen değiştir'),
          ),
        ],
      ),
    );
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final reminderHour = ref.watch(reminderHourProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Yedek & Ayarlar')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          children: [
            const SizedBox(height: 4),
            Text(
              'Verilerin yalnızca bu cihazda. Başka bir cihaza taşımak için '
              'dışa aktar, oradan içe aktar.',
              style: TextStyle(color: Theme.of(context).colorScheme.outline),
            ),
            const SizedBox(height: 24),
            _ActionCard(
              icon: Icons.upload_file,
              title: 'Dışa aktar',
              subtitle: 'Tüm alışkanlık ve kayıtları bir .json dosyasına yaz.',
              onTap: _busy ? null : _export,
            ),
            const SizedBox(height: 12),
            _ActionCard(
              icon: Icons.download,
              title: 'İçe aktar',
              subtitle:
                  'Bir .json yedeğinden geri yükle (birleştir veya değiştir).',
              onTap: _busy ? null : _import,
            ),
            const SizedBox(height: 24),
            Text('Sistem', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            Card(
              child: Column(
                children: [
                  if (LaunchAtLoginSetting.isSupported) ...[
                    SwitchListTile(
                      secondary: const Icon(Icons.power_settings_new),
                      title: const Text('Windows başlangıcında aç'),
                      subtitle: const Text(
                        'Oturum açılınca uygulama tepside başlar.',
                      ),
                      value: _launchAtLogin ?? false,
                      onChanged: _launchAtLogin == null
                          ? null
                          : _toggleLaunchAtLogin,
                    ),
                    const Divider(height: 1),
                  ],
                  SwitchListTile(
                    secondary: const Icon(Icons.notifications_outlined),
                    title: const Text('Akşam hatırlatıcısı'),
                    subtitle: Text(
                      reminderHour == null
                          ? 'Kapalı.'
                          : 'Bekleyen alışkanlık varsa saat '
                                '${reminderHour.toString().padLeft(2, '0')}:00\'da '
                                'bildirim gösterir.',
                    ),
                    value: reminderHour != null,
                    onChanged: (on) => ref
                        .read(reminderHourProvider.notifier)
                        .set(on ? AppConstants.defaultReminderHour : null),
                  ),
                  if (reminderHour != null)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                      child: Row(
                        children: [
                          Expanded(
                            child: Slider(
                              value: reminderHour.toDouble(),
                              min: 17,
                              max: 23,
                              divisions: 6,
                              label:
                                  '${reminderHour.toString().padLeft(2, '0')}:00',
                              onChanged: (v) => ref
                                  .read(reminderHourProvider.notifier)
                                  .set(v.round()),
                            ),
                          ),
                          SizedBox(
                            width: 48,
                            child: Text(
                              '${reminderHour.toString().padLeft(2, '0')}:00',
                              textAlign: TextAlign.end,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
            if (_busy) ...[
              const SizedBox(height: 24),
              const Center(child: CircularProgressIndicator()),
            ],
          ],
        ),
      ),
    );
  }
}

enum _ImportMode { merge, replace }

class _ActionCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;
  const _ActionCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: CircleAvatar(
          backgroundColor: scheme.primaryContainer,
          child: Icon(icon, color: scheme.onPrimaryContainer),
        ),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }
}
