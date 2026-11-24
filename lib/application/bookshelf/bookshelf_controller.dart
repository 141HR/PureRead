import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../domain/domain.dart';
import '../core_providers.dart';
import 'bookshelf_state.dart';

const String _kViewModeSettingKey = 'bookshelf_view_mode';
const String _kSortModeSettingKey = 'bookshelf_sort_mode';

final bookshelfControllerProvider =
    NotifierProvider<BookshelfController, BookshelfState>(
      BookshelfController.new,
    );

/// Manages bookshelf sorting, view mode persistence, pin/unpin, deletion,
/// and single/batch local TXT book imports.
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

  Future<void> _applyLoadedBooks(List<Book> rawBooks) async {
    if (!_isAlive) return;
    final bookRepo = ref.read(bookRepositoryProvider);
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
    state = state.copyWith(
      books: sortBooks(rawBooks, state.sortMode),
      progressByBookId: progressMap,
      isLoading: false,
    );
  }

  /// Reloads books and their reading progress snapshots from the repository.
  Future<void> refresh() async {
    if (!_isAlive) return;
    final bookRepo = ref.read(bookRepositoryProvider);
    try {
      final books = await bookRepo.listBooks();
      await _applyLoadedBooks(books);
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

  /// Removes [bookId] from the bookshelf and refreshes the list.
  Future<void> deleteBook(String bookId) async {
    if (!_isAlive) return;
    final bookRepo = ref.read(bookRepositoryProvider);
    try {
      await bookRepo.deleteBook(bookId);
      await refresh();
    } catch (error) {
      if (!_isAlive) return;
      state = state.copyWith(errorMessage: _formatError(error));
    }
  }

  /// Opens the native multi-select TXT file picker and imports selected books.
  Future<void> importLocalTxtFiles() async {
    if (!_isAlive || state.isImporting) return;
    final platform = ref.read(platformBridgeProvider);
    try {
      final paths = await platform.pickFiles(
        extensions: const <String>['txt'],
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

  /// Imports one or more local TXT files at [filePaths] via
  /// [txtBookImporterProvider] and persists them to [BookRepository].
  Future<void> importFilePaths(
    List<String> filePaths, {
    String? forcedEncoding,
  }) async {
    if (!_isAlive || filePaths.isEmpty) return;
    final importer = ref.read(txtBookImporterProvider);
    final bookRepo = ref.read(bookRepositoryProvider);

    state = state.copyWith(
      isImporting: true,
      importDoneCount: 0,
      importTotalCount: filePaths.length,
      clearImportStatus: true,
      clearError: true,
    );

    var successCount = 0;
    final errors = <String>[];

    for (var i = 0; i < filePaths.length; i++) {
      if (!_isAlive) return;
      final filePath = filePaths[i];
      try {
        final imported = await importer(
          filePath,
          forcedEncoding: forcedEncoding,
        );
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

  /// Dismisses active import success or error banners.
  void clearBanner() {
    if (!_isAlive) return;
    state = state.copyWith(clearImportStatus: true, clearError: true);
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
