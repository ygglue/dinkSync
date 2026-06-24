import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

import '../../app/theme.dart';
import '../../data/supabase_client.dart';
import 'player_profile_repository.dart';
import 'rank.dart';

const _months = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

String _memberSince(DateTime d) =>
    'Member since ${_months[d.month - 1]} ${d.year}';

class PlayerProfileScreen extends ConsumerWidget {
  const PlayerProfileScreen({super.key, required this.profileId});

  final String profileId;

  static const _darkGreen = Color(0xFF2E7D32);
  static const _midGreen = Color(0xFF43A047);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final profileAsync = ref.watch(playerProfileProvider(profileId));
    final isMe = supabase.auth.currentUser?.id == profileId;

    return Scaffold(
      appBar: AppBar(),
      body: profileAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Text("Couldn't load player",
              style: TextStyle(color: scheme.error)),
        ),
        data: (p) {
          if (p == null) {
            return const Center(child: Text('Player not found.'));
          }
          return RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(playerProfileProvider(profileId));
              ref.invalidate(playerStatsProvider(profileId));
              ref.invalidate(playerRecentMatchesProvider(profileId));
            },
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
              children: [
                _ProfileCard(
                  profile: p,
                  darkGreen: _darkGreen,
                  midGreen: _midGreen,
                ),
                const SizedBox(height: 24),
                _StatsRow(profileId: profileId),
                const SizedBox(height: 24),
                _RecentMatches(profileId: profileId),
                if (isMe) ...[
                  const SizedBox(height: 24),
                  OutlinedButton.icon(
                    onPressed: () => context.go('/profile'),
                    icon: const Icon(PhosphorIconsFill.pencilSimple),
                    label: const Text('Edit profile'),
                  ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}

// ── Profile card (green gradient header) ──────────────────────────────────────

class _ProfileCard extends StatelessWidget {
  const _ProfileCard({
    required this.profile,
    required this.darkGreen,
    required this.midGreen,
  });

  final PublicProfile profile;
  final Color darkGreen;
  final Color midGreen;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final initial = profile.displayName.isNotEmpty
        ? profile.displayName[0].toUpperCase()
        : '?';

    return Card(
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(kRadius),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Green gradient header
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [darkGreen, midGreen],
              ),
            ),
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
            child: Column(
              children: [
                // Avatar
                Container(
                  width: 100,
                  height: 100,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white.withValues(alpha: 0.15),
                    border: Border.all(color: Colors.white, width: 3),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: profile.avatarUrl != null
                      ? Image.network(
                          profile.avatarUrl!,
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) => Center(
                            child: Text(
                              initial,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 36,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        )
                      : Center(
                          child: Text(
                            initial,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 36,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                ),
                const SizedBox(height: 16),
                // Name
                Text(
                  profile.displayName,
                  style: theme.textTheme.titleLarge?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 6),
                // Rank badge + MMR
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 3),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        rankForMmr(profile.mmr).label,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '${profile.mmr} MMR',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.85),
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          // Member since
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 14),
            child: Text(
              _memberSince(profile.createdAt),
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Stats row ─────────────────────────────────────────────────────────────────

class _StatsRow extends ConsumerWidget {
  const _StatsRow({required this.profileId});

  final String profileId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final statsAsync = ref.watch(playerStatsProvider(profileId));

    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(kRadius),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
        child: statsAsync.when(
          loading: () => const Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _StatCell(icon: PhosphorIconsFill.trophy, label: 'WINS', value: '—'),
              _StatCell(icon: PhosphorIconsFill.x, label: 'LOSSES', value: '—'),
              _StatCell(icon: PhosphorIconsFill.percent, label: 'WIN RATE', value: '—'),
            ],
          ),
          error: (_, _) => const Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _StatCell(icon: PhosphorIconsFill.trophy, label: 'WINS', value: '—'),
              _StatCell(icon: PhosphorIconsFill.x, label: 'LOSSES', value: '—'),
              _StatCell(icon: PhosphorIconsFill.percent, label: 'WIN RATE', value: '—'),
            ],
          ),
          data: (s) {
            final winRateStr = s.winRate == null
                ? '—'
                : '${(s.winRate! * 100).round()}%';
            return Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _StatCell(
                  icon: PhosphorIconsFill.trophy,
                  label: 'WINS',
                  value: '${s.wins}',
                ),
                _StatCell(
                  icon: PhosphorIconsFill.x,
                  label: 'LOSSES',
                  value: '${s.losses}',
                ),
                _StatCell(
                  icon: PhosphorIconsFill.percent,
                  label: 'WIN RATE',
                  value: winRateStr,
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _StatCell extends StatelessWidget {
  const _StatCell({
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
          style:
              theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
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

// ── Recent matches ─────────────────────────────────────────────────────────────

class _RecentMatches extends ConsumerWidget {
  const _RecentMatches({required this.profileId});

  final String profileId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final matchesAsync = ref.watch(playerRecentMatchesProvider(profileId));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Recent matches',
          style: theme.textTheme.titleMedium
              ?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 12),
        matchesAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, _) => Text(
            'Could not load matches.',
            style: TextStyle(color: scheme.error),
          ),
          data: (matches) {
            if (matches.isEmpty) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: Text(
                    'No matches yet',
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                ),
              );
            }
            return Column(
              children: matches.map((m) {
                final isWin = m.result == 'win';
                final resultColor =
                    isWin ? scheme.primary : scheme.error;
                final dateStr =
                    '${_months[m.playedAt.month - 1]} ${m.playedAt.day}, ${m.playedAt.year}';
                return Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(kRadius / 2),
                  ),
                  child: ListTile(
                    leading: Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: resultColor.withValues(alpha: 0.12),
                        shape: BoxShape.circle,
                      ),
                      child: Center(
                        child: Text(
                          isWin ? 'W' : 'L',
                          style: TextStyle(
                            color: resultColor,
                            fontWeight: FontWeight.w700,
                            fontSize: 14,
                          ),
                        ),
                      ),
                    ),
                    title: Text(
                      isWin ? 'Win' : 'Loss',
                      style: theme.textTheme.bodyMedium
                          ?.copyWith(fontWeight: FontWeight.w600),
                    ),
                    subtitle: Text(
                      dateStr,
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                  ),
                );
              }).toList(),
            );
          },
        ),
      ],
    );
  }
}
