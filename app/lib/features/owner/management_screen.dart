import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

import 'court_repository.dart';
import 'owner_dashboard_screen.dart';

/// Body of the Manage shell's "Dashboard" tab: the owner's court dashboard, or
/// a prompt to set one up. The surrounding app bar + bottom nav live in
/// `ManageShell`; this widget returns body content only (no Scaffold).
class ManagementHome extends ConsumerWidget {
  const ManagementHome({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final courtAsync = ref.watch(ownerCourtProvider);
    return courtAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (_, _) => _ErrorRetry(
        onRetry: () => ref.invalidate(ownerCourtProvider),
      ),
      data: (court) {
        if (court == null) {
          return _NoCourt(onCreate: () => context.push('/onboard'));
        }
        return OwnerDashboard(
          court: court,
          onEdit: () => context.push('/manage/edit'),
          onSubscribe: () => context.push('/manage/subscribe'),
        );
      },
    );
  }
}

class _NoCourt extends StatelessWidget {
  const _NoCourt({required this.onCreate});

  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(PhosphorIconsFill.storefront,
                size: 48, color: theme.colorScheme.primary),
            const SizedBox(height: 12),
            Text('No court yet', style: theme.textTheme.titleLarge),
            const SizedBox(height: 4),
            Text(
              'Set up your court to start managing it.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: onCreate,
              child: const Text('Set up your court'),
            ),
          ],
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
          const Text('Could not load your court.'),
          const SizedBox(height: 12),
          OutlinedButton(onPressed: onRetry, child: const Text('Retry')),
        ],
      ),
    );
  }
}
