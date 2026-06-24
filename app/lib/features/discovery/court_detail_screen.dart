import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

import '../../app/app_icons.dart';
import '../../data/court.dart';
import 'discovery_repository.dart';

/// Full-screen court detail: venue info + live availability + a placeholder
/// join CTA. Pushed on the root navigator, so it owns its Scaffold/AppBar.
class CourtDetailScreen extends ConsumerWidget {
  const CourtDetailScreen({super.key, required this.courtId});

  final String courtId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final courtAsync = ref.watch(courtByIdProvider(courtId));
    return Scaffold(
      appBar: AppBar(
        title: Text(courtAsync.valueOrNull?.name ?? 'Court'),
      ),
      body: courtAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) =>
            const Center(child: Text('Could not load this court.')),
        data: (court) {
          if (court == null) {
            return const Center(child: Text('Could not load this court.'));
          }
          return _Body(courtId: courtId, court: court);
        },
      ),
    );
  }
}

class _Body extends ConsumerWidget {
  const _Body({required this.courtId, required this.court});

  final String courtId;
  final Court court;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final availAsync = ref.watch(courtAvailabilityProvider(courtId));
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text(court.name, style: theme.textTheme.headlineSmall),
        const SizedBox(height: 8),
        _InfoRow(
          icon: const Icon(PhosphorIconsFill.mapPin),
          text: court.address ?? 'Address not set',
        ),
        const SizedBox(height: 8),
        _InfoRow(
          icon: const Icon(PhosphorIconsFill.currencyDollar),
          text: 'Entry fee ${formatFee(court.entryFeeCents, court.currency)}',
        ),
        const SizedBox(height: 8),
        _InfoRow(
          icon: const Icon(PhosphorIconsFill.gridFour),
          text: '${court.numCourts} '
              '${court.numCourts == 1 ? 'court' : 'courts'}',
        ),
        const SizedBox(height: 8),
        availAsync.when(
          loading: () => _InfoRow(
            icon: AppIcon(AppIcons.pickleballPaddle),
            text: 'Checking availability…',
          ),
          error: (_, _) => _InfoRow(
            icon: AppIcon(AppIcons.pickleballPaddle),
            text: 'Availability unavailable',
          ),
          data: (a) => _InfoRow(
            icon: AppIcon(AppIcons.pickleballPaddle),
            text: a.totalCount == 0
                ? 'No courts in service'
                : '${a.openCount} of ${a.totalCount} courts open',
          ),
        ),
        const SizedBox(height: 28),
        FilledButton(
          onPressed: null, // queueing not built yet
          child: const Text('Join queue — coming soon'),
        ),
      ],
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.icon, required this.text});

  final Widget icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Row(
      children: [
        IconTheme(
          data: IconThemeData(size: 20, color: scheme.primary),
          child: icon,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            text,
            style: theme.textTheme.bodyMedium
                ?.copyWith(color: scheme.onSurfaceVariant),
          ),
        ),
      ],
    );
  }
}
