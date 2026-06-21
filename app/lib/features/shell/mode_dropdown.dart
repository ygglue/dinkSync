import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/app_mode.dart';
import '../../data/capabilities.dart';

/// Top-bar Play/Management switch, styled as a tonal pill. Renders nothing
/// unless the user is a manager. Persists the selection and calls [onChanged]
/// so the caller can navigate to the matching shell.
class ModeDropdown extends ConsumerWidget {
  const ModeDropdown({super.key, required this.onChanged});

  final void Function(AppMode) onChanged;

  static IconData _icon(AppMode m) =>
      m == AppMode.management ? Icons.storefront_outlined : Icons.sports_tennis;

  /// Compact label shown in the closed pill.
  static String _shortLabel(AppMode m) =>
      m == AppMode.management ? 'Manage' : 'Play';

  /// Full label shown in the open menu.
  static String _menuLabel(AppMode m) =>
      m == AppMode.management ? 'Court Management' : 'Play';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final caps = ref.watch(capabilitiesProvider).valueOrNull;
    if (caps == null || !caps.isManager) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final mode = ref.watch(appModeProvider);

    return Container(
      key: const Key('mode-dropdown'),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(999),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<AppMode>(
          value: mode,
          isDense: true,
          borderRadius: BorderRadius.circular(16),
          dropdownColor: scheme.surfaceContainerLowest,
          icon: Icon(Icons.keyboard_arrow_down_rounded,
              size: 20, color: scheme.primary),
          style: theme.textTheme.labelLarge?.copyWith(
            color: scheme.onSurface,
            fontWeight: FontWeight.w600,
          ),
          onChanged: (m) {
            if (m == null) return;
            ref.read(appModeProvider.notifier).set(m);
            onChanged(m);
          },
          // Closed state: compact icon + short label, brand-tinted.
          selectedItemBuilder: (context) => AppMode.values.map((m) {
            return Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(_icon(m), size: 18, color: scheme.primary),
                const SizedBox(width: 6),
                Text(_shortLabel(m)),
              ],
            );
          }).toList(),
          // Open menu: full labels with a leading icon.
          items: AppMode.values.map((m) {
            return DropdownMenuItem(
              value: m,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(_icon(m), size: 18, color: scheme.onSurfaceVariant),
                  const SizedBox(width: 8),
                  Text(_menuLabel(m)),
                ],
              ),
            );
          }).toList(),
        ),
      ),
    );
  }
}
