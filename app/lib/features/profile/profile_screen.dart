import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme.dart';
import '../../data/capabilities.dart';
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
  final _avatarFocus = FocusNode();
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
    _avatarFocus.dispose();
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

    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isManager =
        ref.watch(capabilitiesProvider).valueOrNull?.isManager ?? false;
    final displayName = _nameCtl.text.trim();
    final initial = (displayName.isEmpty
            ? (email.isNotEmpty ? email[0] : '?')
            : displayName[0])
        .toUpperCase();

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Profile',
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.bold,
            color: scheme.primary,
          ),
        ),
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
              padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_error != null) ...[
                    Text(
                      _error!,
                      style: TextStyle(color: scheme.error),
                    ),
                    const SizedBox(height: 12),
                  ],

                  // Identity block — avatar with an edit affordance.
                  Center(
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Container(
                          width: 96,
                          height: 96,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: scheme.primary.withValues(alpha: 0.10),
                            border: Border.all(color: scheme.surface, width: 4),
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            initial,
                            style: theme.textTheme.headlineMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: scheme.primary,
                            ),
                          ),
                        ),
                        Positioned(
                          right: -2,
                          bottom: -2,
                          child: Material(
                            color: kBrandGreen,
                            shape: const CircleBorder(),
                            child: InkWell(
                              customBorder: const CircleBorder(),
                              onTap: () => _avatarFocus.requestFocus(),
                              child: const Padding(
                                padding: EdgeInsets.all(6),
                                child: Icon(Icons.edit,
                                    size: 16, color: Colors.white),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (displayName.isNotEmpty)
                    Text(
                      displayName,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w600),
                    ),
                  const SizedBox(height: 2),
                  Text(
                    email,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: 16),

                  // MMR + role badges.
                  Wrap(
                    spacing: 8,
                    alignment: WrapAlignment.center,
                    children: [
                      _StatChip(
                        icon: Icons.trending_up,
                        label: 'MMR $mmr',
                        tinted: true,
                      ),
                      if (isAdmin)
                        const _StatChip(
                          icon: Icons.shield,
                          label: 'Admin',
                          tinted: false,
                        ),
                    ],
                  ),
                  const SizedBox(height: 28),

                  TextField(
                    controller: _nameCtl,
                    onChanged: (_) => setState(() {}),
                    decoration: const InputDecoration(
                      labelText: 'Display name',
                      prefixIcon: Icon(Icons.person_outline),
                    ),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: _avatarCtl,
                    focusNode: _avatarFocus,
                    keyboardType: TextInputType.url,
                    decoration: const InputDecoration(
                      labelText: 'Avatar URL (optional)',
                      prefixIcon: Icon(Icons.image_outlined),
                    ),
                  ),
                  const SizedBox(height: 24),
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
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: _signOut,
                    icon: const Icon(Icons.logout),
                    label: const Text('Sign out'),
                  ),
                  if (!isManager) ...[
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: () => context.push('/onboard'),
                      icon: const Icon(Icons.storefront_outlined),
                      label: const Text('Own a court? Set it up'),
                    ),
                  ],

                  const SizedBox(height: 28),
                  // RLS probe result — visible so the Phase 0 demo is explicit.
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: scheme.surfaceContainerHighest
                          .withValues(alpha: 0.6),
                      borderRadius: BorderRadius.circular(kRadius),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: scheme.surface,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(Icons.lock_outline,
                              size: 18, color: scheme.primary),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'SECURITY ACCESS',
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: scheme.outline,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 1.0,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                _rlsNote,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: scheme.onSurfaceVariant,
                                ),
                              ),
                            ],
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

/// Small rounded badge for a stat (e.g. "MMR 1050") or role (e.g. "Admin").
/// [tinted] gives it a green-tinted background; otherwise it's neutral.
class _StatChip extends StatelessWidget {
  const _StatChip({
    required this.icon,
    required this.label,
    required this.tinted,
  });

  final IconData icon;
  final String label;
  final bool tinted;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final bg = tinted
        ? scheme.primary.withValues(alpha: 0.08)
        : const Color(0xFFF1F5F9);
    final fg = tinted ? scheme.primary : scheme.onSurfaceVariant;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: fg),
          const SizedBox(width: 6),
          Text(
            label,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: const Color(0xFF1F2937),
                ),
          ),
        ],
      ),
    );
  }
}
