import 'package:flutter/material.dart';

import 'court_repository.dart';

/// Presentational management dashboard for a single court. Metric cards are
/// empty states until the player loop feeds real data. A suspended court shows
/// a "subscribe to publish" banner.
class OwnerDashboard extends StatelessWidget {
  const OwnerDashboard({
    super.key,
    required this.court,
    required this.onSubscribe,
  });

  final Court court;
  final VoidCallback onSubscribe;

  String get _fee => '₱${(court.entryFeeCents / 100).toStringAsFixed(0)}';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text(court.name, style: theme.textTheme.headlineSmall),
        const SizedBox(height: 4),
        Text(
          'Entry fee $_fee · ${court.numCourts} '
          '${court.numCourts == 1 ? 'court' : 'courts'}',
          style: theme.textTheme.bodyMedium
              ?.copyWith(color: scheme.onSurfaceVariant),
        ),
        const SizedBox(height: 20),
        if (!court.isActive)
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: scheme.errorContainer.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Subscription inactive — your court is hidden from players.',
                  style: theme.textTheme.titleSmall,
                ),
                const SizedBox(height: 8),
                FilledButton(
                  onPressed: onSubscribe,
                  child: const Text('Subscribe'),
                ),
              ],
            ),
          ),
        if (!court.isActive) const SizedBox(height: 20),
        const _MetricCard(
          icon: Icons.payments_outlined,
          title: "Today's revenue",
          empty: 'No revenue yet',
        ),
        const SizedBox(height: 12),
        const _MetricCard(
          icon: Icons.groups_outlined,
          title: 'Players today',
          empty: 'No players yet',
        ),
        const SizedBox(height: 12),
        const _MetricCard(
          icon: Icons.timer_outlined,
          title: 'Active queue',
          empty: 'Queue is empty',
        ),
      ],
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.icon,
    required this.title,
    required this.empty,
  });

  final IconData icon;
  final String title;
  final String empty;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Icon(icon, color: scheme.primary),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: theme.textTheme.titleSmall),
              Text(empty,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: scheme.onSurfaceVariant)),
            ],
          ),
        ],
      ),
    );
  }
}
