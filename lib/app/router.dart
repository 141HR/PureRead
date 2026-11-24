import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../presentation/bookshelf/bookshelf_page.dart';
import '../presentation/reader/reader_page.dart';
import '../presentation/search/search_page.dart';
import '../presentation/settings/settings_page.dart';
import '../presentation/shells/adaptive_shell.dart';
import '../presentation/sources/sources_page.dart';

/// Named application route paths.
abstract final class AppRoutes {
  static const bookshelf = '/bookshelf';
  static const search = '/search';
  static const sources = '/sources';
  static const settings = '/settings';
  static const reader = '/reader/:bookId';

  static String readerForBook(String bookId) => '/reader/$bookId';
}

/// Top-level GoRouter configuration with a stateful adaptive shell for primary
/// destinations and a dedicated full-screen route for the reader canvas.
final routerProvider = Provider<GoRouter>((ref) {
  final rootNavigatorKey = GlobalKey<NavigatorState>(debugLabel: 'rootNav');

  return GoRouter(
    navigatorKey: rootNavigatorKey,
    initialLocation: AppRoutes.bookshelf,
    routes: [
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) {
          return AdaptiveShell(navigationShell: navigationShell);
        },
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppRoutes.bookshelf,
                builder: (context, state) => const BookshelfPage(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppRoutes.search,
                builder: (context, state) => const SearchPage(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppRoutes.sources,
                builder: (context, state) => const SourcesPage(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppRoutes.settings,
                builder: (context, state) => const SettingsPage(),
              ),
            ],
          ),
        ],
      ),
      GoRoute(
        parentNavigatorKey: rootNavigatorKey,
        path: AppRoutes.reader,
        builder: (context, state) {
          final bookId = state.pathParameters['bookId'] ?? 'demo';
          return ReaderPage(bookId: bookId);
        },
      ),
    ],
  );
});
