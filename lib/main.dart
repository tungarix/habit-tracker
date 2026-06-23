import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Load locale data so Turkish date formatting works out of the box.
  await initializeDateFormatting('tr');
  runApp(const ProviderScope(child: AktenakApp()));
}
