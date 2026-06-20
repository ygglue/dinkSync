import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../data/supabase_client.dart';

/// Thin wrapper around Supabase Auth. Centralizes auth calls so widgets stay
/// free of supabase-specific code.
///
/// Primary sign-in is email+password and Google OAuth (web). Email OTP is
/// retained only as the password-reset mechanism (recovery type).
class AuthRepository {
  AuthRepository(this._client);
  final SupabaseClient _client;

  /// Sign in an existing user. Throws [AuthException] on bad credentials.
  Future<void> signInWithPassword({
    required String email,
    required String password,
  }) async {
    await _client.auth.signInWithPassword(
      email: email.trim(),
      password: password,
    );
  }

  /// Create a new account. Throws [AuthException] if the email is taken.
  /// Returns the [AuthResponse] so callers can detect a null session (email
  /// confirmation required).
  Future<AuthResponse> signUpWithPassword({
    required String email,
    required String password,
  }) {
    return _client.auth.signUp(
      email: email.trim(),
      password: password,
    );
  }

  /// Start the Google OAuth redirect flow (web). Returns the launch result.
  Future<bool> signInWithGoogle() {
    return _client.auth.signInWithOAuth(OAuthProvider.google);
  }

  /// Step 1 of password reset: email the user a recovery code.
  Future<void> sendPasswordResetOtp(String email) async {
    await _client.auth.resetPasswordForEmail(email.trim());
  }

  /// Step 2 of password reset: exchange the recovery code for a session.
  /// Throws [AuthException] on a wrong/expired code.
  Future<void> verifyPasswordResetOtp({
    required String email,
    required String token,
  }) async {
    await _client.auth.verifyOTP(
      email: email.trim(),
      token: token.trim(),
      type: OtpType.recovery,
    );
  }

  /// Step 3 of password reset: set the new password on the recovered session.
  Future<void> updatePassword(String newPassword) async {
    await _client.auth.updateUser(UserAttributes(password: newPassword));
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
