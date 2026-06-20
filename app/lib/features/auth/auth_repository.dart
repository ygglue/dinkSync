import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../data/supabase_client.dart';

/// Thin wrapper around Supabase Auth. Centralizes error handling and keeps
/// widgets free of supabase-specific calls. Phase 0 uses email + OTP:
///   1. signIn / signUp sends a 6-digit code to the user's email.
///   2. verifyOtp exchanges the code for a session.
/// (Password auth, social, and deep links come in later phases.)
class AuthRepository {
  AuthRepository(this._client);
  final SupabaseClient _client;

  /// Sends an OTP to [email]. Works for both sign-up and sign-in — Supabase
  /// creates the user if they don't exist.
  Future<void> sendOtp(String email) async {
    await _client.auth.signInWithOtp(
      email: email.trim(),
      emailRedirectTo: null,
      shouldCreateUser: true,
    );
  }

  /// Exchanges the OTP for a session. Throws on wrong/expired code.
  Future<void> verifyOtp({required String email, required String token}) async {
    await _client.auth.verifyOTP(
      email: email.trim(),
      token: token.trim(),
      type: OtpType.email,
    );
  }

  Future<void> signOut() async {
    await _client.auth.signOut();
  }

  User? get currentUser => _client.auth.currentUser;
  String? get currentEmail => _client.auth.currentUser?.email;
}

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return AuthRepository(supabase);
});
