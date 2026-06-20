import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/app_config.dart';

/// Initializes the global Supabase client. Call once at startup (see main.dart).
Future<void> initSupabase(AppConfig config) async {
  await Supabase.initialize(
    url: config.supabaseUrl,
    // publishableKey (formerly anonKey) is safe to ship in the client: RLS,
    // not this key, is what actually protects data.
    publishableKey: config.supabaseAnonKey,
  );
}

/// Typed accessor for the singleton client.
SupabaseClient get supabase => Supabase.instance.client;

/// Riverpod provider for the auth state stream, so widgets can react to
/// sign-in / sign-out. Returns the current session or null.
final authStateProvider = StreamProvider<Session?>((ref) {
  return Supabase.instance.client.auth.onAuthStateChange.map((event) {
    return event.session;
  });
});

/// Convenience: is there a currently signed-in user?
final isSignedInProvider = Provider<bool>((ref) {
  return Supabase.instance.client.auth.currentSession != null;
});
