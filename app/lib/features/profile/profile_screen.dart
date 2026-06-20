import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/supabase_client.dart';

/// Profile screen — the Phase 0 destination after sign-in.
///
/// Proves the Phase 0 contract end-to-end:
///   - On load, reads the signed-in user's own profiles row (RLS: self read).
///   - Lets the user edit display_name + avatar_url (RLS: self write only).
///   - Shows the Elo MMR (read-only here; updated by RPC in Phase 2).
///   - Includes a "RLS probe" that tries to read someone else's row by id —
///     it returns empty, demonstrating that RLS blocks cross-user reads even
///     though the anon key is in the client.
class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  final _nameCtl = TextEditingController();
  final _avatarCtl = TextEditingController();
  Map<String, dynamic>? _profile;
  bool _loading = true;
  bool _saving = false;
  String? _error;
  String _rlsNote = '';

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  @override
  void dispose() {
    _nameCtl.dispose();
    _avatarCtl.dispose();
    super.dispose();
  }

  Future<void> _loadProfile() async {
    final uid = supabase.auth.currentUser?.id;
    if (uid == null) {
      setState(() {
        _loading = false;
        _error = 'Not signed in.';
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      // Own row — RLS self-read policy allows this.
      final rows = await supabase
          .from('profiles')
          .select()
          .eq('id', uid)
          .limit(1);
      final p = (rows as List).isEmpty ? null : rows.first;

      // RLS probe: try to read a (almost certainly) non-self id by filtering
      // on id != uid. With RLS this returns zero rows for other users.
      final other = await supabase
          .from('profiles')
          .select('id, display_name')
          .neq('id', uid)
          .limit(1);

      setState(() {
        _profile = p;
        _nameCtl.text = (p?['display_name'] as String?) ?? '';
        _avatarCtl.text = (p?['avatar_url'] as String?) ?? '';
        _rlsNote = (other as List).isEmpty
            ? 'RLS probe: cannot see other users\' rows. ✓'
            : 'RLS probe WARNING: saw another user\'s row. ✗';
      });
    } catch (e) {
      setState(() => _error = 'Failed to load profile: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    final uid = supabase.auth.currentUser?.id;
    if (uid == null) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await supabase.from('profiles').update({
        'display_name': _nameCtl.text.trim(),
        'avatar_url': _avatarCtl.text.trim().isEmpty
            ? null
            : _avatarCtl.text.trim(),
      }).eq('id', uid);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Profile saved.')),
        );
      }
      await _loadProfile();
    } catch (e) {
      setState(() => _error = 'Save failed: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _signOut() async {
    await supabase.auth.signOut();
    // Router redirect sends us back to /auth.
  }

  @override
  Widget build(BuildContext context) {
    final email = supabase.auth.currentUser?.email ?? '';
    final mmr = _profile?['mmr'] as int? ?? 1000;
    final isAdmin =
        (_profile?['is_platform_admin'] as bool?) ?? false;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Profile'),
        actions: [
          IconButton(
            onPressed: _loading ? null : _loadProfile,
            icon: const Icon(Icons.refresh),
            tooltip: 'Reload',
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_error != null) ...[
                    Text(
                      _error!,
                      style: TextStyle(
                          color: Theme.of(context).colorScheme.error),
                    ),
                    const SizedBox(height: 12),
                  ],
                  // Identity summary
                  CircleAvatar(
                    radius: 36,
                    backgroundColor:
                        Theme.of(context).colorScheme.primaryContainer,
                    child: Text(
                      (_nameCtl.text.isEmpty
                              ? (email.isNotEmpty ? email[0] : '?')
                              : _nameCtl.text[0])
                          .toUpperCase(),
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    email,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 16),

                  // MMR chip + admin badge
                  Wrap(
                    spacing: 8,
                    alignment: WrapAlignment.center,
                    children: [
                      Chip(
                        avatar: const Icon(Icons.trending_up, size: 18),
                        label: Text('MMR $mmr'),
                      ),
                      if (isAdmin)
                        const Chip(
                          avatar: Icon(Icons.shield, size: 18),
                          label: Text('Admin'),
                        ),
                    ],
                  ),
                  const SizedBox(height: 24),

                  TextField(
                    controller: _nameCtl,
                    decoration: const InputDecoration(
                      labelText: 'Display name',
                      prefixIcon: Icon(Icons.person_outline),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _avatarCtl,
                    decoration: const InputDecoration(
                      labelText: 'Avatar URL (optional)',
                      prefixIcon: Icon(Icons.image_outlined),
                    ),
                  ),
                  const SizedBox(height: 20),
                  FilledButton.icon(
                    onPressed: _saving ? null : _save,
                    icon: _saving
                        ? const SizedBox(
                            height: 18,
                            width: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.save_outlined),
                    label: const Text('Save profile'),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: _signOut,
                    icon: const Icon(Icons.logout),
                    label: const Text('Sign out'),
                  ),

                  const SizedBox(height: 28),
                  // RLS probe result — visible so the Phase 0 demo is explicit.
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Theme.of(context)
                          .colorScheme
                          .surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.lock_outline,
                            size: 18,
                            color: Theme.of(context).colorScheme.primary),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _rlsNote,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}
