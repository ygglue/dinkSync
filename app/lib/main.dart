import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/router.dart';
import 'app/theme.dart';
import 'config/app_config.dart';
import 'data/supabase_client.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Load .env + initialize Supabase. Fails loudly if .env is unconfigured.
  final config = await AppConfig.load();
  await initSupabase(config);

  runApp(const ProviderScope(child: DinkSyncApp()));
}

class DinkSyncApp extends StatelessWidget {
  const DinkSyncApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'dinkSync',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      routerConfig: buildRouter(),
    );
  }
}
