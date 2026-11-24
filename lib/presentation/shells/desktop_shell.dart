import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'shell_destinations.dart';

/// Wide-screen desktop shell using a left navigation rail.
class DesktopShell extends StatelessWidget {
  final StatefulNavigationShell navigationShell;

  const DesktopShell({
    super.key,
    required this.navigationShell,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: Row(
        children: [
          NavigationRail(
            selectedIndex: navigationShell.currentIndex,
            labelType: NavigationRailLabelType.all,
            leading: Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Column(
                children: [
                  Icon(
                    Icons.auto_stories,
                    color: theme.colorScheme.primary,
                    size: 28,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'PureRead',
                    style: theme.textTheme.labelMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            onDestinationSelected: (index) {
              navigationShell.goBranch(
                index,
                initialLocation: index == navigationShell.currentIndex,
              );
            },
            destinations: [
              for (final dest in kPrimaryDestinations)
                NavigationRailDestination(
                  icon: Icon(dest.icon),
                  selectedIcon: Icon(dest.selectedIcon),
                  label: Text(dest.label),
                ),
            ],
          ),
          const VerticalDivider(thickness: 1, width: 1),
          Expanded(child: navigationShell),
        ],
      ),
    );
  }
}
