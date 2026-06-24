import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

import '../../app/app_icons.dart';
import '../../app/theme.dart';
import '../../data/court.dart';
import 'discovery_repository.dart';

/// Body of the Play shell's first tab: a searchable list of active courts.
/// Body-only — the Play shell supplies the app bar and bottom nav.
class CourtListScreen extends ConsumerStatefulWidget {
  const CourtListScreen({super.key, this.onSelect});
  final void Function(Court court)? onSelect;

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
            decoration: InputDecoration(
              hintText: 'Search courts by name',
              prefixIcon: Icon(PhosphorIconsFill.magnifyingGlass),
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
                itemBuilder: (context, i) =>
                    _CourtCard(court: filtered[i], onSelect: widget.onSelect),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _CourtCard extends StatelessWidget {
  const _CourtCard({required this.court, this.onSelect});

  final Court court;
  final void Function(Court)? onSelect;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Material(
      color: scheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(kRadius),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onSelect != null
            ? () => onSelect!(court)
            : () => context.push('/play/court/${court.id}'),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Stack(
              children: [
                AspectRatio(
                  aspectRatio: 16 / 9,
                  child: _CourtImage(imageUrl: court.imageUrl),
                ),
                if (onSelect != null)
                  Positioned(
                    top: 8,
                    right: 8,
                    child: Material(
                      color: Colors.black.withValues(alpha: 0.45),
                      borderRadius: BorderRadius.circular(100),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(100),
                        onTap: () => context.push('/play/court/${court.id}'),
                        child: Padding(
                          padding: const EdgeInsets.all(6),
                          child: Icon(PhosphorIconsFill.info,
                              color: Colors.white, size: 18),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(court.name, style: theme.textTheme.titleMedium),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          court.address ?? 'Address not set',
                          style: theme.textTheme.bodySmall
                              ?.copyWith(color: scheme.onSurfaceVariant),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        formatFee(court.entryFeeCents, court.currency),
                        style: theme.textTheme.bodyMedium?.copyWith(
                            color: scheme.primary,
                            fontWeight: FontWeight.w600),
                      ),
                    ],
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

class _CourtImage extends StatelessWidget {
  const _CourtImage({required this.imageUrl});

  final String? imageUrl;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final placeholder = Container(
      color: scheme.surfaceContainerHighest,
      alignment: Alignment.center,
      child: AppIcon(
        AppIcons.pickleballPaddle,
        size: 48,
        color: scheme.onSurfaceVariant.withValues(alpha: 0.3),
      ),
    );
    if (imageUrl == null) return placeholder;
    return Image.network(
      imageUrl!,
      fit: BoxFit.cover,
      errorBuilder: (_, _, _) => placeholder,
      loadingBuilder: (_, child, progress) =>
          progress == null ? child : placeholder,
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
