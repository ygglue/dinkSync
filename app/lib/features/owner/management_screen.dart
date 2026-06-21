import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/app_mode.dart';
import '../../data/capabilities.dart';
import '../shell/mode_dropdown.dart';
import 'court_onboarding_screen.dart';
import 'court_repository.dart';
import 'owner_dashboard_screen.dart';

/// Court Management mode entry. Shows onboarding if the user owns no court,
/// otherwise the dashboard. Reachable by any signed-in user (first-time hosts).
class ManagementScreen extends ConsumerWidget {
  const ManagementScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final courtAsync = ref.watch(ownerCourtProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Court Management'),
        actions: [
          ModeDropdown(
            onChanged: (m) {
              if (m == AppMode.play) context.go('/play');
            },
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: courtAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => _ErrorRetry(
          onRetry: () => ref.invalidate(ownerCourtProvider),
        ),
        data: (court) {
          if (court == null) {
            return CourtOnboardingScreen(
              onCreated: (_) {
                ref.invalidate(ownerCourtProvider);
                ref.invalidate(capabilitiesProvider);
                context.go('/manage/subscribe');
              },
            );
          }
          if (!court.isActive) {
            // Allow jumping straight to subscribe from a suspended court.
            return OwnerDashboard(
              court: court,
              onEdit: () => context.go('/manage/edit'),
              onSubscribe: () => context.go('/manage/subscribe'),
            );
          }
          return OwnerDashboard(
            court: court,
            onEdit: () => context.go('/manage/edit'),
            onSubscribe: () {},
          );
        },
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
