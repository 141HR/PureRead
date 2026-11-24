import 'package:drift/drift.dart';

import '../../domain/entities/book.dart';
import '../../domain/entities/book_group.dart';
import '../../domain/entities/bookmark.dart';
import '../../domain/entities/chapter.dart';
import '../../domain/entities/reading_progress.dart';
import '../../domain/repositories/book_repository.dart';
import 'app_database.dart';
import 'drift_mappers.dart';

/// Drift-backed implementation of [BookRepository].
class DriftBookRepository implements BookRepository {
  final AppDatabase _db;

  const DriftBookRepository(this._db);

  SimpleSelectStatement<$BooksTable, BookRow> _booksQuery(String? groupId) {
    final query = _db.select(_db.books);
    if (groupId != null) {
      query.where((b) => b.groupId.equals(groupId));
    }
    query.orderBy([
      (b) => OrderingTerm.desc(b.isPinned),
      (b) => OrderingTerm.desc(b.lastReadAt),
      (b) => OrderingTerm.desc(b.updatedAt),
      (b) => OrderingTerm.desc(b.createdAt),
    ]);
    return query;
  }

  @override
  Stream<List<Book>> watchBooks({String? groupId}) {
    return guardDbStream(
      'watchBooks',
      () => _booksQuery(
        groupId,
      ).watch().map((rows) => rows.map(bookFromRow).toList(growable: false)),
    );
  }

  @override
  Future<List<Book>> listBooks({String? groupId}) {
    return guardDbCall('listBooks', () async {
      final rows = await _booksQuery(groupId).get();
      return rows.map(bookFromRow).toList(growable: false);
    });
  }

  @override
  Future<Book?> getBookById(String bookId) {
    return guardDbCall('getBookById', () async {
      final row = await (_db.select(
        _db.books,
      )..where((b) => b.id.equals(bookId))).getSingleOrNull();
      return row == null ? null : bookFromRow(row);
    });
  }

  @override
  Future<Book?> findBySourceAndUrl(String sourceId, String originBookUrl) {
    return guardDbCall('findBySourceAndUrl', () async {
      final row =
          await (_db.select(_db.books)
                ..where(
                  (b) =>
                      b.sourceId.equals(sourceId) &
                      b.originBookUrl.equals(originBookUrl),
                )
                ..limit(1))
              .getSingleOrNull();
      return row == null ? null : bookFromRow(row);
    });
  }

  @override
  Future<void> saveBook(Book book) {
    return guardDbCall('saveBook', () async {
      await _db.into(_db.books).insertOnConflictUpdate(bookToCompanion(book));
    });
  }

  @override
  Future<void> deleteBook(String bookId) {
    return guardDbCall('deleteBook', () async {
      await (_db.delete(_db.books)..where((b) => b.id.equals(bookId))).go();
    });
  }

  @override
  Future<List<BookGroup>> listGroups() {
    return guardDbCall('listGroups', () async {
      final rows =
          await (_db.select(_db.bookGroups)..orderBy([
                (g) => OrderingTerm.asc(g.sortOrder),
                (g) => OrderingTerm.asc(g.createdAt),
              ]))
              .get();
      return rows.map(bookGroupFromRow).toList(growable: false);
    });
  }

  @override
  Future<void> saveGroup(BookGroup group) {
    return guardDbCall('saveGroup', () async {
      await _db
          .into(_db.bookGroups)
          .insertOnConflictUpdate(bookGroupToCompanion(group));
    });
  }

  @override
  Future<void> deleteGroup(String groupId) {
    return guardDbCall('deleteGroup', () async {
      await (_db.delete(
        _db.bookGroups,
      )..where((g) => g.id.equals(groupId))).go();
    });
  }

  @override
  Future<List<ChapterMeta>> listChapters(String bookId) {
    return guardDbCall('listChapters', () async {
      final rows =
          await (_db.select(_db.chapters)
                ..where((c) => c.bookId.equals(bookId))
                ..orderBy([(c) => OrderingTerm.asc(c.chapterIndex)]))
              .get();
      return rows.map(chapterFromRow).toList(growable: false);
    });
  }

  @override
  Future<ChapterMeta?> getChapter(String bookId, int chapterIndex) {
    return guardDbCall('getChapter', () async {
      final row =
          await (_db.select(_db.chapters)..where(
                (c) =>
                    c.bookId.equals(bookId) &
                    c.chapterIndex.equals(chapterIndex),
              ))
              .getSingleOrNull();
      return row == null ? null : chapterFromRow(row);
    });
  }

  @override
  Future<void> replaceChapters(String bookId, List<ChapterMeta> chapters) {
    return guardDbCall('replaceChapters', () async {
      await _db.transaction(() async {
        await (_db.delete(
          _db.chapters,
        )..where((c) => c.bookId.equals(bookId))).go();
        if (chapters.isEmpty) {
          return;
        }
        await _db.batch((b) {
          b.insertAll(
            _db.chapters,
            chapters
                .map((chapter) => chapterToCompanion(bookId, chapter))
                .toList(growable: false),
          );
        });
      });
    });
  }

  @override
  Future<void> markChapterCached(
    String bookId,
    int chapterIndex,
    String cacheKey, {
    int? wordCount,
  }) {
    return guardDbCall('markChapterCached', () async {
      await (_db.update(_db.chapters)..where(
            (c) =>
                c.bookId.equals(bookId) & c.chapterIndex.equals(chapterIndex),
          ))
          .write(
            ChaptersCompanion(
              isCached: const Value(true),
              cacheKey: Value(cacheKey),
              wordCount: wordCount != null
                  ? Value(wordCount)
                  : const Value.absent(),
              updatedAt: Value(toEpochMs(DateTime.now())),
            ),
          );
    });
  }

  @override
  Future<ReadingProgress?> getProgress(String bookId) {
    return guardDbCall('getProgress', () async {
      final row = await (_db.select(
        _db.readingProgressRecords,
      )..where((p) => p.bookId.equals(bookId))).getSingleOrNull();
      return row == null ? null : readingProgressFromRow(row);
    });
  }

  @override
  Future<void> saveProgress(ReadingProgress progress) {
    return guardDbCall('saveProgress', () async {
      await _db
          .into(_db.readingProgressRecords)
          .insertOnConflictUpdate(readingProgressToCompanion(progress));
    });
  }

  @override
  Future<List<Bookmark>> listBookmarks(String bookId) {
    return guardDbCall('listBookmarks', () async {
      final rows =
          await (_db.select(_db.bookmarks)
                ..where((b) => b.bookId.equals(bookId))
                ..orderBy([
                  (b) => OrderingTerm.asc(b.chapterIndex),
                  (b) => OrderingTerm.asc(b.charOffset),
                  (b) => OrderingTerm.asc(b.createdAt),
                ]))
              .get();
      return rows.map(bookmarkFromRow).toList(growable: false);
    });
  }

  @override
  Future<void> saveBookmark(Bookmark bookmark) {
    return guardDbCall('saveBookmark', () async {
      await _db
          .into(_db.bookmarks)
          .insertOnConflictUpdate(bookmarkToCompanion(bookmark));
    });
  }

  @override
  Future<void> deleteBookmark(String bookmarkId) {
    return guardDbCall('deleteBookmark', () async {
      await (_db.delete(
        _db.bookmarks,
      )..where((b) => b.id.equals(bookmarkId))).go();
    });
  }
}
