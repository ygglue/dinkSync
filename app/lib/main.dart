import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app/router.dart';
import 'app/theme.dart';
import 'config/app_config.dart';
import 'data/app_mode.dart';
import 'data/supabase_client.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Load .env + initialize Supabase. Fails loudly if .env is unconfigured.
  final config = await AppConfig.load();
  await initSupabase(config);
  final prefs = await SharedPreferences.getInstance();

  runApp(
    ProviderScope(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      child: const DinkSyncApp(),
    ),
  );
}

class DinkSyncApp extends ConsumerWidget {
  const DinkSyncApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp.router(
      title: 'dinkSync',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      routerConfig: ref.watch(routerProvider),
    );
  }
}
