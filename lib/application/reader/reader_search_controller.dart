import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/domain.dart';
import 'in_book_search_service.dart';
import 'reader_search_state.dart';
import 'reader_session_controller.dart';

final readerSearchControllerProvider = NotifierProvider.autoDispose
    .family<ReaderSearchController, ReaderSearchState, String>(
      ReaderSearchController.new,
    );

/// Orchestrates in-book keyword search for an open reader session, managing
/// scope switching, cooperative cancellation, and streaming progress updates.
class ReaderSearchController extends Notifier<ReaderSearchState> {
  ReaderSearchController(this.bookId);

  final String bookId;

  bool _disposed = false;
  int _searchEpoch = 0;
  CancellationToken? _activeCancelToken;

  bool get _isAlive => !_disposed && ref.mounted;

  @override
  ReaderSearchState build() {
    _disposed = false;
    _searchEpoch = 0;
    _activeCancelToken?.cancel();
    _activeCancelToken = null;

    ref.onDispose(() {
      _disposed = true;
      _activeCancelToken?.cancel();
      _activeCancelToken?.dispose();
      _activeCancelToken = null;
    });

    return ReaderSearchState(bookId: bookId);
  }

  /// Executes an in-book search for [rawQuery] within [scope] (defaulting to
  /// [ReaderSearchState.scope]), cancelling any previous in-flight search.
  Future<void> search(String rawQuery, {InBookSearchScope? scope}) async {
    if (!_isAlive) return;
    final effectiveScope = scope ?? state.scope;
    final trimmed = rawQuery.trim();

    _activeCancelToken?.cancel();
    _activeCancelToken?.dispose();
    _activeCancelToken = null;
    final epoch = ++_searchEpoch;

    if (trimmed.isEmpty) {
      state = ReaderSearchState(
        bookId: bookId,
        scope: effectiveScope,
      );
      return;
    }

    final sessionState = ref.read(readerSessionControllerProvider(bookId));
    final book = sessionState.book;
    if (book == null) {
      state = state.copyWith(
        query: trimmed,
        scope: effectiveScope,
        isSearching: false,
        hasSearched: true,
        matches: const <InBookSearchMatch>[],
        isCapped: false,
        errorMessage: '书籍尚未加载完成，暂无法搜索。',
      );
      return;
    }

    final cancelToken = CancellationToken();
    _activeCancelToken = cancelToken;

    state = state.copyWith(
      query: trimmed,
      scope: effectiveScope,
      isSearching: true,
      matches: const <InBookSearchMatch>[],
      isCapped: false,
      scannedChapters: 0,
      totalCandidateChapters: 0,
      skippedUncachedChapters: 0,
      clearError: true,
      hasSearched: true,
    );

    final searchService = ref.read(inBookSearchServiceProvider);
    final sessionController = ref.read(
      readerSessionControllerProvider(bookId).notifier,
    );

    var lastProgressScanned = 0;
    var lastProgressMatchCount = 0;

    try {
      final result = await searchService.searchBook(
        book: book,
        chapters: sessionState.chapters,
        query: trimmed,
        scope: effectiveScope,
        currentChapterIndex: sessionState.currentChapterIndex,
        activeChapterText: sessionState.currentChapterText,
        chapterTextReader: (chapter) =>
            sessionController.readChapterTextForSearch(chapter.chapterIndex),
        cancelToken: cancelToken,
        onProgress: (progress) {
          if (!_isAlive || epoch != _searchEpoch || cancelToken.isCancelled) {
            return;
          }
          final matchesGrew = progress.matches.length > lastProgressMatchCount;
          final chapterStepReached =
              progress.scannedChapters - lastProgressScanned >= 16;
          if (!matchesGrew && !chapterStepReached && !progress.isCapped) {
            return;
          }
          lastProgressScanned = progress.scannedChapters;
          lastProgressMatchCount = progress.matches.length;
          state = state.copyWith(
            matches: progress.matches,
            isCapped: progress.isCapped,
            scannedChapters: progress.scannedChapters,
            totalCandidateChapters: progress.totalCandidateChapters,
            skippedUncachedChapters: progress.skippedUncachedChapters,
          );
        },
      );

      if (!_isAlive || epoch != _searchEpoch || cancelToken.isCancelled) {
        return;
      }

      state = state.copyWith(
        isSearching: false,
        matches: result.matches,
        isCapped: result.isCapped,
        scannedChapters: result.scannedChapters,
        totalCandidateChapters: result.totalCandidateChapters,
        skippedUncachedChapters: result.skippedUncachedChapters,
        clearError: true,
        hasSearched: true,
      );
    } on CancelledFailure {
      if (_isAlive && epoch == _searchEpoch) {
        state = state.copyWith(isSearching: false);
      }
    } catch (error) {
      if (!_isAlive || epoch != _searchEpoch || cancelToken.isCancelled) {
        return;
      }
      state = state.copyWith(
        isSearching: false,
        errorMessage: error is AppFailure ? error.message : '搜索失败：$error',
      );
    } finally {
      if (identical(_activeCancelToken, cancelToken)) {
        _activeCancelToken = null;
      }
      cancelToken.dispose();
    }
  }

  /// Switches the search scope and re-runs the current query if non-empty.
  Future<void> setScope(InBookSearchScope nextScope) async {
    if (!_isAlive || state.scope == nextScope) return;
    if (state.query.trim().isEmpty) {
      state = state.copyWith(scope: nextScope);
      return;
    }
    await search(state.query, scope: nextScope);
  }

  /// Cancels any active search operation without clearing already collected matches.
  void cancelSearch() {
    _searchEpoch++;
    _activeCancelToken?.cancel();
    _activeCancelToken?.dispose();
    _activeCancelToken = null;
    if (_isAlive && state.isSearching) {
      state = state.copyWith(isSearching: false);
    }
  }

  /// Cancels any active search and resets query and match results.
  void clear() {
    _searchEpoch++;
    _activeCancelToken?.cancel();
    _activeCancelToken?.dispose();
    _activeCancelToken = null;
    if (_isAlive) {
      state = ReaderSearchState(bookId: bookId, scope: state.scope);
    }
  }
}
