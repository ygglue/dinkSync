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
    final nameAsync = ref.watch(currentUserDisplayNameProvider);
    final displayName = nameAsync.valueOrNull ?? 'Player';
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
                          ? kBrandGreen
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
          // Player slots — fixed height so the cards stay compact instead of
          // stretching to fill the leftover vertical space.
          SizedBox(
            height: 168,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: _PlayerSlot(displayName: displayName)),
                const SizedBox(width: 12),
                const Expanded(child: _PartnerSlot()),
              ],
            ),
          ),
          const Spacer(),
          // Action row — equal widths so "Book a Court" has room for its label.
          Row(
            children: [
              Expanded(
                child: FilledButton(
                  onPressed: null,
                  child: const Text('Find Match'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton(
                  onPressed: canBook
                      ? () => context.push('/play/custom',
                          extra: _selectedCourt)
                      : null,
                  child: const Text('Book a Court'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PlayerSlot extends StatelessWidget {
  const _PlayerSlot({required this.displayName});
  final String displayName;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final initial = displayName.isNotEmpty ? displayName[0].toUpperCase() : '?';
    return Container(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(kRadius),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircleAvatar(
            radius: 28,
            backgroundColor: scheme.primary.withValues(alpha: 0.1),
            child: Text(
              initial,
              style: theme.textTheme.headlineSmall?.copyWith(
                color: kBrandGreen,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            displayName,
            style: theme.textTheme.bodyMedium
                ?.copyWith(fontWeight: FontWeight.w600),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 4),
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
      // Empty placeholder look: no fill (vs the filled "You" slot) + an outline,
      // so it clearly reads as an open seat rather than an occupied one.
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
              size: 48, color: scheme.onSurfaceVariant.withValues(alpha: 0.5)),
          const SizedBox(height: 10),
          Text(
            'Invite partner',
            style: theme.textTheme.bodyMedium
                ?.copyWith(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 4),
          Text(
            'Coming soon',
            style: theme.textTheme.labelSmall
                ?.copyWith(color: scheme.onSurfaceVariant.withValues(alpha: 0.6)),
          ),
        ],
      ),
    );
  }
}
