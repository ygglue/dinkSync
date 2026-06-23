import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme.dart';
import '../../data/app_mode.dart';
import '../../data/court.dart';
import '../discovery/discovery_repository.dart';
import 'booking_repository.dart';

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
    _selectedCourtId = widget.initialCourt?.id;
    if (_selectedCourtId == null) {
      Future.microtask(_restoreLastCourt);
    }
  }

  void _restoreLastCourt() {
    if (!mounted) return;
    final savedId =
        ref.read(sharedPreferencesProvider).getString(_kLastCourtKey);
    if (savedId != null && mounted) {
      setState(() => _selectedCourtId = savedId);
    }
  }

  Future<void> _pickCourt() async {
    final court = await context.push<Court>('/play/courts');
    if (court != null && mounted) {
      ref.read(sharedPreferencesProvider).setString(_kLastCourtKey, court.id);
      setState(() => _selectedCourtId = court.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final profileAsync = ref.watch(currentUserProfileProvider);
    final profile = profileAsync.valueOrNull ??
        const LobbyProfile(displayName: 'Player', mmr: 1000);

    // Always watch live data so edits in Manage mode are reflected instantly.
    final selectedCourt = _selectedCourtId != null
        ? ref.watch(courtByIdProvider(_selectedCourtId!)).valueOrNull
        : null;

    final canBook =
        selectedCourt != null && selectedCourt.customFeeCents != null;

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
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                child: Row(
                  children: [
                    Icon(
                      Icons.stadium_outlined,
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
                    Icon(Icons.chevron_right,
                        size: 20, color: scheme.onSurfaceVariant),
                  ],
                ),
              ),
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
          // Find Match — primary CTA.
          FilledButton(
            onPressed: null,
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(68),
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
                ? () => context.push('/play/custom', extra: selectedCourt)
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

    return ClipRRect(
      borderRadius: BorderRadius.circular(kRadius),
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Background: network photo when available, tonal gradient otherwise.
          if (profile.avatarUrl != null)
            Image.network(profile.avatarUrl!, fit: BoxFit.cover)
          else
            Container(
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest,
              ),
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
          // Dark gradient — covers bottom ~45% for text legibility.
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
                  // MMR badge — dark pill with white text.
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.45),
                      borderRadius: BorderRadius.circular(100),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.bar_chart_rounded,
                            size: 14, color: Colors.white),
                        const SizedBox(width: 4),
                        Text(
                          '${profile.mmr} MMR',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: Colors.white,
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
              Icons.person_add_outlined,
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
                border: Border.all(color: scheme.outlineVariant),
                borderRadius: BorderRadius.circular(100),
              ),
              child: Text(
                'COMING SOON',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: scheme.onSurfaceVariant.withValues(alpha: 0.7),
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
