import '../entities/book.dart';
import '../entities/book_group.dart';
import '../entities/bookmark.dart';
import '../entities/chapter.dart';
import '../entities/reading_progress.dart';

/// Repository contract for bookshelf books, groups, chapter indices, reading
/// progress, and bookmarks.
abstract interface class BookRepository {
  Stream<List<Book>> watchBooks({String? groupId});

  Future<List<Book>> listBooks({String? groupId});

  Future<Book?> getBookById(String bookId);

  Future<Book?> findBySourceAndUrl(String sourceId, String originBookUrl);

  Future<void> saveBook(Book book);

  Future<void> deleteBook(String bookId);

  Future<List<BookGroup>> listGroups();

  Future<void> saveGroup(BookGroup group);

  Future<void> deleteGroup(String groupId);

  Future<List<ChapterMeta>> listChapters(String bookId);

  Future<ChapterMeta?> getChapter(String bookId, int chapterIndex);

  Future<void> replaceChapters(String bookId, List<ChapterMeta> chapters);

  Future<void> markChapterCached(
    String bookId,
    int chapterIndex,
    String cacheKey, {
    int? wordCount,
  });

  Future<ReadingProgress?> getProgress(String bookId);

  Future<void> saveProgress(ReadingProgress progress);

  Future<List<Bookmark>> listBookmarks(String bookId);

  Future<void> saveBookmark(Bookmark bookmark);

  Future<void> deleteBookmark(String bookmarkId);
}
