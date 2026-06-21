import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/router.dart';
import '../../data/app_mode.dart';
import '../../data/capabilities.dart';

/// Transient '/' screen: once capabilities resolve, routes to the right shell
/// based on the persisted mode. Shows a spinner while loading.
class LaunchScreen extends ConsumerWidget {
  const LaunchScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final caps = ref.watch(capabilitiesProvider);
    final mode = ref.watch(appModeProvider);

    return caps.when(
      loading: () =>
          const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (_, _) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (context.mounted) context.go('/play');
        });
        return const Scaffold(body: Center(child: CircularProgressIndicator()));
      },
      data: (c) {
        final target = launchTarget(isManager: c.isManager, mode: mode);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (context.mounted) context.go(target);
        });
        return const Scaffold(body: Center(child: CircularProgressIndicator()));
      },
    );
  }
}
