import 'package:flutter/material.dart';

/// Primary navigation destination descriptor shared by [DesktopShell] and
/// [MobileShell].
class AppShellDestination {
  final String label;
  final IconData icon;
  final IconData selectedIcon;

  const AppShellDestination({
    required this.label,
    required this.icon,
    required this.selectedIcon,
  });
}

const List<AppShellDestination> kPrimaryDestinations = [
  AppShellDestination(
    label: '书架',
    icon: Icons.menu_book_outlined,
    selectedIcon: Icons.menu_book,
  ),
  AppShellDestination(
    label: '发现',
    icon: Icons.explore_outlined,
    selectedIcon: Icons.explore,
  ),
  AppShellDestination(
    label: '搜索',
    icon: Icons.search_outlined,
    selectedIcon: Icons.search,
  ),
  AppShellDestination(
    label: '书源',
    icon: Icons.extension_outlined,
    selectedIcon: Icons.extension,
  ),
  AppShellDestination(
    label: '设置',
    icon: Icons.settings_outlined,
    selectedIcon: Icons.settings,
  ),
];
