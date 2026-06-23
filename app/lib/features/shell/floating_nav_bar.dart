import 'package:flutter/material.dart';

class FloatingNavDestination {
  const FloatingNavDestination({
    required this.icon,
    required this.selectedIcon,
  });

  final Widget icon;
  final Widget selectedIcon;
}

/// A pill-shaped floating navigation bar with a sliding selection indicator.
/// Place it inside a [Stack] with [Positioned(left:0, right:0, bottom:0)].
class FloatingNavBar extends StatelessWidget {
  const FloatingNavBar({
    super.key,
    required this.destinations,
    required this.selectedIndex,
    required this.onDestinationSelected,
  });

  final List<FloatingNavDestination> destinations;
  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final bottomInset = MediaQuery.of(context).padding.bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 0, 16, bottomInset + 16),
      child: Material(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(100),
        elevation: 6,
        shadowColor: scheme.shadow.withValues(alpha: 0.25),
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final itemWidth = constraints.maxWidth / destinations.length;
              return Stack(
                children: [
                  // Sliding indicator — animates to the active item's position.
                  AnimatedPositioned(
                    duration: const Duration(milliseconds: 280),
                    curve: Curves.easeInOut,
                    left: selectedIndex * itemWidth,
                    width: itemWidth,
                    top: 0,
                    bottom: 0,
                    child: Container(
                      margin: const EdgeInsets.all(2),
                      decoration: BoxDecoration(
                        color: scheme.primary.withValues(alpha: 0.28),
                        borderRadius: BorderRadius.circular(100),
                      ),
                    ),
                  ),
                  // Icon row sits above the indicator.
                  Row(
                    children: [
                      for (int i = 0; i < destinations.length; i++)
                        Expanded(
                          child: _NavItem(
                            destination: destinations[i],
                            selected: i == selectedIndex,
                            onTap: () => onDestinationSelected(i),
                          ),
                        ),
                    ],
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.destination,
    required this.selected,
    required this.onTap,
  });

  final FloatingNavDestination destination;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      borderRadius: BorderRadius.circular(100),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Center(
          child: IconTheme(
            data: IconThemeData(
              color: selected ? scheme.primary : scheme.onSurfaceVariant,
              size: 24,
            ),
            child: selected ? destination.selectedIcon : destination.icon,
          ),
        ),
      ),
    );
  }
}
