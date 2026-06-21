import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/app_mode.dart';
import '../../data/capabilities.dart';

/// In-app-bar Play/Management switch: a court-green icon + label + chevron with
/// no background, sitting on the right of the top bar next to the wordmark.
/// Renders nothing unless the user is a manager. Persists the selection and
/// calls [onChanged] so the caller can navigate to the matching shell.
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
              Text(_label(m)),
              if (selected) ...[
                const SizedBox(width: 12),
                Icon(Icons.check_rounded, size: 18, color: scheme.primary),
              ],
            ],
          ),
        );
      }).toList(),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(_icon(mode), size: 22, color: scheme.primary),
            const SizedBox(width: 6),
            Text(
              _label(mode),
              style: theme.textTheme.titleLarge?.copyWith(
                fontSize: 17,
                fontWeight: FontWeight.w600,
                color: scheme.primary,
              ),
            ),
            Icon(Icons.keyboard_arrow_down_rounded,
                size: 22, color: scheme.primary),
          ],
        ),
      ),
    );
  }
}
