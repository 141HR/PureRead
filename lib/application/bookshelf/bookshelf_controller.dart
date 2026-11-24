import 'dart:async';
import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../domain/domain.dart';
import '../core_providers.dart';
import '../m2_providers.dart';
import 'bookshelf_state.dart';
import 'local_epub_providers.dart';

const String _kViewModeSettingKey = 'bookshelf_view_mode';
const String _kSortModeSettingKey = 'bookshelf_sort_mode';

final bookshelfControllerProvider =
    NotifierProvider<BookshelfController, BookshelfState>(
      BookshelfController.new,
    );

/// Manages bookshelf sorting, view mode persistence, group management (F1.3),
/// pin/unpin, deletion with optional chapter cache cleanup, and unified
/// single/batch local TXT & EPUB imports.
class BookshelfController extends Notifier<BookshelfState> {
  StreamSubscription<List<Book>>? _booksSub;
  bool _disposed = false;
  bool _initialized = false;

  bool get _isAlive => !_disposed && ref.mounted;

  @override
  BookshelfState build() {
    _disposed = false;
    _initialized = false;
    ref.onDispose(() {
      _disposed = true;
      unawaited(_booksSub?.cancel());
      _booksSub = null;
    });
    Future<void>.microtask(_initialize);
    return const BookshelfState(isLoading: true);
  }

  Future<void> _initialize() async {
    if (!_isAlive || _initialized) return;
    _initialized = true;

    final themeRepo = ref.read(themeRepositoryProvider);
    final bookRepo = ref.read(bookRepositoryProvider);

    var viewMode = BookshelfViewMode.grid;
    var sortMode = BookshelfSortMode.recentRead;

    try {
      final viewSetting = await themeRepo.getSetting(_kViewModeSettingKey);
      if (!_isAlive) return;
      if (viewSetting != null) {
        viewMode = BookshelfViewMode.values.firstWhere(
          (m) => m.name == viewSetting.value,
          orElse: () => BookshelfViewMode.grid,
        );
      }
      final sortSetting = await themeRepo.getSetting(_kSortModeSettingKey);
      if (!_isAlive) return;
      if (sortSetting != null) {
        sortMode = BookshelfSortMode.values.firstWhere(
          (m) => m.name == sortSetting.value,
          orElse: () => BookshelfSortMode.recentRead,
        );
      }
    } catch (_) {
      // Fall back to default bookshelf preferences if settings cannot be read.
    }

    if (!_isAlive) return;
    state = state.copyWith(viewMode: viewMode, sortMode: sortMode);

    await _booksSub?.cancel();
    if (!_isAlive) return;
    _booksSub = bookRepo.watchBooks().listen(
      (books) {
        if (_isAlive) {
          unawaited(_applyLoadedBooks(books));
        }
      },
      onError: (Object error) {
        if (!_isAlive) return;
        state = state.copyWith(
          isLoading: false,
          errorMessage: _formatError(error),
        );
      },
    );

    await refresh();
  }

  Future<void> _applyLoadedBooks(
    List<Book> rawBooks, {
    List<BookGroup>? loadedGroups,
  }) async {
    if (!_isAlive) return;
    final bookRepo = ref.read(bookRepositoryProvider);

    var groups = loadedGroups ?? state.groups;
    if (loadedGroups == null) {
      try {
        groups = await bookRepo.listGroups();
        if (!_isAlive) return;
      } catch (_) {
        // Keep existing groups if transient lookup fails.
      }
    }
    final sortedGroups = _sortGroups(groups);

    final progressMap = <String, ReadingProgress>{};
    for (final book in rawBooks) {
      if (!_isAlive) return;
      try {
        final progress = await bookRepo.getProgress(book.id);
        if (!_isAlive) return;
        if (progress != null) {
          progressMap[book.id] = progress;
        }
      } catch (_) {
        // Ignore single-book progress lookup failure so shelf stays responsive.
      }
    }
    if (!_isAlive) return;

    final existingBookIds = rawBooks.map((b) => b.id).toSet();
    final validSelectedBookIds = state.selectedBookIds
        .where(existingBookIds.contains)
        .toSet();
    final selectedGroupStillValid =
        state.selectedGroupId == null ||
        state.selectedGroupId == kUngroupedBookGroupFilterId ||
        sortedGroups.any((g) => g.id == state.selectedGroupId);

    state = state.copyWith(
      books: sortBooks(rawBooks, state.sortMode),
      groups: sortedGroups,
      clearSelectedGroup: !selectedGroupStillValid,
      selectedBookIds: validSelectedBookIds,
      isSelectionMode:
          validSelectedBookIds.isNotEmpty ? state.isSelectionMode : false,
      progressByBookId: progressMap,
      isLoading: false,
    );
  }

  /// Reloads books, groups, and reading progress snapshots from the repository.
  Future<void> refresh() async {
    if (!_isAlive) return;
    final bookRepo = ref.read(bookRepositoryProvider);
    try {
      final books = await bookRepo.listBooks();
      if (!_isAlive) return;
      final groups = await bookRepo.listGroups();
      if (!_isAlive) return;
      await _applyLoadedBooks(books, loadedGroups: groups);
    } catch (error) {
      if (!_isAlive) return;
      state = state.copyWith(
        isLoading: false,
        errorMessage: _formatError(error),
      );
    }
  }

  /// Switches between grid and list view modes and persists the preference.
  Future<void> toggleViewMode() async {
    if (!_isAlive) return;
    final next = state.viewMode == BookshelfViewMode.grid
        ? BookshelfViewMode.list
        : BookshelfViewMode.grid;
    state = state.copyWith(viewMode: next);
    await _saveSetting(_kViewModeSettingKey, next.name);
  }

  /// Sets [BookshelfSortMode], re-sorts the shelf, and persists the choice.
  Future<void> setSortMode(BookshelfSortMode mode) async {
    if (!_isAlive) return;
    state = state.copyWith(
      sortMode: mode,
      books: sortBooks(state.books, mode),
    );
    await _saveSetting(_kSortModeSettingKey, mode.name);
  }

  /// Filters bookshelf items locally by title or author.
  void setSearchQuery(String query) {
    if (!_isAlive) return;
    state = state.copyWith(searchQuery: query);
  }

  /// Selects a group filter (`null` = 全部, [kUngroupedBookGroupFilterId] = 未分组).
  void selectGroup(String? groupId) {
    if (!_isAlive) return;
    state = state.copyWith(
      selectedGroupId: groupId,
      clearSelectedGroup: groupId == null,
      selectedBookIds: const <String>{},
    );
  }

  /// Creates a new custom [BookGroup] with [name] and refreshes the group list.
  Future<BookGroup?> createGroup(String name) async {
    if (!_isAlive) return null;
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      state = state.copyWith(errorMessage: '分组名称不能为空');
      return null;
    }

    final bookRepo = ref.read(bookRepositoryProvider);
    try {
      final existing = await bookRepo.listGroups();
      if (!_isAlive) return null;
      final maxOrder = existing.fold<int>(
        0,
        (prev, g) => math.max(prev, g.sortOrder),
      );
      final now = DateTime.now().toUtc();
      final group = BookGroup(
        id: 'grp_${now.microsecondsSinceEpoch}',
        name: trimmed,
        sortOrder: maxOrder + 1,
        createdAt: now,
        updatedAt: now,
      );
      await bookRepo.saveGroup(group);
      if (!_isAlive) return null;
      await refresh();
      return group;
    } catch (error) {
      if (!_isAlive) return null;
      state = state.copyWith(errorMessage: _formatError(error));
      return null;
    }
  }

  /// Renames [groupId] to [newName] and refreshes the group list.
  Future<void> renameGroup(String groupId, String newName) async {
    if (!_isAlive) return;
    final trimmed = newName.trim();
    if (trimmed.isEmpty) {
      state = state.copyWith(errorMessage: '分组名称不能为空');
      return;
    }

    final bookRepo = ref.read(bookRepositoryProvider);
    try {
      final groups = await bookRepo.listGroups();
      if (!_isAlive) return;
      final idx = groups.indexWhere((g) => g.id == groupId);
      if (idx < 0) return;
      final updated = groups[idx].copyWith(
        name: trimmed,
        updatedAt: DateTime.now().toUtc(),
      );
      await bookRepo.saveGroup(updated);
      if (!_isAlive) return;
      await refresh();
    } catch (error) {
      if (!_isAlive) return;
      state = state.copyWith(errorMessage: _formatError(error));
    }
  }

  /// Deletes [groupId] and frees any books in that group to `groupId = null`.
  Future<void> deleteGroup(String groupId) async {
    if (!_isAlive) return;
    final bookRepo = ref.read(bookRepositoryProvider);
    try {
      await bookRepo.deleteGroup(groupId);
      if (!_isAlive) return;

      // Ensure repositories without SQLite ON DELETE SET NULL also unassign books.
      final allBooks = await bookRepo.listBooks();
      if (!_isAlive) return;
      final now = DateTime.now().toUtc();
      for (final book in allBooks) {
        if (book.groupId == groupId) {
          await bookRepo.saveBook(
            book.copyWith(clearGroupId: true, updatedAt: now),
          );
          if (!_isAlive) return;
        }
      }

      if (state.selectedGroupId == groupId) {
        state = state.copyWith(clearSelectedGroup: true);
      }
      await refresh();
    } catch (error) {
      if (!_isAlive) return;
      state = state.copyWith(errorMessage: _formatError(error));
    }
  }

  /// Moves a single [bookId] into [groupId] (or ungrouped when `null`).
  Future<void> moveBookToGroup(String bookId, String? groupId) {
    return moveBooksToGroup(<String>[bookId], groupId);
  }

  /// Moves all books in [bookIds] into [groupId] (or ungrouped when `null`).
  Future<void> moveBooksToGroup(
    Iterable<String> bookIds,
    String? groupId,
  ) async {
    if (!_isAlive) return;
    final ids = bookIds.toSet();
    if (ids.isEmpty) return;

    final bookRepo = ref.read(bookRepositoryProvider);
    try {
      final now = DateTime.now().toUtc();
      for (final id in ids) {
        final existing = await bookRepo.getBookById(id);
        if (!_isAlive) return;
        if (existing == null) continue;
        final updated = groupId == null
            ? existing.copyWith(clearGroupId: true, updatedAt: now)
            : existing.copyWith(groupId: groupId, updatedAt: now);
        await bookRepo.saveBook(updated);
        if (!_isAlive) return;
      }

      state = state.copyWith(
        selectedBookIds: const <String>{},
        isSelectionMode: false,
      );
      await refresh();
    } catch (error) {
      if (!_isAlive) return;
      state = state.copyWith(errorMessage: _formatError(error));
    }
  }

  /// Toggles or explicitly sets multi-book selection mode.
  void toggleSelectionMode([bool? enabled]) {
    if (!_isAlive) return;
    final next = enabled ?? !state.isSelectionMode;
    state = state.copyWith(
      isSelectionMode: next,
      selectedBookIds: next ? state.selectedBookIds : const <String>{},
    );
  }

  /// Toggles selection of [bookId] in multi-select mode.
  void toggleBookSelection(String bookId) {
    if (!_isAlive) return;
    final next = Set<String>.from(state.selectedBookIds);
    if (!next.add(bookId)) {
      next.remove(bookId);
    }
    state = state.copyWith(
      isSelectionMode: true,
      selectedBookIds: next,
    );
  }

  /// Selects all books currently visible under active group/search filters.
  void selectAllVisible() {
    if (!_isAlive) return;
    final visibleIds = state.filteredBooks.map((b) => b.id).toSet();
    state = state.copyWith(
      isSelectionMode: true,
      selectedBookIds: visibleIds,
    );
  }

  /// Exits multi-select mode and clears selected book IDs.
  void clearSelection() {
    if (!_isAlive) return;
    state = state.copyWith(
      isSelectionMode: false,
      selectedBookIds: const <String>{},
    );
  }

  /// Toggles the pinned status of [bookId] and persists it immediately.
  Future<void> togglePin(String bookId) async {
    if (!_isAlive) return;
    final bookRepo = ref.read(bookRepositoryProvider);
    final idx = state.books.indexWhere((b) => b.id == bookId);
    if (idx < 0) return;
    final target = state.books[idx];
    final updated = target.copyWith(
      isPinned: !target.isPinned,
      updatedAt: DateTime.now(),
    );
    try {
      await bookRepo.saveBook(updated);
      await refresh();
    } catch (error) {
      if (!_isAlive) return;
      state = state.copyWith(errorMessage: _formatError(error));
    }
  }

  /// Removes [bookId] from the bookshelf, optionally clearing cached chapters.
  Future<void> deleteBook(
    String bookId, {
    bool deleteCachedChapters = false,
  }) {
    return deleteBooks(
      <String>[bookId],
      deleteCachedChapters: deleteCachedChapters,
    );
  }

  /// Removes all [bookIds] from the bookshelf, optionally clearing cached
  /// chapters via [ChapterCacheGateway.deleteBookCache].
  Future<void> deleteBooks(
    Iterable<String> bookIds, {
    bool deleteCachedChapters = false,
  }) async {
    if (!_isAlive) return;
    final ids = bookIds.toSet();
    if (ids.isEmpty) return;

    final bookRepo = ref.read(bookRepositoryProvider);
    final cacheGateway = ref.read(chapterCacheGatewayProvider);
    try {
      for (final id in ids) {
        if (deleteCachedChapters) {
          await cacheGateway.deleteBookCache(id);
          if (!_isAlive) return;
        }
        await bookRepo.deleteBook(id);
        if (!_isAlive) return;
      }

      final remainingSelected = Set<String>.from(state.selectedBookIds)
        ..removeAll(ids);
      state = state.copyWith(
        selectedBookIds: remainingSelected,
        isSelectionMode:
            remainingSelected.isNotEmpty ? state.isSelectionMode : false,
      );
      await refresh();
    } catch (error) {
      if (!_isAlive) return;
      state = state.copyWith(errorMessage: _formatError(error));
    }
  }

  /// Opens the native multi-select `.txt` / `.epub` file picker and imports
  /// selected books.
  Future<void> importLocalBookFiles() async {
    if (!_isAlive || state.isImporting) return;
    final platform = ref.read(platformBridgeProvider);
    try {
      final paths = await platform.pickFiles(
        extensions: const <String>['txt', 'epub'],
        allowMultiple: true,
      );
      if (!_isAlive || paths.isEmpty) return;
      await importFilePaths(paths);
    } catch (error) {
      if (!_isAlive) return;
      state = state.copyWith(
        isImporting: false,
        errorMessage: '打开文件选择器失败：${_formatError(error)}',
      );
    }
  }

  /// Backward-compatible alias for [importLocalBookFiles].
  Future<void> importLocalTxtFiles() => importLocalBookFiles();

  /// Imports one or more local `.txt` or `.epub` files at [filePaths] via
  /// [txtBookImporterProvider] / [epubBookImporterProvider] and persists them
  /// to [BookRepository].
  Future<void> importFilePaths(
    List<String> filePaths, {
    String? forcedEncoding,
  }) async {
    if (!_isAlive || filePaths.isEmpty) return;
    final txtImporter = ref.read(txtBookImporterProvider);
    final epubImporter = ref.read(epubBookImporterProvider);
    final bookRepo = ref.read(bookRepositoryProvider);

    state = state.copyWith(
      isImporting: true,
      importDoneCount: 0,
      importTotalCount: filePaths.length,
      clearImportStatus: true,
      clearUpdateStatus: true,
      clearError: true,
    );

    var successCount = 0;
    final errors = <String>[];

    for (var i = 0; i < filePaths.length; i++) {
      if (!_isAlive) return;
      final filePath = filePaths[i];
      try {
        final ext = p.extension(filePath).trim().toLowerCase();
        final ({Book book, List<ChapterMeta> chapters}) imported;
        if (ext == '.epub') {
          imported = await epubImporter(filePath);
        } else if (ext == '.txt' || ext.isEmpty) {
          imported = await txtImporter(
            filePath,
            forcedEncoding: forcedEncoding,
          );
        } else {
          throw FileAccessFailure(
            message: '不支持的本地文件格式（仅支持 .txt / .epub）：${p.basename(filePath)}',
            filePath: filePath,
          );
        }
        if (!_isAlive) return;
        final existing = await bookRepo.getBookById(imported.book.id);
        if (!_isAlive) return;
        final bookToSave = existing == null
            ? imported.book
            : imported.book.copyWith(
                isPinned: existing.isPinned,
                groupId: existing.groupId,
                lastReadAt: existing.lastReadAt,
                lastChapterTitle: existing.lastChapterTitle.isNotEmpty
                    ? existing.lastChapterTitle
                    : imported.book.lastChapterTitle,
                coverPath: imported.book.coverPath ?? existing.coverPath,
              );
        await bookRepo.saveBook(bookToSave);
        if (!_isAlive) return;
        await bookRepo.replaceChapters(bookToSave.id, imported.chapters);
        successCount++;
      } catch (error) {
        final fileName = p.basename(filePath);
        errors.add('$fileName：${_formatError(error)}');
      }
      if (!_isAlive) return;
      state = state.copyWith(importDoneCount: i + 1);
    }

    await refresh();
    if (!_isAlive) return;
    state = state.copyWith(
      isImporting: false,
      importStatusMessage: successCount > 0 ? '已成功导入 $successCount 本书籍' : null,
      errorMessage: errors.isNotEmpty ? errors.join('\n') : null,
    );
  }

  /// Checks all online books on the shelf for newly published chapters using
  /// bounded concurrency, persisting newly discovered chapters and unread counts
  /// while skipping missing or broken sources gracefully.
  Future<void> checkUpdates({int maxConcurrency = 4}) async {
    if (!_isAlive || state.isCheckingUpdates) return;
    final bookRepo = ref.read(bookRepositoryProvider);
    final sourceRepo = ref.read(sourceRepositoryProvider);
    final providerFactory = ref.read(bookProviderFactoryProvider);

    state = state.copyWith(
      isCheckingUpdates: true,
      clearImportStatus: true,
      clearUpdateStatus: true,
      clearError: true,
    );

    final List<Book> onlineBooks;
    try {
      final allBooks = await bookRepo.listBooks();
      if (!_isAlive) return;
      onlineBooks = allBooks
          .where(
            (b) =>
                b.providerType == ProviderType.jsPlugin ||
                b.providerType == ProviderType.legado,
          )
          .toList(growable: false);
    } catch (error) {
      if (!_isAlive) return;
      state = state.copyWith(
        isCheckingUpdates: false,
        errorMessage: '加载书架书籍失败：${_formatError(error)}',
      );
      return;
    }

    if (onlineBooks.isEmpty) {
      state = state.copyWith(
        isCheckingUpdates: false,
        updateStatusMessage: '书架暂无在线书籍',
      );
      return;
    }

    var nextIdx = 0;
    var updatedBooksCount = 0;
    var totalNewChapters = 0;
    var skippedCount = 0;

    Future<void> worker() async {
      while (true) {
        if (!_isAlive || nextIdx >= onlineBooks.length) return;
        final book = onlineBooks[nextIdx++];
        try {
          final sourceId = book.sourceId?.trim() ?? '';
          if (sourceId.isEmpty) {
            skippedCount++;
            continue;
          }
          final source = await sourceRepo.getSourceById(sourceId);
          if (!_isAlive) return;
          if (source == null) {
            skippedCount++;
            continue;
          }

          final provider = await providerFactory.createProvider(source);
          if (!_isAlive) return;
          if (!provider.capabilities.supportsUpdateCheck) {
            skippedCount++;
            continue;
          }

          var tocUrl = book.tocUrl?.trim() ?? '';
          if (tocUrl.isEmpty) {
            final originUrl = book.originBookUrl?.trim() ?? '';
            if (originUrl.isEmpty) {
              skippedCount++;
              continue;
            }
            try {
              final detailRes = await provider.getBookDetail(originUrl);
              if (!_isAlive) return;
              tocUrl = detailRes.detail.tocUrl.trim().isNotEmpty
                  ? detailRes.detail.tocUrl.trim()
                  : originUrl;
            } catch (_) {
              tocUrl = originUrl;
            }
          }

          final tocRes = await provider.getToc(tocUrl);
          if (!_isAlive) return;
          final remoteChapters = tocRes.chapters;
          if (remoteChapters.isEmpty) {
            skippedCount++;
            continue;
          }

          final existingChapters = await bookRepo.listChapters(book.id);
          if (!_isAlive) return;
          final previousCount = math.max(
            book.totalChapters,
            existingChapters.length,
          );
          if (remoteChapters.length <= previousCount) {
            if (existingChapters.isEmpty) {
              final now = DateTime.now().toUtc();
              final rebuilt = remoteChapters
                  .asMap()
                  .entries
                  .map(
                    (entry) => entry.value.copyWith(
                      bookId: book.id,
                      chapterIndex: entry.key,
                      isCached: false,
                      cacheKey: null,
                      updatedAt: now,
                    ),
                  )
                  .toList(growable: false);
              await bookRepo.replaceChapters(book.id, rebuilt);
            }
            continue;
          }

          final addedCount = remoteChapters.length - previousCount;
          final existingByIndex = <int, ChapterMeta>{
            for (final ch in existingChapters) ch.chapterIndex: ch,
          };
          final now = DateTime.now().toUtc();
          final mergedChapters = remoteChapters
              .asMap()
              .entries
              .map((entry) {
                final idx = entry.key;
                final remote = entry.value;
                final prev = existingByIndex[idx];
                final sameChapter =
                    prev != null &&
                    ((prev.url != null &&
                            remote.url != null &&
                            prev.url == remote.url) ||
                        prev.title == remote.title);
                return remote.copyWith(
                  bookId: book.id,
                  chapterIndex: idx,
                  isCached: sameChapter ? prev.isCached : false,
                  cacheKey: sameChapter ? prev.cacheKey : null,
                  wordCount: sameChapter ? prev.wordCount : remote.wordCount,
                  updatedAt: now,
                );
              })
              .toList(growable: false);

          await bookRepo.replaceChapters(book.id, mergedChapters);
          if (!_isAlive) return;

          final updatedBook = book.copyWith(
            tocUrl: tocUrl,
            totalChapters: mergedChapters.length,
            unreadCount: book.unreadCount + addedCount,
            lastChapterTitle: mergedChapters.last.title,
            latestChapterAt: now,
            updatedAt: now,
          );
          await bookRepo.saveBook(updatedBook);
          if (!_isAlive) return;

          updatedBooksCount++;
          totalNewChapters += addedCount;
        } catch (_) {
          skippedCount++;
        }
      }
    }

    final workerCount = math.min(
      math.max(1, maxConcurrency),
      onlineBooks.length,
    );
    await Future.wait<void>(
      List<Future<void>>.generate(workerCount, (_) => worker()),
    );
    if (!_isAlive) return;

    await refresh();
    if (!_isAlive) return;

    final String summary;
    if (updatedBooksCount > 0) {
      summary =
          '更新完成：$updatedBooksCount 本书有新章节（共 +$totalNewChapters 章）'
          '${skippedCount > 0 ? ' · $skippedCount 本书源不可用已跳过' : ''}';
    } else if (skippedCount > 0) {
      summary = '检查更新完成：暂无新章节（$skippedCount 本书源缺失或请求失败已跳过）';
    } else {
      summary = '检查更新完成：所有在线书籍均已是最新章节';
    }

    state = state.copyWith(
      isCheckingUpdates: false,
      updateStatusMessage: summary,
    );
  }

  /// Dismisses active import, update-check, or error banners.
  void clearBanner() {
    if (!_isAlive) return;
    state = state.copyWith(
      clearImportStatus: true,
      clearUpdateStatus: true,
      clearError: true,
    );
  }

  /// Sorts [books] keeping pinned books first, then ordering by [mode].
  static List<Book> sortBooks(List<Book> books, BookshelfSortMode mode) {
    final sorted = List<Book>.from(books);
    sorted.sort((a, b) {
      if (a.isPinned != b.isPinned) {
        return a.isPinned ? -1 : 1;
      }
      switch (mode) {
        case BookshelfSortMode.recentRead:
          final aRead = a.lastReadAt;
          final bRead = b.lastReadAt;
          if (aRead != null && bRead != null) {
            final cmp = bRead.compareTo(aRead);
            if (cmp != 0) return cmp;
          } else if (aRead != null || bRead != null) {
            return aRead != null ? -1 : 1;
          }
          final updatedCmp = b.updatedAt.compareTo(a.updatedAt);
          if (updatedCmp != 0) return updatedCmp;
          return a.title.toLowerCase().compareTo(b.title.toLowerCase());

        case BookshelfSortMode.updatedAt:
          final aTime = a.latestChapterAt ?? a.updatedAt;
          final bTime = b.latestChapterAt ?? b.updatedAt;
          final cmp = bTime.compareTo(aTime);
          if (cmp != 0) return cmp;
          return a.title.toLowerCase().compareTo(b.title.toLowerCase());

        case BookshelfSortMode.title:
          final titleCmp = a.title.toLowerCase().compareTo(
            b.title.toLowerCase(),
          );
          if (titleCmp != 0) return titleCmp;
          return b.updatedAt.compareTo(a.updatedAt);
      }
    });
    return sorted;
  }

  static List<BookGroup> _sortGroups(List<BookGroup> groups) {
    final sorted = List<BookGroup>.from(groups);
    sorted.sort((a, b) {
      final orderCmp = a.sortOrder.compareTo(b.sortOrder);
      if (orderCmp != 0) return orderCmp;
      return a.createdAt.compareTo(b.createdAt);
    });
    return sorted;
  }

  Future<void> _saveSetting(String key, String value) async {
    if (!_isAlive) return;
    final themeRepo = ref.read(themeRepositoryProvider);
    try {
      await themeRepo.saveSetting(
        AppSetting(key: key, value: value, updatedAt: DateTime.now()),
      );
    } catch (_) {
      // Ignore persistence failures for non-critical UI preferences.
    }
  }

  String _formatError(Object error) {
    if (error is AppFailure) return error.message;
    return error.toString();
  }
}
