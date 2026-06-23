import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme.dart';
import '../../data/court.dart';
import 'booking_repository.dart';

/// Body of the Play shell's first tab: the game lobby.
/// Body-only — PlayShell supplies the AppBar and floating nav.
class LobbyScreen extends ConsumerStatefulWidget {
  const LobbyScreen({super.key, this.initialCourt});
  final Court? initialCourt;

  @override
  ConsumerState<LobbyScreen> createState() => _LobbyScreenState();
}

class _LobbyScreenState extends ConsumerState<LobbyScreen> {
  Court? _selectedCourt;

  @override
  void initState() {
    super.initState();
    _selectedCourt = widget.initialCourt;
  }

  Future<void> _pickCourt() async {
    final court = await context.push<Court>('/play/courts');
    if (court != null && mounted) setState(() => _selectedCourt = court);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final profileAsync = ref.watch(currentUserProfileProvider);
    final profile = profileAsync.valueOrNull ??
        const LobbyProfile(displayName: 'Player', mmr: 1000);
    final canBook =
        _selectedCourt != null && _selectedCourt!.customFeeCents != null;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Court selector
          Material(
            color: scheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(kRadius),
            child: InkWell(
              borderRadius: BorderRadius.circular(kRadius),
              onTap: _pickCourt,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Icon(
                      Icons.stadium_outlined,
                      color: _selectedCourt != null
                          ? scheme.primary
                          : scheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        _selectedCourt?.name ?? 'Select a court',
                        style: theme.textTheme.titleMedium?.copyWith(
                          color: _selectedCourt != null
                              ? null
                              : scheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                    Icon(Icons.chevron_right, color: scheme.onSurfaceVariant),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 24),
          // Player slots — let them grow to fill available space.
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: _PlayerSlot(profile: profile)),
                const SizedBox(width: 12),
                const Expanded(child: _PartnerSlot()),
              ],
            ),
          ),
          const SizedBox(height: 24),
          // Find Match — primary CTA, tall and prominent.
          FilledButton(
            onPressed: null,
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(56),
              textStyle: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.3,
              ),
            ),
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.sports_tennis, size: 20),
                SizedBox(width: 10),
                Text('Find Match'),
              ],
            ),
          ),
          const SizedBox(height: 10),
          // Book a Court — secondary CTA.
          OutlinedButton(
            onPressed: canBook
                ? () => context.push('/play/custom', extra: _selectedCourt)
                : null,
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(48),
            ),
            child: const Text('Book a Court'),
          ),
        ],
      ),
    );
  }
}

class _PlayerSlot extends StatelessWidget {
  const _PlayerSlot({required this.profile});
  final LobbyProfile profile;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final initial =
        profile.displayName.isNotEmpty ? profile.displayName[0].toUpperCase() : '?';
    return Container(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(kRadius),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircleAvatar(
            radius: 36,
            backgroundColor: scheme.primary.withValues(alpha: 0.12),
            child: Text(
              initial,
              style: theme.textTheme.headlineMedium?.copyWith(
                color: scheme.primary,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            profile.displayName,
            style: theme.textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.w700),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 6),
          // MMR badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: scheme.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(100),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.bar_chart_rounded,
                    size: 14, color: scheme.primary),
                const SizedBox(width: 4),
                Text(
                  '${profile.mmr} MMR',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: scheme.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'You',
            style: theme.textTheme.labelSmall
                ?.copyWith(color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

class _PartnerSlot extends StatelessWidget {
  const _PartnerSlot();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(kRadius),
        border: Border.all(
          color: scheme.outlineVariant,
          width: 1.5,
          strokeAlign: BorderSide.strokeAlignInside,
        ),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.person_add_outlined,
              size: 52, color: scheme.onSurfaceVariant.withValues(alpha: 0.5)),
          const SizedBox(height: 12),
          Text(
            'Invite partner',
            style: theme.textTheme.titleSmall
                ?.copyWith(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: scheme.outlineVariant.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(100),
            ),
            child: Text(
              'Coming soon',
              style: theme.textTheme.labelSmall?.copyWith(
                color: scheme.onSurfaceVariant.withValues(alpha: 0.7),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
