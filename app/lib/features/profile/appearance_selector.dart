import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/theme_mode.dart';

/// Lets the user pick the app appearance — follow-system, light, or dark.
/// Backed by [themeModeProvider], so the choice applies app-wide and persists
/// across restarts. Self-contained so it can be dropped into any settings
/// surface (currently the profile screen).
class AppearanceSelector extends ConsumerWidget {
  const AppearanceSelector({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final themeMode = ref.watch(themeModeProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'APPEARANCE',
          style: theme.textTheme.labelSmall?.copyWith(
            color: scheme.outline,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.0,
          ),
        ),
        const SizedBox(height: 8),
        SegmentedButton<ThemeMode>(
          showSelectedIcon: false,
          segments: const [
            ButtonSegment(
              value: ThemeMode.system,
              label: Text('System'),
              icon: Icon(Icons.brightness_auto_outlined),
            ),
            ButtonSegment(
              value: ThemeMode.light,
              label: Text('Light'),
              icon: Icon(Icons.light_mode_outlined),
            ),
            ButtonSegment(
              value: ThemeMode.dark,
              label: Text('Dark'),
              icon: Icon(Icons.dark_mode_outlined),
            ),
          ],
          selected: {themeMode},
          onSelectionChanged: (selection) =>
              ref.read(themeModeProvider.notifier).set(selection.first),
        ),
      ],
    );
  }
}
