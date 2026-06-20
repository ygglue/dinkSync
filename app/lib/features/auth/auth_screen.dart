import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show AuthException, AuthResponse;

import 'auth_repository.dart';
import 'dev_accounts.dart';

/// Auth entry point. Email+password (Sign In / Sign Up tabs) plus
/// "Continue with Google" and a forgot-password flow. In debug builds a
/// dev-login panel offers one-tap sign-in as seeded identities.
class AuthScreen extends ConsumerStatefulWidget {
  const AuthScreen({super.key});

  @override
  ConsumerState<AuthScreen> createState() => _AuthScreenState();
}

enum _Mode { signIn, signUp }

class _AuthScreenState extends ConsumerState<AuthScreen> {
  final _emailCtl = TextEditingController();
  final _passwordCtl = TextEditingController();

  _Mode _mode = _Mode.signIn;
  bool _busy = false;
  bool _obscure = true;
  String? _error;
  String? _notice;

  @override
  void dispose() {
    _emailCtl.dispose();
    _passwordCtl.dispose();
    super.dispose();
  }

  AuthRepository get _repo => ref.read(authRepositoryProvider);

  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _error = null;
      _notice = null;
    });
    try {
      await action();
      // On success the auth-state listener redirects to /profile.
    } on AuthException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Something went wrong. Check your connection.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _submit() => _run(() async {
        if (_mode == _Mode.signIn) {
          await _repo.signInWithPassword(
            email: _emailCtl.text,
            password: _passwordCtl.text,
          );
        } else {
          final AuthResponse res = await _repo.signUpWithPassword(
            email: _emailCtl.text,
            password: _passwordCtl.text,
          );
          if (res.session == null && mounted) {
            setState(() => _notice =
                'Account created. Check your email to confirm, then sign in.');
          }
        }
      });

  Future<void> _google() => _run(() => _repo.signInWithGoogle());

  Future<void> _devLogin(DevAccount account) {
    assert(kDebugMode);
    if (!kDebugMode) return Future.value();
    return _run(() => _repo.signInWithPassword(
          email: account.email,
          password: kDevPassword,
        ));
  }

  Future<void> _openResetFlow() async {
    final sent = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _PasswordResetSheet(repo: _repo),
    );
    if (mounted && sent == true) {
      setState(() => _notice = 'If the email exists, a reset code was sent.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isSignIn = _mode == _Mode.signIn;
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
                Icon(Icons.sports_tennis,
                    size: 56, color: theme.colorScheme.primary),
                const SizedBox(height: 12),
                Text(
                  'dinkSync',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.headlineMedium
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 16),

                SegmentedButton<_Mode>(
                  segments: const [
                    ButtonSegment(value: _Mode.signIn, label: Text('Sign In')),
                    ButtonSegment(value: _Mode.signUp, label: Text('Sign Up')),
                  ],
                  selected: {_mode},
                  onSelectionChanged: _busy
                      ? null
                      : (s) => setState(() {
                            _mode = s.first;
                            _error = null;
                            _notice = null;
                          }),
                ),
                const SizedBox(height: 16),

                TextField(
                  controller: _emailCtl,
                  enabled: !_busy,
                  keyboardType: TextInputType.emailAddress,
                  autofillHints: const ['email'],
                  decoration: const InputDecoration(
                    labelText: 'Email',
                    prefixIcon: Icon(Icons.mail_outline),
                  ),
                ),
                const SizedBox(height: 12),

                TextField(
                  controller: _passwordCtl,
                  enabled: !_busy,
                  obscureText: _obscure,
                  decoration: InputDecoration(
                    labelText: 'Password',
                    prefixIcon: const Icon(Icons.lock_outline),
                    suffixIcon: IconButton(
                      icon: Icon(
                          _obscure ? Icons.visibility : Icons.visibility_off),
                      onPressed: () => setState(() => _obscure = !_obscure),
                    ),
                  ),
                ),

                if (isSignIn)
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: _busy ? null : _openResetFlow,
                      child: const Text('Forgot password?'),
                    ),
                  )
                else
                  const SizedBox(height: 12),

                if (_error != null) ...[
                  const SizedBox(height: 4),
                  Text(_error!,
                      textAlign: TextAlign.center,
                      style: TextStyle(color: theme.colorScheme.error)),
                ],
                if (_notice != null) ...[
                  const SizedBox(height: 4),
                  Text(_notice!, textAlign: TextAlign.center),
                ],
                const SizedBox(height: 12),

                FilledButton(
                  onPressed: _busy ? null : _submit,
                  child: _busy
                      ? const SizedBox(
                          height: 22,
                          width: 22,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : Text(isSignIn ? 'Sign in' : 'Create account'),
                ),
                const SizedBox(height: 8),

                OutlinedButton.icon(
                  onPressed: _busy ? null : _google,
                  icon: const Icon(Icons.login),
                  label: const Text('Continue with Google'),
                ),

                if (kDebugMode) _DevLoginPanel(busy: _busy, onPick: _devLogin),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// DEV ONLY. Compiled out of release builds via the `if (kDebugMode)` guard at
/// its single call site.
class _DevLoginPanel extends StatelessWidget {
  const _DevLoginPanel({required this.busy, required this.onPick});

  final bool busy;
  final Future<void> Function(DevAccount) onPick;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(children: [
            const Expanded(child: Divider()),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Text('DEV ONLY',
                  style: theme.textTheme.labelSmall
                      ?.copyWith(color: theme.colorScheme.outline)),
            ),
            const Expanded(child: Divider()),
          ]),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.center,
            children: [
              for (final account in kDevAccounts)
                OutlinedButton(
                  onPressed: busy ? null : () => onPick(account),
                  child: Text(account.label),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Bottom-sheet password reset: send code -> enter code -> set new password.
class _PasswordResetSheet extends StatefulWidget {
  const _PasswordResetSheet({required this.repo});
  final AuthRepository repo;

  @override
  State<_PasswordResetSheet> createState() => _PasswordResetSheetState();
}

enum _ResetStep { enterEmail, enterCode }

class _PasswordResetSheetState extends State<_PasswordResetSheet> {
  final _emailCtl = TextEditingController();
  final _codeCtl = TextEditingController();
  final _newPwCtl = TextEditingController();

  _ResetStep _step = _ResetStep.enterEmail;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _emailCtl.dispose();
    _codeCtl.dispose();
    _newPwCtl.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action,
      {VoidCallback? onSuccess}) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
      if (mounted && onSuccess != null) onSuccess();
    } on AuthException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Something went wrong. Try again.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _sendCode() => _run(
        () => widget.repo.sendPasswordResetOtp(_emailCtl.text),
        onSuccess: () => setState(() => _step = _ResetStep.enterCode),
      );

  void _finish() => _run(() async {
        await widget.repo.verifyPasswordResetOtp(
          email: _emailCtl.text,
          token: _codeCtl.text,
        );
        await widget.repo.updatePassword(_newPwCtl.text);
      }, onSuccess: () => Navigator.of(context).pop(true));

  @override
  Widget build(BuildContext context) {
    final onEmail = _step == _ResetStep.enterEmail;
    return Padding(
      padding: EdgeInsets.only(
        left: 24,
        right: 24,
        top: 24,
        bottom: 24 + MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Reset password',
              style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 16),
          if (onEmail)
            TextField(
              controller: _emailCtl,
              enabled: !_busy,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(
                labelText: 'Email',
                prefixIcon: Icon(Icons.mail_outline),
              ),
            )
          else ...[
            TextField(
              controller: _codeCtl,
              enabled: !_busy,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: '6-digit code',
                prefixIcon: Icon(Icons.password),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _newPwCtl,
              enabled: !_busy,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'New password',
                prefixIcon: Icon(Icons.lock_outline),
              ),
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!,
                textAlign: TextAlign.center,
                style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ],
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _busy ? null : (onEmail ? _sendCode : _finish),
            child: _busy
                ? const SizedBox(
                    height: 22,
                    width: 22,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : Text(onEmail ? 'Send code' : 'Set new password'),
          ),
        ],
      ),
    );
  }
}
