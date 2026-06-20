import 'package:flutter_dotenv/flutter_dotenv.dart';

/// App-wide configuration loaded from .env at startup.
///
/// Phase 0: reads Supabase URL + anon key. These are safe to ship in a client
/// app because RLS (not the anon key) is what actually protects data.
class AppConfig {
  const AppConfig._({required this.supabaseUrl, required this.supabaseAnonKey});

  final String supabaseUrl;
  final String supabaseAnonKey;

  /// Load .env and return a populated config. Throws if values are missing.
  static Future<AppConfig> load() async {
    await dotenv.load(fileName: '.env');
    final url = dotenv.maybeGet('SUPABASE_URL') ?? '';
    final anon = dotenv.maybeGet('SUPABASE_ANON_KEY') ?? '';
    if (url.isEmpty || anon.isEmpty || url.startsWith('your-')) {
      throw const AppConfigError(
        'Missing Supabase config. Copy .env.example to .env and fill in '
        'SUPABASE_URL and SUPABASE_ANON_KEY from your Supabase project.',
      );
    }
    return AppConfig._(supabaseUrl: url, supabaseAnonKey: anon);
  }
}

class AppConfigError implements Exception {
  const AppConfigError(this.message);
  final String message;
  @override
  String toString() => 'AppConfigError: $message';
}
