import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'app.dart';
import 'shared/desktop_integration.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Load locale data so Turkish date formatting works out of the box.
  await initializeDateFormatting('tr');

  // A container of its own (rather than one implicitly owned by
  // ProviderScope) so TrayService can read/watch providers from outside the
  // widget tree — the tray menu has to update even while no screen is
  // subscribed to today's habits.
  final container = ProviderContainer();
  await TrayService(container).init();

  runApp(
    UncontrolledProviderScope(container: container, child: const AktenakApp()),
  );
}
