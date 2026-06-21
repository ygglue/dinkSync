import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/app_mode.dart';
import '../../data/capabilities.dart';

/// Full-width Play/Management switch shown directly under the app bar. Renders
/// nothing unless the user is a manager. Persists the selection and calls
/// [onChanged] so the caller can navigate to the matching shell.
class ModeDropdown extends ConsumerWidget {
  const ModeDropdown({super.key, required this.onChanged});

  final void Function(AppMode) onChanged;

  static IconData _icon(AppMode m) =>
      m == AppMode.management ? Icons.storefront_outlined : Icons.sports_tennis;

  static String _label(AppMode m) =>
      m == AppMode.management ? 'Manage' : 'Play';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final caps = ref.watch(capabilitiesProvider).valueOrNull;
    if (caps == null || !caps.isManager) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final mode = ref.watch(appModeProvider);

    return Container(
      key: const Key('mode-dropdown'),
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: scheme.surface,
        border: Border(bottom: BorderSide(color: scheme.outlineVariant)),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<AppMode>(
          value: mode,
          isExpanded: true,
          borderRadius: BorderRadius.circular(16),
          dropdownColor: scheme.surfaceContainerLowest,
          icon: Icon(Icons.keyboard_arrow_down_rounded, color: scheme.primary),
          style: theme.textTheme.titleSmall?.copyWith(
            color: scheme.onSurface,
            fontWeight: FontWeight.w600,
          ),
          onChanged: (m) {
            if (m == null) return;
            ref.read(appModeProvider.notifier).set(m);
            onChanged(m);
          },
          items: AppMode.values.map((m) {
            return DropdownMenuItem(
              value: m,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(_icon(m), size: 18, color: scheme.primary),
                  const SizedBox(width: 10),
                  Text(_label(m)),
                ],
              ),
            );
          }).toList(),
        ),
      ),
    );
  }
}
