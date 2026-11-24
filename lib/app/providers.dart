import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Viewport width breakpoint separating mobile bottom-tab layout from desktop
/// side-rail layout.
const double kDesktopLayoutBreakpoint = 720.0;

/// Application metadata exposed to the presentation layer.
final appTitleProvider = Provider<String>((ref) => 'PureRead');
