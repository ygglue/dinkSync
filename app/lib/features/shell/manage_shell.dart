import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

import '../../data/app_mode.dart';
import 'floating_nav_bar.dart';
import 'mode_dropdown.dart';

/// Bottom-nav scaffold for Court Management mode: Dashboard / Bookings / Profile.
/// Profile is the one tab shared with the Play shell.
class ManageShell extends StatelessWidget {
  const ManageShell({super.key, required this.navigationShell});

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
              if (m == AppMode.play) context.go('/play');
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
              destinations: [
                FloatingNavDestination(
                  icon: Icon(PhosphorIconsFill.squaresFour),
                  selectedIcon: Icon(PhosphorIconsFill.squaresFour),
                ),
                FloatingNavDestination(
                  icon: Icon(PhosphorIconsFill.calendarBlank),
                  selectedIcon: Icon(PhosphorIconsFill.calendarBlank),
                ),
                FloatingNavDestination(
                  icon: Icon(PhosphorIconsFill.user),
                  selectedIcon: Icon(PhosphorIconsFill.user),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
