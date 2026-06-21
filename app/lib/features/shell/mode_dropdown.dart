import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../data/app_mode.dart';
import '../../data/capabilities.dart';

/// In-app-bar Play/Management switch. Shows a court-green icon + label + chevron
/// on the right of the top bar; tapping opens an Instagram-style "switch
/// account" bottom sheet listing the modes. Renders nothing unless the user is
/// a manager. Persists the selection and calls [onChanged] so the caller can
/// navigate to the matching shell.
class ModeDropdown extends ConsumerWidget {
  const ModeDropdown({super.key, required this.onChanged});

  final void Function(AppMode) onChanged;

  static IconData _icon(AppMode m) =>
      m == AppMode.management ? Icons.storefront_outlined : Icons.sports_tennis;

  /// Compact label for the top-bar trigger.
  static String _shortLabel(AppMode m) =>
      m == AppMode.management ? 'Manage' : 'Play';

  /// Full label + subtitle shown in the sheet.
  static String _title(AppMode m) =>
      m == AppMode.management ? 'Court Management' : 'Play';
  static String _subtitle(AppMode m) => m == AppMode.management
      ? 'Manage your court, staff & revenue'
      : 'Find games and matches';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final caps = ref.watch(capabilitiesProvider).valueOrNull;
    if (caps == null || !caps.isManager) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final mode = ref.watch(appModeProvider);

    return InkWell(
      key: const Key('mode-dropdown'),
      borderRadius: BorderRadius.circular(999),
      onTap: () => _openSheet(context, ref, mode),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(_icon(mode), size: 22, color: scheme.primary),
            const SizedBox(width: 6),
            Text(
              _shortLabel(mode),
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

  Future<void> _openSheet(
      BuildContext context, WidgetRef ref, AppMode current) async {
    final picked = await showModalBottomSheet<AppMode>(
      context: context,
      showDragHandle: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => _ModeSheet(current: current),
    );
    if (picked != null && picked != current) {
      ref.read(appModeProvider.notifier).set(picked);
      onChanged(picked);
    }
  }
}

/// The bottom-sheet body: a list of modes, each a tappable row with a tinted
/// icon, title + subtitle, and a check on the active one.
class _ModeSheet extends StatelessWidget {
  const _ModeSheet({required this.current});

  final AppMode current;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SafeArea(
      top: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Text(
              'Switch mode',
              style: theme.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
          ),
          for (final m in AppMode.values)
            _ModeRow(
              mode: m,
              selected: m == current,
              onTap: () => Navigator.of(context).pop(m),
            ),
          const SizedBox(height: 12),
        ],
      ),
    );
  }
}

class _ModeRow extends StatelessWidget {
  const _ModeRow({
    required this.mode,
    required this.selected,
    required this.onTap,
  });

  final AppMode mode;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: scheme.primary.withValues(alpha: 0.10),
              ),
              alignment: Alignment.center,
              child: Icon(ModeDropdown._icon(mode),
                  size: 22, color: scheme.primary),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    ModeDropdown._title(mode),
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    ModeDropdown._subtitle(mode),
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Icon(
              selected ? Icons.check_circle_rounded : Icons.circle_outlined,
              color: selected ? kBrandGreen : scheme.outlineVariant,
            ),
          ],
        ),
      ),
    );
  }
}
