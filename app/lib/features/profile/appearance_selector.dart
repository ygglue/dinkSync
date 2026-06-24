import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

import '../../app/theme.dart';
import '../../data/theme_mode.dart';

class AppearanceSelector extends ConsumerWidget {
  const AppearanceSelector({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeModeProvider);

    return _AppearancePill(
      value: themeMode,
      onChanged: (m) => ref.read(themeModeProvider.notifier).set(m),
    );
  }
}

class _AppearancePill extends StatelessWidget {
  const _AppearancePill({required this.value, required this.onChanged});

  final ThemeMode value;
  final ValueChanged<ThemeMode> onChanged;

  static const _options = [ThemeMode.system, ThemeMode.light, ThemeMode.dark];
  static const _labels = ['System', 'Light', 'Dark'];
  static const _icons = [
    PhosphorIconsFill.monitor,
    PhosphorIconsFill.sun,
    PhosphorIconsFill.moon,
  ];

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Container(
      height: 56,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(kRadius),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Row(
        children: List.generate(_options.length, (i) {
          final selected = value == _options[i];
          return Expanded(
            child: GestureDetector(
              onTap: () => onChanged(_options[i]),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeInOut,
                decoration: BoxDecoration(
                  color: selected ? scheme.primary : Colors.transparent,
                  borderRadius: BorderRadius.circular(kRadius - 4),
                ),
                child: Center(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        _icons[i],
                        size: 16,
                        color: selected ? scheme.onPrimary : scheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        _labels[i],
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                          color: selected ? scheme.onPrimary : scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}
