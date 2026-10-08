import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'app.dart';
import 'data/data_location.dart';
import 'data/providers.dart';
import 'shared/desktop_integration.dart';

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  // Load locale data so Turkish date formatting works out of the box.
  await initializeDateFormatting('tr');

  // Before anything opens the database: pull back data v1.2.x wrote to the
  // wrong folder (see data_location.dart).
  final stray = strayV12Directory();
  if (stray != null) {
    try {
      await recoverStrayV12Data(
        canonical: await appDataDirectory(),
        stray: stray,
        now: DateTime.now(),
      );
    } catch (_) {
      // The stray file stays untouched on failure; next launch retries.
    }
  }

  // A container of its own (rather than one implicitly owned by
  // ProviderScope) so TrayService can read/watch providers from outside the
  // widget tree — the tray menu has to update even while no screen is
  // subscribed to today's habits.
  final container = ProviderContainer();
  final tray = TrayService(container, startInTray: args.contains('--tray'));
  await tray.init();

  _startAutoBackup(container);

  runApp(
    UncontrolledProviderScope(container: container, child: const AktenakApp()),
  );
  WidgetsBinding.instance.addPostFrameCallback((_) => tray.onFirstFrame());
}

/// Daily JSON backup into `<data dir>/yedekler/`. Checked hourly so an app
/// that lives in the tray for days still backs up every day.
void _startAutoBackup(ProviderContainer container) {
  Future<void> run() async {
    try {
      final backup = await container.read(autoBackupProvider.future);
      await backup.runIfDue(DateTime.now());
    } catch (_) {
      // A failed backup must never take the app down; next hour retries.
    }
  }

  unawaited(run());
  Timer.periodic(const Duration(hours: 1), (_) => run());
}
