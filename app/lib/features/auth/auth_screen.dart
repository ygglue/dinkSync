import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show AuthException;

import 'auth_repository.dart';

/// Email + OTP sign-in. Two steps:
///   1. Enter email -> tap "Send code" -> Supabase emails a 6-digit OTP.
///   2. Enter the code -> tap "Verify" -> session is created, router bounces
///      to /profile (a DB trigger auto-creates the profiles row on first login).
class AuthScreen extends ConsumerStatefulWidget {
  const AuthScreen({super.key});

  @override
  ConsumerState<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends ConsumerState<AuthScreen> {
  final _emailCtl = TextEditingController();
  final _otpCtl = TextEditingController();
  bool _codeSent = false;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _emailCtl.dispose();
    _otpCtl.dispose();
    super.dispose();
  }

  Future<void> _sendCode() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(authRepositoryProvider).sendOtp(_emailCtl.text);
      if (mounted) setState(() => _codeSent = true);
    } on AuthException catch (e) {
      setState(() => _error = e.message);
    } catch (_) {
      setState(() => _error = 'Could not send code. Check your connection.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _verify() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref
          .read(authRepositoryProvider)
          .verifyOtp(email: _emailCtl.text, token: _otpCtl.text);
      // On success the auth-state listener flips us to /profile.
    } on AuthException catch (e) {
      setState(() => _error = e.message);
    } catch (_) {
      setState(() => _error = 'Verification failed. Try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 380),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Hero
                Icon(Icons.sports_tennis,
                    size: 56, color: Theme.of(context).colorScheme.primary),
                const SizedBox(height: 12),
                Text(
                  'dinkSync',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
                const SizedBox(height: 6),
                Text(
                  _codeSent
                      ? 'Enter the 6-digit code we sent to your email.'
                      : 'Sign in or sign up with your email.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 24),

                TextField(
                  controller: _emailCtl,
                  enabled: !_codeSent,
                  keyboardType: TextInputType.emailAddress,
                  autofillHints: const ['email'],
                  decoration: const InputDecoration(
                    labelText: 'Email',
                    prefixIcon: Icon(Icons.mail_outline),
                  ),
                ),
                const SizedBox(height: 12),

                if (_codeSent) ...[
                  TextField(
                    controller: _otpCtl,
                    keyboardType: TextInputType.number,
                    autofocus: true,
                    decoration: const InputDecoration(
                      labelText: '6-digit code',
                      prefixIcon: Icon(Icons.password),
                    ),
                  ),
                  const SizedBox(height: 12),
                ],

                if (_error != null) ...[
                  Text(
                    _error!,
                    style: TextStyle(
                        color: Theme.of(context).colorScheme.error),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),
                ],

                FilledButton(
                  onPressed: _busy
                      ? null
                      : (_codeSent ? _verify : _sendCode),
                  child: _busy
                      ? const SizedBox(
                          height: 22,
                          width: 22,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(_codeSent ? 'Verify & continue' : 'Send code'),
                ),
                if (_codeSent)
                  TextButton(
                    onPressed: _busy ? null : _sendCode,
                    child: const Text('Resend code / change email'),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
