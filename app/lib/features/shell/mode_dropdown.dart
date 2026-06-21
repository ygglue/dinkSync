import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/app_mode.dart';
import '../../data/capabilities.dart';

/// Top-bar Play/Management switch, styled as a compact tonal pill. Renders
/// nothing unless the user is a manager. Persists the selection and calls
/// [onChanged] so the caller can navigate to the matching shell.
///
/// Uses a [PopupMenuButton] rather than a [DropdownButton] so the closed pill
/// stays compact (a DropdownButton sizes itself to its widest item, which
/// overflows a narrow app bar).
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

    return PopupMenuButton<AppMode>(
      key: const Key('mode-dropdown'),
      initialValue: mode,
      tooltip: 'Switch mode',
      position: PopupMenuPosition.under,
      color: scheme.surfaceContainerLowest,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      onSelected: (m) {
        ref.read(appModeProvider.notifier).set(m);
        onChanged(m);
      },
      itemBuilder: (context) => AppMode.values.map((m) {
        final selected = m == mode;
        return PopupMenuItem<AppMode>(
          value: m,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(_icon(m),
                  size: 18,
                  color: selected ? scheme.primary : scheme.onSurfaceVariant),
              const SizedBox(width: 10),
              Text(_menuLabel(m)),
              if (selected) ...[
                const SizedBox(width: 12),
                Icon(Icons.check_rounded, size: 18, color: scheme.primary),
              ],
            ],
          ),
        );
      }).toList(),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(_icon(mode), size: 18, color: scheme.primary),
            const SizedBox(width: 6),
            Text(
              _shortLabel(mode),
              style: theme.textTheme.labelLarge?.copyWith(
                color: scheme.onSurface,
                fontWeight: FontWeight.w600,
              ),
            ),
            Icon(Icons.keyboard_arrow_down_rounded,
                size: 20, color: scheme.primary),
          ],
        ),
      ),
    );
  }
}
