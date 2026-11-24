import 'dart:async';

import 'package:drift/drift.dart' show Value;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:path/path.dart' as p;

import '../application/backup/backup_providers.dart';
import '../application/core_providers.dart';
import '../application/m2_providers.dart';
import '../domain/domain.dart';
import '../engine/reader_engine/reader_engine.dart';
import '../engine/source_engine/local_txt/local_txt.dart';
import '../engine/source_engine/sanitizer/sanitizer.dart';
import '../engine/source_engine/source_registry.dart';
import '../infrastructure/database/database.dart';
import '../infrastructure/database/drift_backup_repository.dart';
import '../infrastructure/network/source_http_client.dart';
import '../infrastructure/platform/platform_bridge.dart';
import '../infrastructure/storage/chapter_cache_store.dart';
import '../infrastructure/storage/storage.dart';

/// Viewport width breakpoint separating mobile bottom-tab layout from desktop
/// side-rail layout.
const double kDesktopLayoutBreakpoint = 720.0;

/// Application metadata exposed to the presentation layer.
final appTitleProvider = Provider<String>((ref) => 'PureRead');

/// Long-lived runtime services owning the SQLite database, storage resolver,
/// background TXT isolate worker, font storage service, online HTTP client,
/// chapter cache store, source engine registry, and backup repository.
class PureReadRuntime {
  factory PureReadRuntime({
    required AppPathResolver pathResolver,
    required AppDatabase database,
    required TxtIsolateWorker txtIsolateWorker,
    required LocalTxtProvider localTxtProvider,
    required FontStorageService fontStorageService,
    SourceHttpClient? sourceHttpClient,
    ChapterCacheStore? chapterCacheStore,
    BookProviderFactory? bookProviderFactory,
    SourceImportExportService? sourceImportExportService,
    DriftBackupRepository? backupRepository,
  }) {
    final resolvedHttpClient = sourceHttpClient ?? SourceHttpClient();
    return PureReadRuntime._(
      pathResolver: pathResolver,
      database: database,
      txtIsolateWorker: txtIsolateWorker,
      localTxtProvider: localTxtProvider,
      fontStorageService: fontStorageService,
      sourceHttpClient: resolvedHttpClient,
      chapterCacheStore: chapterCacheStore ?? ChapterCacheStore(pathResolver),
      bookProviderFactory:
          bookProviderFactory ??
          BookProviderFactory(httpClient: resolvedHttpClient),
      sourceImportExportService:
          sourceImportExportService ?? const SourceImportExportService(),
      backupRepository:
          backupRepository ?? DriftBackupRepository(database, pathResolver),
    );
  }

  PureReadRuntime._({
    required this.pathResolver,
    required this.database,
    required this.txtIsolateWorker,
    required this.localTxtProvider,
    required this.fontStorageService,
    required this.sourceHttpClient,
    required this.chapterCacheStore,
    required this.bookProviderFactory,
    required this.sourceImportExportService,
    required this.backupRepository,
  });

  final AppPathResolver pathResolver;
  final AppDatabase database;
  final TxtIsolateWorker txtIsolateWorker;
  final LocalTxtProvider localTxtProvider;
  final FontStorageService fontStorageService;
  final SourceHttpClient sourceHttpClient;
  final ChapterCacheStore chapterCacheStore;
  final BookProviderFactory bookProviderFactory;
  final SourceImportExportService sourceImportExportService;
  final DriftBackupRepository backupRepository;

  Future<void>? _disposeFuture;

  /// Whether [dispose] has already been initiated.
  bool get isDisposed => _disposeFuture != null;

  /// Idempotently closes the HTTP client, releases the TXT provider/isolate
  /// worker, and closes the SQLite database.
  Future<void> dispose() {
    return _disposeFuture ??= _disposeInternal();
  }

  Future<void> _disposeInternal() async {
    sourceHttpClient.close();
    await localTxtProvider.dispose();
    await txtIsolateWorker.dispose();
    await database.close();
  }
}

/// Resolves application directories, opens the SQLite database with backup
/// protection, and initializes production M1/M2 runtime services.
Future<PureReadRuntime> bootstrapPureReadRuntime({
  AppPathResolver? pathResolver,
  bool useBackgroundDatabaseIsolate = true,
}) async {
  final resolver = pathResolver ?? await AppPathResolver.resolve();
  final database = AppDatabase.forFile(
    resolver.databaseFile,
    backupsDirPath: resolver.dbBackupsDir.path,
    useBackgroundIsolate: useBackgroundDatabaseIsolate,
  );
  final txtWorker = TxtIsolateWorker();
  final txtProvider = LocalTxtProvider(worker: txtWorker);
  final fontStorage = FontStorageService(resolver);
  final sourceHttpClient = SourceHttpClient();
  final chapterCacheStore = ChapterCacheStore(resolver);
  final bookProviderFactory = BookProviderFactory(httpClient: sourceHttpClient);
  const sourceImportExportService = SourceImportExportService();
  final backupRepository = DriftBackupRepository(database, resolver);

  try {
    // Trigger initial database opening, PRAGMA setup, and seed population
    // while mapping any SQLite startup failures into AppFailure.
    await DriftBookRepository(database).listGroups();
  } catch (error, stackTrace) {
    sourceHttpClient.close();
    await txtProvider.dispose();
    await txtWorker.dispose();
    await database.close();
    if (error is AppFailure) rethrow;
    throw DatabaseFailure(
      message: 'Failed to initialize PureRead database: $error',
      cause: error,
      stackTrace: stackTrace,
    );
  }

  return PureReadRuntime(
    pathResolver: resolver,
    database: database,
    txtIsolateWorker: txtWorker,
    localTxtProvider: txtProvider,
    fontStorageService: fontStorage,
    sourceHttpClient: sourceHttpClient,
    chapterCacheStore: chapterCacheStore,
    bookProviderFactory: bookProviderFactory,
    sourceImportExportService: sourceImportExportService,
    backupRepository: backupRepository,
  );
}

class _FontStorageGatewayAdapter implements FontLoaderGateway {
  const _FontStorageGatewayAdapter(this._storage);

  final FontStorageService _storage;

  @override
  Future<({String fontFamily, String relativeFontPath})> importAndRegisterFont(
    String sourcePath,
  ) {
    return _storage.importAndRegisterFont(sourcePath);
  }

  @override
  Future<void> ensureFontLoaded(
    String fontFamily,
    String? relativeFontPath,
  ) {
    return _storage.ensureFontLoaded(fontFamily, relativeFontPath);
  }
}

class _BookProviderFactoryGatewayAdapter implements BookProviderFactoryGateway {
  const _BookProviderFactoryGatewayAdapter(this._factory);

  final BookProviderFactory _factory;

  @override
  BookProvider createProvider(BookSource source) =>
      _factory.createProvider(source);
}

class _SourceImportExportGatewayAdapter implements SourceImportExportGateway {
  const _SourceImportExportGatewayAdapter(this._service);

  final SourceImportExportService _service;

  @override
  Future<SourceImportResult> parseImportText(
    String rawText, {
    String? fileName,
  }) async {
    final batch = await _service.importFromText(rawText, fileName: fileName);
    return _mapBatch(batch);
  }

  @override
  Future<SourceImportResult> parseImportFile(String filePath) async {
    final batch = await _service.importFromFile(filePath);
    return _mapBatch(batch);
  }

  @override
  Future<String> exportSources(List<BookSource> sources) async =>
      _service.exportSources(sources);

  static SourceImportResult _mapBatch(SourceImportBatch batch) {
    return SourceImportResult(
      sources: batch.sources,
      skippedNonTextCount: batch.skippedNonTextCount,
      invalidCount: batch.invalidCount,
      messages: batch.messages,
    );
  }
}

class _ChapterCacheGatewayAdapter implements ChapterCacheGateway {
  const _ChapterCacheGatewayAdapter(this._store, this._pathResolver);

  final ChapterCacheStore _store;
  final AppPathResolver _pathResolver;

  @override
  String buildCacheKey(String bookId, int chapterIndex) =>
      _pathResolver.chapterCacheKey(bookId, chapterIndex);

  @override
  Future<String?> readChapterText(String bookId, int chapterIndex) =>
      _store.readChapter(bookId, chapterIndex);

  @override
  Future<String> writeChapterText(
    String bookId,
    int chapterIndex,
    String rawText,
  ) => _store.writeChapter(bookId, chapterIndex, rawText);

  @override
  Future<void> deleteBookCache(String bookId) => _store.deleteBookCache(bookId);

  @override
  Future<int> getTotalCacheBytes() => _store.getTotalCacheBytes();

  @override
  Future<void> clearAllCache() async {
    await _store.clearAllCache();
  }
}

/// Builds production Riverpod [Override]s connecting the presentation and
/// application layers to Drift repositories, [IncrementalTextPaginator],
/// [ContentSanitizerImpl], [LocalTxtProvider], [FontStorageService], and M2
/// online/backup gateways.
List<Override> buildPureReadOverrides({
  required AppDatabase database,
  required AppPathResolver pathResolver,
  LocalTxtProvider? localTxtProvider,
  FontStorageService? fontStorageService,
  PlatformBridge? platformBridge,
  SourceHttpClient? sourceHttpClient,
  ChapterCacheStore? chapterCacheStore,
  BookProviderFactory? bookProviderFactory,
  SourceImportExportService? sourceImportExportService,
  DriftBackupRepository? backupRepository,
}) {
  final ownsTxtProvider = localTxtProvider == null;
  final txtProvider = localTxtProvider ?? LocalTxtProvider();
  final fontStorage = fontStorageService ?? FontStorageService(pathResolver);
  final fontGateway = _FontStorageGatewayAdapter(fontStorage);
  final cacheStore = chapterCacheStore ?? ChapterCacheStore(pathResolver);
  final importExportService =
      sourceImportExportService ?? const SourceImportExportService();
  final backupRepo =
      backupRepository ?? DriftBackupRepository(database, pathResolver);

  return <Override>[
    bookRepositoryProvider.overrideWithValue(DriftBookRepository(database)),
    themeRepositoryProvider.overrideWithValue(DriftThemeRepository(database)),
    sourceRepositoryProvider.overrideWithValue(DriftSourceRepository(database)),
    readerPaginatorProvider.overrideWith((ref) => IncrementalTextPaginator()),
    contentSanitizerProvider.overrideWith(
      (ref) => ContentSanitizerImpl(
        sourceRepository: ref.watch(sourceRepositoryProvider),
      ),
    ),
    txtBookImporterProvider.overrideWith((ref) {
      if (ownsTxtProvider) {
        ref.onDispose(() {
          unawaited(txtProvider.dispose());
        });
      }
      return txtProvider.importTxtFile;
    }),
    localTxtChapterReaderProvider.overrideWith((ref) {
      if (ownsTxtProvider) {
        ref.onDispose(() {
          unawaited(txtProvider.dispose());
        });
      }
      return (Book book, ChapterMeta chapter) async {
        final path = book.localFilePath;
        if (path == null || path.trim().isEmpty) {
          throw FileAccessFailure(
            message: '本地书籍《${book.title}》缺少本地文件路径',
            filePath: path,
          );
        }
        final rawEncoding = book.fileEncoding;
        final encoding = (rawEncoding != null && rawEncoding.trim().isNotEmpty)
            ? rawEncoding
            : 'utf-8';
        return txtProvider.readChapterText(
          filePath: path,
          encoding: encoding,
          chapter: chapter,
        );
      };
    }),
    fontLoaderGatewayProvider.overrideWithValue(fontGateway),
    bookProviderFactoryProvider.overrideWith((ref) {
      final ownsHttpClient =
          sourceHttpClient == null && bookProviderFactory == null;
      final client = sourceHttpClient ?? SourceHttpClient();
      if (ownsHttpClient) {
        ref.onDispose(client.close);
      }
      final factory =
          bookProviderFactory ?? BookProviderFactory(httpClient: client);
      return _BookProviderFactoryGatewayAdapter(factory);
    }),
    sourceImportExportGatewayProvider.overrideWithValue(
      _SourceImportExportGatewayAdapter(importExportService),
    ),
    chapterCacheGatewayProvider.overrideWithValue(
      _ChapterCacheGatewayAdapter(cacheStore, pathResolver),
    ),
    backupRepositoryProvider.overrideWithValue(backupRepo),
    cacheManagementGatewayProvider.overrideWithValue(
      DirectoryCacheManagementGateway(
        chaptersCacheDir: pathResolver.chaptersCacheDir,
        tmpCacheDir: pathResolver.tmpCacheDir,
        onChapterCacheCleared: () async {
          await database
              .update(database.chapters)
              .write(
                const ChaptersCompanion(
                  isCached: Value(false),
                  cacheKey: Value(null),
                ),
              );
        },
      ),
    ),
    backupExportPathResolverProvider.overrideWithValue(
      (ts) async => p.join(
        pathResolver.dataRootDir.path,
        'exports',
        formatBackupArchiveFileName(ts),
      ),
    ),
    if (platformBridge != null)
      platformBridgeProvider.overrideWithValue(platformBridge),
  ];
}
