import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

import '../../app/app_icons.dart';
import '../../app/theme.dart';
import '../../data/app_mode.dart';
import '../../data/court.dart';
import '../discovery/discovery_repository.dart';
import 'book_slot_sheet.dart';
import 'booking_repository.dart';
import 'matchmaking_repository.dart';

const _kLastCourtKey = 'lobby_last_court_id';

/// Body of the Play shell's first tab: the game lobby.
/// Body-only — PlayShell supplies the AppBar and floating nav.
class LobbyScreen extends ConsumerStatefulWidget {
  const LobbyScreen({super.key, this.initialCourt});
  final Court? initialCourt;

  @override
  ConsumerState<LobbyScreen> createState() => _LobbyScreenState();
}

class _LobbyScreenState extends ConsumerState<LobbyScreen> {
  String? _selectedCourtId;

  @override
  void initState() {
    super.initState();
    _selectedCourtId = widget.initialCourt?.id
        ?? ref.read(sharedPreferencesProvider).getString(_kLastCourtKey);
  }

  Future<void> _pickCourt() async {
    final court = await context.push<Court>('/play/courts');
    if (court != null && mounted) {
      ref.read(sharedPreferencesProvider).setString(_kLastCourtKey, court.id);
      setState(() => _selectedCourtId = court.id);
    }
  }

  void _showMatchFoundSheet(BuildContext context, MatchmakingMatched state) {
    showModalBottomSheet<void>(
      context: context,
      isDismissible: false,
      enableDrag: false,
      backgroundColor: Colors.transparent,
      builder: (_) => _MatchFoundSheet(
        state: state,
        onDismiss: () {
          ref.read(matchmakingProvider.notifier).acknowledgeMatch();
          Navigator.of(context).pop();
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final profileAsync = ref.watch(currentUserProfileProvider);
    final profile = profileAsync.valueOrNull ??
        const LobbyProfile(displayName: 'Player', mmr: 1000);
    final matchState = ref.watch(matchmakingProvider);

    // Trigger match-found sheet as a side effect
    ref.listen<MatchmakingState>(matchmakingProvider, (prev, next) {
      if (next is MatchmakingMatched && mounted) {
        _showMatchFoundSheet(context, next);
      }
    });

    // Always watch live data so edits in Manage mode are reflected instantly.
    final selectedCourt = _selectedCourtId != null
        ? ref.watch(courtByIdProvider(_selectedCourtId!)).valueOrNull
        : null;

    final canBook =
        selectedCourt != null && selectedCourt.customFeeCents != null;
    final canMatch = selectedCourt != null && matchState is MatchmakingIdle;
    final isSearching = matchState is MatchmakingSearching;

    // Live queue depth while searching
    final queueDepth = isSearching
        ? ref.watch(queueDepthProvider(matchState.courtId)).valueOrNull
        : null;

    final bottomInset = MediaQuery.of(context).padding.bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 16, 16, bottomInset + 92),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Court selector
          Material(
            color: scheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(kRadius),
            clipBehavior: Clip.antiAlias,
            child: Stack(
              children: [
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: RadialGradient(
                        center: Alignment.topLeft,
                        radius: 3.0,
                        colors: [
                          scheme.primary.withValues(alpha: 0.18),
                          Colors.transparent,
                        ],
                      ),
                    ),
                  ),
                ),
                InkWell(
                  onTap: isSearching ? null : _pickCourt,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 14),
                    child: Row(
                      children: [
                        Icon(
                          PhosphorIconsFill.buildings,
                          color: selectedCourt != null
                              ? scheme.primary
                              : scheme.onSurfaceVariant,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            selectedCourt?.name ?? 'Select a court',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: selectedCourt != null
                                  ? scheme.onSurface
                                  : scheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                        Icon(PhosphorIconsFill.caretRight,
                            size: 20, color: scheme.onSurfaceVariant),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          // Player slots — fill remaining vertical space.
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
          const SizedBox(height: 16),
          // Find Match — primary CTA (switches to searching state).
          if (isSearching)
            _SearchingCard(
              queueDepth: queueDepth,
              onCancel: () =>
                  ref.read(matchmakingProvider.notifier).cancelQueue(),
            )
          else
            SizedBox(
              height: 80,
              child: FilledButton(
                onPressed: canMatch
                    ? () => ref
                        .read(matchmakingProvider.notifier)
                        .joinQueue(
                          courtId: selectedCourt.id,
                          mmr: profile.mmr,
                        )
                    : null,
                style: FilledButton.styleFrom(
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  textStyle: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.3,
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    AppIcon(AppIcons.pickleballPaddle, size: 20),
                    const SizedBox(width: 10),
                    const Text('Find Match'),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 10),
          // Book a Slot — secondary CTA.
          SizedBox(
            height: 60,
            child: OutlinedButton(
              onPressed: (!isSearching && canBook)
                  ? () async {
                      final messenger = ScaffoldMessenger.of(context);
                      final label =
                          await BookSlotSheet.show(context, selectedCourt);
                      if (label != null && mounted) {
                        messenger.showSnackBar(
                          SnackBar(
                              content: Text('Booked! See you on $label.')),
                        );
                      }
                    }
                  : null,
              style: OutlinedButton.styleFrom(
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: const Text('Book a Slot'),
            ),
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

    return ClipRRect(
      borderRadius: BorderRadius.circular(kRadius),
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Background: network photo when available, tonal surface otherwise.
          if (profile.avatarUrl != null)
            Image.network(profile.avatarUrl!, fit: BoxFit.cover)
          else
            Container(
              color: scheme.surfaceContainerHighest,
              child: Center(
                child: Text(
                  initial,
                  style: TextStyle(
                    fontSize: 96,
                    fontWeight: FontWeight.w900,
                    color: scheme.primary.withValues(alpha: 0.18),
                    height: 1,
                  ),
                ),
              ),
            ),
          // Dark gradient for text legibility.
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  stops: const [0.45, 1.0],
                  colors: [
                    Colors.transparent,
                    Colors.black.withValues(alpha: 0.68),
                  ],
                ),
              ),
            ),
          ),
          // Name / MMR / You — anchored to the bottom.
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    profile.displayName,
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFF232821),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: scheme.primary, width: 1),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(PhosphorIconsFill.chartBar,
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
                  const SizedBox(height: 6),
                  Text(
                    'You',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: Colors.white.withValues(alpha: 0.75),
                    ),
                  ),
                ],
              ),
            ),
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
    return CustomPaint(
      painter: _DashedRoundedBorder(
        color: scheme.outlineVariant,
        radius: kRadius,
        strokeWidth: 1.5,
        dashLength: 8,
        gapLength: 6,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(kRadius),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              PhosphorIconsFill.userPlus,
              size: 48,
              color: scheme.onSurfaceVariant.withValues(alpha: 0.45),
            ),
            const SizedBox(height: 12),
            Text(
              'Invite partner',
              style: theme.textTheme.titleSmall
                  ?.copyWith(color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFF232821),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: scheme.primary, width: 1),
              ),
              child: Text(
                'COMING SOON',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: scheme.primary,
                  letterSpacing: 0.5,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DashedRoundedBorder extends CustomPainter {
  const _DashedRoundedBorder({
    required this.color,
    required this.radius,
    required this.strokeWidth,
    required this.dashLength,
    required this.gapLength,
  });

  final Color color;
  final double radius;
  final double strokeWidth;
  final double dashLength;
  final double gapLength;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke;

    final rrect = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Radius.circular(radius),
    );
    final path = Path()..addRRect(rrect);

    for (final metric in path.computeMetrics()) {
      double distance = 0;
      bool drawing = true;
      while (distance < metric.length) {
        final segLen = drawing ? dashLength : gapLength;
        if (drawing) {
          canvas.drawPath(
            metric.extractPath(distance, distance + segLen),
            paint,
          );
        }
        distance += segLen;
        drawing = !drawing;
      }
    }
  }

  @override
  bool shouldRepaint(_DashedRoundedBorder old) =>
      color != old.color ||
      radius != old.radius ||
      strokeWidth != old.strokeWidth ||
      dashLength != old.dashLength ||
      gapLength != old.gapLength;
}

// ── Searching state card ───────────────────────────────────────────────────────

class _SearchingCard extends StatelessWidget {
  const _SearchingCard({this.queueDepth, required this.onCancel});

  final int? queueDepth;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Container(
      height: 80,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(kRadius),
      ),
      child: Stack(
        children: [
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: Alignment.topLeft,
                  radius: 2.0,
                  colors: [
                    scheme.primary.withValues(alpha: 0.20),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    color: scheme.primary,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Searching for match…',
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: scheme.onSurface,
                        ),
                      ),
                      if (queueDepth != null)
                        Text(
                          '$queueDepth in queue',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                    ],
                  ),
                ),
                GestureDetector(
                  onTap: onCancel,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 6),
                    decoration: BoxDecoration(
                      color: scheme.error.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      'Cancel',
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: scheme.error,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
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

// ── Match-found bottom sheet ───────────────────────────────────────────────────

class _MatchFoundSheet extends StatelessWidget {
  const _MatchFoundSheet({required this.state, required this.onDismiss});

  final MatchmakingMatched state;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final bottomInset = MediaQuery.of(context).padding.bottom;

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(kRadius),
      ),
      child: Stack(
        children: [
          // Radial glow — stronger for this celebratory moment
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: Alignment.topLeft,
                  radius: 1.6,
                  colors: [
                    scheme.primary.withValues(alpha: 0.28),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(24, 28, 24, 24 + bottomInset),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Icon(PhosphorIconsFill.trophy,
                        size: 28, color: scheme.primary),
                    const SizedBox(width: 12),
                    Text(
                      'Match Found!',
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: scheme.onSurface,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                if (state.slotLabel != null) ...[
                  Text(
                    "You're on",
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 10),
                    decoration: BoxDecoration(
                      color: const Color(0xFF232821),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: scheme.primary, width: 1),
                    ),
                    child: Text(
                      state.slotLabel!,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.titleLarge?.copyWith(
                        color: scheme.primary,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.3,
                      ),
                    ),
                  ),
                ] else
                  Text(
                    'Your group is formed — heading to queue.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                const SizedBox(height: 8),
                Text(
                  '${state.memberIds.length} players ready',
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: onDismiss,
                  child: const Text("Let's Play!"),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
