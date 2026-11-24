import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';

import '../application/core_providers.dart';
import '../domain/domain.dart';
import '../engine/reader_engine/reader_engine.dart';
import '../engine/source_engine/local_txt/local_txt.dart';
import '../engine/source_engine/sanitizer/sanitizer.dart';
import '../infrastructure/database/database.dart';
import '../infrastructure/platform/platform_bridge.dart';
import '../infrastructure/storage/storage.dart';

/// Viewport width breakpoint separating mobile bottom-tab layout from desktop
/// side-rail layout.
const double kDesktopLayoutBreakpoint = 720.0;

/// Application metadata exposed to the presentation layer.
final appTitleProvider = Provider<String>((ref) => 'PureRead');

/// Long-lived runtime services owning the SQLite database, storage resolver,
/// background TXT isolate worker, and font storage service.
class PureReadRuntime {
  PureReadRuntime({
    required this.pathResolver,
    required this.database,
    required this.txtIsolateWorker,
    required this.localTxtProvider,
    required this.fontStorageService,
  });

  final AppPathResolver pathResolver;
  final AppDatabase database;
  final TxtIsolateWorker txtIsolateWorker;
  final LocalTxtProvider localTxtProvider;
  final FontStorageService fontStorageService;

  Future<void>? _disposeFuture;

  /// Whether [dispose] has already been initiated.
  bool get isDisposed => _disposeFuture != null;

  /// Idempotently releases the TXT provider/isolate worker and closes the
  /// SQLite database.
  Future<void> dispose() {
    return _disposeFuture ??= _disposeInternal();
  }

  Future<void> _disposeInternal() async {
    await localTxtProvider.dispose();
    await txtIsolateWorker.dispose();
    await database.close();
  }
}

/// Resolves application directories, opens the SQLite database with backup
/// protection, and initializes production TXT and font services.
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

  try {
    // Trigger initial database opening, PRAGMA setup, and seed population
    // while mapping any SQLite startup failures into AppFailure.
    await DriftBookRepository(database).listGroups();
  } catch (error, stackTrace) {
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

/// Builds production Riverpod [Override]s connecting the presentation and
/// application layers to Drift repositories, [IncrementalTextPaginator],
/// [ContentSanitizerImpl], [LocalTxtProvider], and [FontStorageService].
List<Override> buildPureReadOverrides({
  required AppDatabase database,
  required AppPathResolver pathResolver,
  LocalTxtProvider? localTxtProvider,
  FontStorageService? fontStorageService,
  PlatformBridge? platformBridge,
}) {
  final ownsTxtProvider = localTxtProvider == null;
  final txtProvider = localTxtProvider ?? LocalTxtProvider();
  final fontStorage = fontStorageService ?? FontStorageService(pathResolver);
  final fontGateway = _FontStorageGatewayAdapter(fontStorage);

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
    if (platformBridge != null)
      platformBridgeProvider.overrideWithValue(platformBridge),
  ];
}
