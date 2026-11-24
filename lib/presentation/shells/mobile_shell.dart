import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'shell_destinations.dart';

/// Narrow-screen mobile shell using a bottom navigation bar.
class MobileShell extends StatelessWidget {
  final StatefulNavigationShell navigationShell;

  const MobileShell({
    super.key,
    required this.navigationShell,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: navigationShell,
      bottomNavigationBar: NavigationBar(
        selectedIndex: navigationShell.currentIndex,
        onDestinationSelected: (index) {
          navigationShell.goBranch(
            index,
            initialLocation: index == navigationShell.currentIndex,
          );
        },
        destinations: [
          for (final dest in kPrimaryDestinations)
            NavigationDestination(
              icon: Icon(dest.icon),
              selectedIcon: Icon(dest.selectedIcon),
              label: dest.label,
            ),
        ],
      ),
    );
  }
}
