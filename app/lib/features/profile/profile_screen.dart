import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show FileOptions;

import '../../app/theme.dart';
import '../../data/capabilities.dart';
import '../../data/supabase_client.dart';
import 'appearance_selector.dart';

class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen>
    with SingleTickerProviderStateMixin {
  final _nameCtl = TextEditingController();
  final _nameFocus = FocusNode();
  late final AnimationController _saveAnim;
  Map<String, dynamic>? _profile;
  bool _loading = true;
  bool _saving = false;
  bool _editing = false;
  String? _error;
  Uint8List? _pendingImageBytes;
  String? _pendingImageExt;

  bool get _hasChanges {
    final original = (_profile?['display_name'] as String?) ?? '';
    return _nameCtl.text.trim() != original || _pendingImageBytes != null;
  }

  @override
  void initState() {
    super.initState();
    _saveAnim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 380),
    );
    _loadProfile();
  }

  @override
  void dispose() {
    _saveAnim.dispose();
    _nameCtl.dispose();
    _nameFocus.dispose();
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
      final rows = await supabase
          .from('profiles')
          .select()
          .eq('id', uid)
          .limit(1);
      final p = (rows as List).isEmpty ? null : rows.first;
      setState(() {
        _profile = p;
        _nameCtl.text = (p?['display_name'] as String?) ?? '';
      });
    } catch (e) {
      setState(() => _error = 'Failed to load profile: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _startEditing() {
    setState(() => _editing = true);
    _saveAnim.forward();
    WidgetsBinding.instance.addPostFrameCallback((_) => _nameFocus.requestFocus());
  }

  void _cancelEditing() {
    _nameFocus.unfocus();
    // Revert edit state immediately; save button slides away on its own.
    setState(() {
      _editing = false;
      _pendingImageBytes = null;
      _pendingImageExt = null;
      _nameCtl.text = (_profile?['display_name'] as String?) ?? '';
    });
    _saveAnim.reverse();
  }

  Future<void> _pickImage() async {
    final img = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 512,
      imageQuality: 85,
    );
    if (img == null || !mounted) return;
    final bytes = await img.readAsBytes();
    setState(() {
      _pendingImageBytes = bytes;
      _pendingImageExt = img.path.contains('.')
          ? img.path.split('.').last.toLowerCase()
          : 'jpg';
    });
  }

  Future<void> _save() async {
    final uid = supabase.auth.currentUser?.id;
    if (uid == null) return;
    _nameFocus.unfocus();
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      String? avatarUrl = _profile?['avatar_url'] as String?;
      if (_pendingImageBytes != null) {
        final ext = _pendingImageExt ?? 'jpg';
        final path = '$uid/avatar.$ext';
        await supabase.storage.from('avatars').uploadBinary(
          path,
          _pendingImageBytes!,
          fileOptions: const FileOptions(upsert: true),
        );
        avatarUrl = supabase.storage.from('avatars').getPublicUrl(path);
      }
      await supabase.from('profiles').update({
        'display_name': _nameCtl.text.trim(),
        'avatar_url': avatarUrl,
      }).eq('id', uid);
      setState(() {
        _editing = false;
        _pendingImageBytes = null;
        _pendingImageExt = null;
      });
      _saveAnim.reverse();
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Profile saved.')));
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
  }

  @override
  Widget build(BuildContext context) {
    final email = supabase.auth.currentUser?.email ?? '';
    final uid = supabase.auth.currentUser?.id ?? '';
    final mmr = _profile?['mmr'] as int? ?? 1000;
    final isAdmin = (_profile?['is_platform_admin'] as bool?) ?? false;
    final isManager =
        ref.watch(capabilitiesProvider).valueOrNull?.isManager ?? false;

    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final displayName = _nameCtl.text.trim();
    final initial = (displayName.isEmpty
            ? (email.isNotEmpty ? email[0] : '?')
            : displayName[0])
        .toUpperCase();
    final cardId =
        uid.length >= 6 ? uid.substring(0, 6).toUpperCase() : '——';
    final avatarUrl = _profile?['avatar_url'] as String?;

    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        title: Text(
          'Profile',
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.bold,
            color: scheme.primary,
          ),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // ── Scrollable content ─────────────────────────────────────
                Expanded(
                  child: RefreshIndicator(
                    onRefresh: _loadProfile,
                    child: SingleChildScrollView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (_error != null) ...[
                            Text(_error!,
                                style: TextStyle(color: scheme.error)),
                            const SizedBox(height: 12),
                          ],

                          // Trading card + floating edit toggle
                          Stack(
                            clipBehavior: Clip.none,
                            children: [
                              _PlayerCard(
                                initial: initial,
                                displayName: displayName,
                                email: email,
                                mmr: mmr,
                                isAdmin: isAdmin,
                                cardId: cardId,
                                avatarUrl: avatarUrl,
                                editing: _editing,
                                saving: _saving,
                                hasChanges: _hasChanges,
                                saveAnim: _saveAnim,
                                pendingImageBytes: _pendingImageBytes,
                                nameCtl: _nameCtl,
                                nameFocus: _nameFocus,
                                onPickImage: _pickImage,
                                onSaveChanges: _save,
                                onNameChanged: () => setState(() {}),
                              ),
                              Positioned(
                                top: 12,
                                right: 12,
                                child: _EditToggle(
                                  editing: _editing,
                                  onTap: _editing
                                      ? _cancelEditing
                                      : _startEditing,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 24),

                          if (!isManager) ...[
                            OutlinedButton.icon(
                              onPressed: () => context.push('/onboard'),
                              icon: Icon(PhosphorIconsFill.storefront),
                              label: const Text('Own a court? Set it up'),
                            ),
                            const SizedBox(height: 24),
                          ],
                          const AppearanceSelector(),
                          const SizedBox(height: 16),
                          Divider(color: scheme.outlineVariant, height: 1),
                          const SizedBox(height: 16),
                          OutlinedButton.icon(
                            onPressed: _signOut,
                            style: OutlinedButton.styleFrom(
                              foregroundColor: scheme.error,
                              side: BorderSide(
                                color: scheme.error.withValues(alpha: 0.5),
                              ),
                              minimumSize: const Size.fromHeight(56),
                            ),
                            icon: Icon(PhosphorIconsFill.signOut),
                            label: const Text('Sign out'),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}

// ── Edit toggle button ────────────────────────────────────────────────────────

class _EditToggle extends StatelessWidget {
  const _EditToggle({required this.editing, required this.onTap});

  final bool editing;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = editing ? scheme.error : scheme.primary;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: const Color(0xFF232821),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: color, width: 1),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(PhosphorIconsFill.pencilSimple, size: 13, color: color),
            const SizedBox(width: 5),
            Text(
              editing ? 'Cancel' : 'Edit',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Player card ───────────────────────────────────────────────────────────────

class _PlayerCard extends StatelessWidget {
  const _PlayerCard({
    required this.initial,
    required this.displayName,
    required this.email,
    required this.mmr,
    required this.isAdmin,
    required this.cardId,
    this.avatarUrl,
    required this.editing,
    required this.saving,
    required this.hasChanges,
    required this.saveAnim,
    this.pendingImageBytes,
    required this.nameCtl,
    required this.nameFocus,
    required this.onPickImage,
    required this.onSaveChanges,
    required this.onNameChanged,
  });

  final String initial;
  final String displayName;
  final String email;
  final int mmr;
  final bool isAdmin;
  final String cardId;
  final String? avatarUrl;
  final bool editing;
  final bool saving;
  final bool hasChanges;
  final Animation<double> saveAnim;
  final Uint8List? pendingImageBytes;
  final TextEditingController nameCtl;
  final FocusNode nameFocus;
  final VoidCallback onPickImage;
  final VoidCallback onSaveChanges;
  final VoidCallback onNameChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final theme = Theme.of(context);

    return Container(
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(kRadius),
        border: Border.all(
          color: scheme.primary.withValues(alpha: 0.28),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF2E7D32).withValues(alpha: 0.16),
            blurRadius: 28,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: Alignment.topLeft,
                  radius: 1.2,
                  colors: [
                    scheme.primary.withValues(alpha: 0.12),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
          Column(
        children: [
          // Green gradient header with avatar
          _CardHeader(
            initial: initial,
            cardId: cardId,
            avatarUrl: avatarUrl,
            pendingImageBytes: pendingImageBytes,
            editing: editing,
            onPickImage: onPickImage,
          ),

          // Body
          Padding(
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Name: text in view mode, focused field in edit mode
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 180),
                    child: editing
                        ? TextField(
                            key: const ValueKey('name-edit'),
                            controller: nameCtl,
                            focusNode: nameFocus,
                            onChanged: (_) => onNameChanged(),
                            textAlign: TextAlign.center,
                            style: theme.textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.w700,
                              letterSpacing: -0.5,
                            ),
                            decoration: InputDecoration(
                              filled: false,
                              border: UnderlineInputBorder(
                                borderSide: BorderSide(
                                    color: scheme.outlineVariant),
                              ),
                              enabledBorder: UnderlineInputBorder(
                                borderSide: BorderSide(
                                    color: scheme.outlineVariant),
                              ),
                              focusedBorder: UnderlineInputBorder(
                                borderSide: BorderSide(
                                    color: scheme.primary, width: 2),
                              ),
                              contentPadding:
                                  const EdgeInsets.symmetric(vertical: 6),
                            ),
                          )
                        : Padding(
                            key: const ValueKey('name-view'),
                            padding:
                                const EdgeInsets.symmetric(vertical: 4),
                            child: Text(
                              displayName.isEmpty ? '—' : displayName,
                              textAlign: TextAlign.center,
                              style: theme.textTheme.titleLarge?.copyWith(
                                fontWeight: FontWeight.w700,
                                letterSpacing: -0.5,
                              ),
                            ),
                          ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    email,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: scheme.onSurfaceVariant),
                  ),

                  // Save Changes — always in tree, slides up/down via saveAnim
                  SizeTransition(
                    sizeFactor: CurvedAnimation(
                      parent: saveAnim,
                      curve: Curves.easeOut,
                      reverseCurve: Curves.easeIn,
                    ),
                    alignment: Alignment.bottomCenter,
                    child: FadeTransition(
                      opacity: CurvedAnimation(
                        parent: saveAnim,
                        curve: const Interval(0.25, 1.0, curve: Curves.easeIn),
                        reverseCurve: const Interval(0.0, 0.75, curve: Curves.easeOut),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const SizedBox(height: 16),
                          FilledButton(
                            onPressed: (saving || !hasChanges) ? null : onSaveChanges,
                            child: saving
                                ? const SizedBox(
                                    height: 18,
                                    width: 18,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2),
                                  )
                                : const Text('Save Changes'),
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 20),
                  Divider(color: scheme.outlineVariant, height: 1),
                  const SizedBox(height: 20),

                  // Stats row
                  IntrinsicHeight(
                    child: Row(
                      children: [
                        Expanded(
                          child: _CardStat(
                            icon: PhosphorIconsFill.trendUp,
                            label: 'MMR',
                            value: '$mmr',
                          ),
                        ),
                        VerticalDivider(
                            color: scheme.outlineVariant,
                            width: 1,
                            thickness: 1),
                        Expanded(
                          child: _CardStat(
                            icon: PhosphorIconsFill.chartBar,
                            label: 'RANK',
                            value: '—',
                          ),
                        ),
                        if (isAdmin) ...[
                          VerticalDivider(
                              color: scheme.outlineVariant,
                              width: 1,
                              thickness: 1),
                          Expanded(
                            child: _CardStat(
                              icon: PhosphorIconsFill.shield,
                              label: 'ROLE',
                              value: 'Admin',
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
        ],
      ),
    );
  }
}

// ── Card header ───────────────────────────────────────────────────────────────

class _CardHeader extends StatelessWidget {
  const _CardHeader({
    required this.initial,
    required this.cardId,
    this.avatarUrl,
    this.pendingImageBytes,
    required this.editing,
    required this.onPickImage,
  });

  final String initial;
  final String cardId;
  final String? avatarUrl;
  final Uint8List? pendingImageBytes;
  final bool editing;
  final VoidCallback onPickImage;

  static const _darkGreen = Color(0xFF2E7D32);
  static const _midGreen = Color(0xFF43A047);

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [_darkGreen, _midGreen],
        ),
      ),
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
      child: Column(
        children: [
          // PLAYER label (left) — card ID intentionally omitted to leave
          // room for the floating edit button in the top-right corner.
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'PLAYER',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.55),
                fontSize: 10,
                fontWeight: FontWeight.w700,
                letterSpacing: 2.5,
              ),
            ),
          ),
          const SizedBox(height: 20),

          // Avatar — tappable in edit mode
          GestureDetector(
            onTap: editing ? onPickImage : null,
            child: Stack(
              alignment: Alignment.center,
              children: [
                // Circle frame
                Container(
                  width: 100,
                  height: 100,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white.withValues(alpha: 0.15),
                    border: Border.all(color: Colors.white, width: 3),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: _AvatarContent(
                    initial: initial,
                    avatarUrl: avatarUrl,
                    pendingImageBytes: pendingImageBytes,
                  ),
                ),
                // Camera overlay in edit mode
                if (editing)
                  Container(
                    width: 100,
                    height: 100,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.black.withValues(alpha: 0.38),
                    ),
                    child: Icon(
                      PhosphorIconsFill.image,
                      color: Colors.white,
                      size: 28,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AvatarContent extends StatelessWidget {
  const _AvatarContent({
    required this.initial,
    this.avatarUrl,
    this.pendingImageBytes,
  });

  final String initial;
  final String? avatarUrl;
  final Uint8List? pendingImageBytes;

  @override
  Widget build(BuildContext context) {
    if (pendingImageBytes != null) {
      return Image.memory(pendingImageBytes!,
          fit: BoxFit.cover, width: 100, height: 100);
    }
    if (avatarUrl != null && avatarUrl!.isNotEmpty) {
      return Image.network(
        avatarUrl!,
        fit: BoxFit.cover,
        width: 100,
        height: 100,
        errorBuilder: (_, _, _) => _Initials(initial: initial),
      );
    }
    return _Initials(initial: initial);
  }
}

class _Initials extends StatelessWidget {
  const _Initials({required this.initial});
  final String initial;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        initial,
        style: const TextStyle(
          fontSize: 40,
          color: Colors.white,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}


// ── Stat cell ─────────────────────────────────────────────────────────────────

class _CardStat extends StatelessWidget {
  const _CardStat({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 18, color: scheme.primary),
        const SizedBox(height: 6),
        Text(
          value,
          style: theme.textTheme.titleMedium
              ?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: theme.textTheme.labelSmall?.copyWith(
            color: scheme.onSurfaceVariant,
            letterSpacing: 1.5,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}
