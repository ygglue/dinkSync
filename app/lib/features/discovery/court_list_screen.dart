import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme.dart';
import '../../data/court.dart';
import 'discovery_repository.dart';

/// Body of the Play shell's first tab: a searchable list of active courts.
/// Body-only — the Play shell supplies the app bar and bottom nav.
class CourtListScreen extends ConsumerStatefulWidget {
  const CourtListScreen({super.key});

  @override
  ConsumerState<CourtListScreen> createState() => _CourtListScreenState();
}

class _CourtListScreenState extends ConsumerState<CourtListScreen> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final courtsAsync = ref.watch(activeCourtsProvider);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: TextField(
            onChanged: (v) => setState(() => _query = v),
            decoration: const InputDecoration(
              hintText: 'Search courts by name',
              prefixIcon: Icon(Icons.search),
            ),
          ),
        ),
        Expanded(
          child: courtsAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (_, _) => _ErrorRetry(
              onRetry: () => ref.invalidate(activeCourtsProvider),
            ),
            data: (courts) {
              if (courts.isEmpty) {
                return const _Empty(message: 'No courts available yet.');
              }
              final q = _query.trim().toLowerCase();
              final filtered = q.isEmpty
                  ? courts
                  : courts
                      .where((c) => c.name.toLowerCase().contains(q))
                      .toList();
              if (filtered.isEmpty) {
                return _Empty(message: 'No courts match "${_query.trim()}".');
              }
              return ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                itemCount: filtered.length,
                separatorBuilder: (_, _) => const SizedBox(height: 12),
                itemBuilder: (context, i) => _CourtCard(court: filtered[i]),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _CourtCard extends StatelessWidget {
  const _CourtCard({required this.court});

  final Court court;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Material(
      color: scheme.surfaceContainerHighest.withValues(alpha: 0.6),
      borderRadius: BorderRadius.circular(kRadius),
      child: InkWell(
        borderRadius: BorderRadius.circular(kRadius),
        onTap: () => context.push('/play/court/${court.id}'),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(court.name, style: theme.textTheme.titleMedium),
                    const SizedBox(height: 4),
                    Text(
                      court.address ?? 'Address not set',
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      formatFee(court.entryFeeCents, court.currency),
                      style: theme.textTheme.bodyMedium?.copyWith(
                          color: scheme.primary, fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: scheme.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Text(
          message,
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium
              ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
      ),
    );
  }
}

class _ErrorRetry extends StatelessWidget {
  const _ErrorRetry({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('Could not load courts.'),
          const SizedBox(height: 12),
          OutlinedButton(onPressed: onRetry, child: const Text('Retry')),
        ],
      ),
    );
  }
}
