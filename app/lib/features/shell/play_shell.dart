import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../data/app_mode.dart';
import 'floating_nav_bar.dart';
import 'mode_dropdown.dart';

/// Bottom-nav scaffold for Play mode. Wraps the Play/Social/Profile branches.
class PlayShell extends StatelessWidget {
  const PlayShell({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(
          'dinkSync',
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.bold,
            color: theme.colorScheme.primary,
          ),
        ),
        actions: [
          ModeDropdown(
            onChanged: (m) {
              if (m == AppMode.management) context.go('/manage');
            },
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: Stack(
        children: [
          navigationShell,
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: FloatingNavBar(
              selectedIndex: navigationShell.currentIndex,
              onDestinationSelected: (i) => navigationShell.goBranch(
                i,
                initialLocation: i == navigationShell.currentIndex,
              ),
              destinations: const [
                FloatingNavDestination(
                  icon: Icon(Icons.sports_tennis_outlined),
                  selectedIcon: Icon(Icons.sports_tennis),
                ),
                FloatingNavDestination(
                  icon: Icon(Icons.groups_outlined),
                  selectedIcon: Icon(Icons.groups),
                ),
                FloatingNavDestination(
                  icon: Icon(Icons.calendar_month_outlined),
                  selectedIcon: Icon(Icons.calendar_month),
                ),
                FloatingNavDestination(
                  icon: Icon(Icons.person_outline),
                  selectedIcon: Icon(Icons.person),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
