import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../engine/reader_engine/platform_font_resolver.dart';
import 'router.dart';

/// Builds the application [ThemeData] for [brightness] and [targetPlatform]
/// (defaulting to `defaultTargetPlatform`).
ThemeData buildPureReadTheme({
  required Brightness brightness,
  TargetPlatform? targetPlatform,
}) {
  const seedColor = Color(0xFF4A6B53);
  return ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(
      seedColor: seedColor,
      brightness: brightness,
    ),
    scaffoldBackgroundColor: brightness == Brightness.light
        ? const Color(0xFFF7F4EC)
        : null,
    fontFamily: resolvePlatformFontFamily(
      null,
      targetPlatform: targetPlatform,
    ),
    fontFamilyFallback: resolvePlatformFontFamilyFallback(
      targetPlatform: targetPlatform,
    ),
  );
}

/// Root PureRead Flutter application widget.
class PureReadApp extends ConsumerWidget {
  const PureReadApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);

    return MaterialApp.router(
      title: 'PureRead',
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.system,
      theme: buildPureReadTheme(brightness: Brightness.light),
      darkTheme: buildPureReadTheme(brightness: Brightness.dark),
      routerConfig: router,
    );
  }
}
