import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import 'desktop_shell.dart';
import 'mobile_shell.dart';

/// Adaptive layout shell selecting [DesktopShell] on wide viewports (Windows)
/// and [MobileShell] on narrow viewports (Android).
class AdaptiveShell extends StatelessWidget {
  final StatefulNavigationShell navigationShell;

  const AdaptiveShell({
    super.key,
    required this.navigationShell,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= kDesktopLayoutBreakpoint) {
          return DesktopShell(navigationShell: navigationShell);
        }
        return MobileShell(navigationShell: navigationShell);
      },
    );
  }
}
