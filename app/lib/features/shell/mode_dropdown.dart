import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/app_mode.dart';
import '../../data/capabilities.dart';

/// Top-bar Play/Management switch. Renders nothing unless the user is a
/// manager. Persists the selection and calls [onChanged] so the caller can
/// navigate to the matching shell.
class ModeDropdown extends ConsumerWidget {
  const ModeDropdown({super.key, required this.onChanged});

  final void Function(AppMode) onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final caps = ref.watch(capabilitiesProvider).valueOrNull;
    if (caps == null || !caps.isManager) return const SizedBox.shrink();

    final mode = ref.watch(appModeProvider);
    return DropdownButtonHideUnderline(
      key: const Key('mode-dropdown'),
      child: DropdownButton<AppMode>(
        value: mode,
        onChanged: (m) {
          if (m == null) return;
          ref.read(appModeProvider.notifier).set(m);
          onChanged(m);
        },
        items: const [
          DropdownMenuItem(value: AppMode.play, child: Text('Play')),
          DropdownMenuItem(
              value: AppMode.management, child: Text('Court Management')),
        ],
      ),
    );
  }
}
