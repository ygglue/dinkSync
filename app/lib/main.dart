import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show Session;

import 'app/router.dart';
import 'app/theme.dart';
import 'config/app_config.dart';
import 'data/app_mode.dart';
import 'data/capabilities.dart';
import 'data/supabase_client.dart';
import 'features/owner/court_repository.dart';

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
    // When the signed-in user changes (sign in / out / switch account), drop
    // user-scoped caches so the previous account's court and manager status
    // don't leak into the next session.
    ref.listen<AsyncValue<Session?>>(authStateProvider, (prev, next) {
      if (prev?.valueOrNull?.user.id != next.valueOrNull?.user.id) {
        ref.invalidate(ownerCourtProvider);
        ref.invalidate(capabilitiesProvider);
      }
    });

    return MaterialApp.router(
      title: 'dinkSync',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      routerConfig: ref.watch(routerProvider),
    );
  }
}
