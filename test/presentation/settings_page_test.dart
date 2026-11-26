import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pureread/application/backup/backup.dart';
import 'package:pureread/application/core_providers.dart';
import 'package:pureread/application/reader/reader_theme_x.dart';
import 'package:pureread/domain/domain.dart';
import 'package:pureread/infrastructure/platform/platform_bridge.dart';
import 'package:pureread/presentation/settings/settings_page.dart';

class _FakeBackupRepository implements BackupRepository {
  BackupManifest? manifestToReturn;
  Object? inspectError;
  Object? exportError;
  Object? restoreError;
  List<String> snapshots = <String>[];

  String? lastExportPath;
  bool? lastIncludeFonts;
  String? lastRestoredPath;
  BackupRestoreMode? lastRestoredMode;

  @override
  Future<BackupManifest> inspectBackup(String archivePath) async {
    if (inspectError != null) throw inspectError!;
    return manifestToReturn ??
        BackupManifest(
          formatVersion: 1,
          appVersion: '1.0.0+1',
          schemaVersion: 1,
          exportedAt: DateTime.utc(2026, 11, 24, 19, 10),
          recordCounts: const <String, int>{
            'book_groups': 1,
            'books': 3,
            'reading_progress': 2,
            'bookmarks': 4,
            'book_sources': 5,
            'replace_rules': 2,
            'reader_themes': 4,
            'app_settings': 3,
            'fonts': 1,
          },
        );
  }

  @override
  Future<String> exportBackup(
    String targetArchivePath, {
    bool includeCustomFonts = true,
  }) async {
    if (exportError != null) throw exportError!;
    lastExportPath = targetArchivePath;
    lastIncludeFonts = includeCustomFonts;
    return targetArchivePath;
  }

  @override
  Future<void> restoreBackup(
    String archivePath, {
    BackupRestoreMode mode = BackupRestoreMode.merge,
  }) async {
    if (restoreError != null) throw restoreError!;
    lastRestoredPath = archivePath;
    lastRestoredMode = mode;
    snapshots = <String>[
      r'D:\data\db\backups\pureread_v1_20261124_191500_000.db',
      ...snapshots,
    ];
  }

  @override
  Future<List<String>> listDatabaseSnapshots() async => snapshots;
}

class _FakeCacheGateway implements CacheManagementGateway {
  CacheStats stats;
  int clearCalls = 0;

  _FakeCacheGateway({
    this.stats = const CacheStats(chapterCacheBytes: 2048, cachedFileCount: 3),
  });

  @override
  Future<CacheStats> getCacheStats() async => stats;

  @override
  Future<int> clearChapterCache() async {
    clearCalls++;
    final freed = stats.totalBytes;
    stats = const CacheStats(chapterCacheBytes: 0, cachedFileCount: 0);
    return freed;
  }
}

class _FakePlatformBridge implements PlatformBridge {
  List<String> filesToPick = const <String>[];
  List<String> lastExtensions = const <String>[];

  @override
  Future<List<String>> pickFiles({
    required List<String> extensions,
    bool allowMultiple = false,
  }) async {
    lastExtensions = extensions;
    return filesToPick;
  }

  @override
  Future<void> setKeepScreenOn(bool enabled) async {}

  @override
  Future<void> setVolumeKeyPaging(bool enabled) async {}

  @override
  Stream<VolumeKeyDirection> get volumeKeyEvents =>
      const Stream<VolumeKeyDirection>.empty();

  @override
  Future<void> setImmersiveMode(bool enabled) async {}

  @override
  Future<void> bossKeyHide() async {}
}

class _FakeThemeRepository implements ThemeRepository {
  final Map<String, ReaderTheme> themes = <String, ReaderTheme>{
    for (final t in buildDefaultReaderThemes()) t.id: t,
  };
  final Map<String, AppSetting> settings = <String, AppSetting>{};

  @override
  Stream<List<ReaderTheme>> watchThemes() =>
      Stream<List<ReaderTheme>>.value(themes.values.toList(growable: false));

  @override
  Future<List<ReaderTheme>> listThemes() async =>
      themes.values.toList(growable: false);

  @override
  Future<ReaderTheme?> getThemeById(String themeId) async => themes[themeId];

  @override
  Future<void> saveTheme(ReaderTheme theme) async => themes[theme.id] = theme;

  @override
  Future<void> deleteTheme(String themeId) async => themes.remove(themeId);

  @override
  Future<AppSetting?> getSetting(String key) async => settings[key];

  @override
  Future<List<AppSetting>> listSettings() async =>
      settings.values.toList(growable: false);

  @override
  Future<void> saveSetting(AppSetting setting) async =>
      settings[setting.key] = setting;
}

class _FakeFontLoaderGateway implements FontLoaderGateway {
  int importCalls = 0;

  @override
  Future<({String fontFamily, String relativeFontPath})> importAndRegisterFont(
    String sourcePath,
  ) async {
    importCalls++;
    return (
      fontFamily: 'pureread_custom_font',
      relativeFontPath: 'fonts/custom_font.ttf',
    );
  }

  @override
  Future<void> ensureFontLoaded(
    String fontFamily,
    String? relativeFontPath,
  ) async {}
}

void main() {
  group('BackupController', () {
    test('exports, picks & inspects, restores, clears cache, and updates themes/fonts', () async {
      final backupRepo = _FakeBackupRepository()
        ..snapshots = <String>[
          r'D:\data\db\backups\pureread_v1_20261124_180000_000.db',
        ];
      final cacheGateway = _FakeCacheGateway(
        stats: const CacheStats(
          chapterCacheBytes: 1024 * 1024,
          cachedFileCount: 12,
        ),
      );
      final platform = _FakePlatformBridge();
      final themeRepo = _FakeThemeRepository();
      final fontGateway = _FakeFontLoaderGateway();

      final container = ProviderContainer(
        overrides: [
          backupRepositoryProvider.overrideWithValue(backupRepo),
          cacheManagementGatewayProvider.overrideWithValue(cacheGateway),
          backupExportPathResolverProvider.overrideWithValue(
            (ts) async => r'D:\backups\auto.pureread.zip',
          ),
          platformBridgeProvider.overrideWithValue(platform),
          themeRepositoryProvider.overrideWithValue(themeRepo),
          fontLoaderGatewayProvider.overrideWithValue(fontGateway),
        ],
      );
      addTearDown(container.dispose);

      container.read(backupControllerProvider);
      await Future<void>.delayed(const Duration(milliseconds: 20));

      var state = container.read(backupControllerProvider);
      expect(state.isLoading, isFalse);
      expect(state.databaseSnapshots, hasLength(1));
      expect(state.cacheStats.cachedFileCount, 12);

      // Export with includeCustomFonts toggled false
      final controller = container.read(backupControllerProvider.notifier);
      controller.setIncludeCustomFonts(false);
      final exported = await controller.exportBackup();
      expect(exported, r'D:\backups\auto.pureread.zip');
      expect(backupRepo.lastIncludeFonts, isFalse);

      // Pick & inspect backup
      platform.filesToPick = const <String>[r'D:\backups\picked.pureread.zip'];
      final manifest = await controller.pickAndInspectBackup();
      expect(manifest, isNotNull);
      expect(platform.lastExtensions, ['zip']);
      expect(
        container.read(backupControllerProvider).inspectedArchivePath,
        r'D:\backups\picked.pureread.zip',
      );

      // Merge restore generates updated snapshot list
      final restoredOk = await controller.restoreBackup(
        mode: BackupRestoreMode.merge,
      );
      expect(restoredOk, isTrue);
      expect(backupRepo.lastRestoredMode, BackupRestoreMode.merge);
      state = container.read(backupControllerProvider);
      expect(state.inspectedManifest, isNull);
      expect(state.databaseSnapshots, hasLength(2));

      // Clear chapter cache
      final freed = await controller.clearChapterCache();
      expect(freed, 1024 * 1024);
      expect(cacheGateway.clearCalls, 1);
      expect(
        container.read(backupControllerProvider).cacheStats.totalBytes,
        0,
      );

      // Theme & custom font switching
      await controller.selectTheme('slate_night');
      expect(themeRepo.settings['active_theme_id']?.value, 'slate_night');

      platform.filesToPick = const <String>[r'D:\fonts\wenkai.ttf'];
      await controller.importCustomFont();
      expect(fontGateway.importCalls, 1);
      expect(
        container.read(backupControllerProvider).activeTheme?.fontFamily,
        'pureread_custom_font',
      );

      await controller.resetCustomFont();
      expect(
        container.read(backupControllerProvider).activeTheme?.fontFamily,
        'system',
      );
    });
  });

  group('SettingsPage', () {
    testWidgets(
      'renders cleanly under default ProviderScope with .pureread.zip disclaimer, theme/font, and MIT About',
      (tester) async {
        tester.view.devicePixelRatio = 1.0;
        tester.view.physicalSize = const Size(400, 800);
        addTearDown(tester.view.reset);

        await tester.pumpWidget(
          const ProviderScope(child: MaterialApp(home: SettingsPage())),
        );
        await tester.pumpAndSettle();

        expect(find.textContaining('.pureread.zip'), findsOneWidget);
        expect(find.textContaining('不包含：在线章节正文缓存'), findsOneWidget);
        expect(find.text('MIT License'), findsOneWidget);
        expect(find.textContaining('零遥测'), findsOneWidget);
        expect(find.text('米白护眼'), findsOneWidget);
      },
    );

    testWidgets(
      'desktop viewport renders two-column layout, snapshots, cache clear, export, and inspect-then-restore dialog',
      (tester) async {
        tester.view.devicePixelRatio = 1.0;
        tester.view.physicalSize = const Size(1280, 720);
        addTearDown(tester.view.reset);

        final backupRepo = _FakeBackupRepository()
          ..snapshots = <String>[
            r'D:\data\db\backups\pureread_v1_20261124_180000_000.db',
          ];
        final cacheGateway = _FakeCacheGateway(
          stats: const CacheStats(
            chapterCacheBytes: 2 * 1024 * 1024,
            cachedFileCount: 8,
          ),
        );
        final platform = _FakePlatformBridge()
          ..filesToPick = const <String>[r'D:\backups\restore_me.pureread.zip'];
        final themeRepo = _FakeThemeRepository();
        final fontGateway = _FakeFontLoaderGateway();

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              backupRepositoryProvider.overrideWithValue(backupRepo),
              cacheManagementGatewayProvider.overrideWithValue(cacheGateway),
              backupExportPathResolverProvider.overrideWithValue(
                (ts) async => r'D:\backups\exported.pureread.zip',
              ),
              platformBridgeProvider.overrideWithValue(platform),
              themeRepositoryProvider.overrideWithValue(themeRepo),
              fontLoaderGatewayProvider.overrideWithValue(fontGateway),
            ],
            child: const MaterialApp(home: SettingsPage()),
          ),
        );
        await tester.pumpAndSettle();

        expect(
          find.text('pureread_v1_20261124_180000_000.db'),
          findsOneWidget,
        );
        expect(find.text('最新'), findsOneWidget);
        expect(find.text('2.00 MB'), findsOneWidget);
        expect(find.text('已缓存 8 个在线章节文件'), findsOneWidget);

        // Clear cache
        await tester.tap(find.text('清理章节缓存'));
        await tester.pumpAndSettle();
        expect(cacheGateway.clearCalls, 1);
        expect(find.text('0 B'), findsOneWidget);

        // Export backup
        await tester.tap(find.text('导出备份'));
        await tester.pumpAndSettle();
        expect(backupRepo.lastExportPath, r'D:\backups\exported.pureread.zip');
        expect(find.textContaining('已成功导出整库备份'), findsOneWidget);

        // Pick & inspect -> restore confirmation dialog -> overwrite restore
        await tester.tap(find.text('导入并校验'));
        await tester.pumpAndSettle();
        expect(find.text('备份包校验通过'), findsOneWidget);
        expect(find.text('书籍: 3'), findsOneWidget);
        expect(find.text('合并恢复'), findsOneWidget);
        expect(find.text('覆盖恢复'), findsOneWidget);

        await tester.tap(find.text('覆盖恢复'));
        await tester.pumpAndSettle();
        expect(backupRepo.lastRestoredPath, r'D:\backups\restore_me.pureread.zip');
        expect(backupRepo.lastRestoredMode, BackupRestoreMode.overwrite);
        expect(find.textContaining('已按覆盖模式恢复整库备份'), findsOneWidget);
      },
    );

    testWidgets(
      'displays FileAccessFailure banner without opening dialog when inspected archive is corrupt',
      (tester) async {
        final backupRepo = _FakeBackupRepository()
          ..inspectError = const FileAccessFailure(
            message: '备份压缩包损坏或格式无效',
            filePath: r'D:\backups\corrupt.pureread.zip',
          );
        final platform = _FakePlatformBridge()
          ..filesToPick = const <String>[r'D:\backups\corrupt.pureread.zip'];

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              backupRepositoryProvider.overrideWithValue(backupRepo),
              cacheManagementGatewayProvider.overrideWithValue(
                _FakeCacheGateway(),
              ),
              platformBridgeProvider.overrideWithValue(platform),
              themeRepositoryProvider.overrideWithValue(_FakeThemeRepository()),
              fontLoaderGatewayProvider.overrideWithValue(
                _FakeFontLoaderGateway(),
              ),
            ],
            child: const MaterialApp(home: SettingsPage()),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.text('导入并校验'));
        await tester.pumpAndSettle();

        expect(find.text('备份包校验通过'), findsNothing);
        expect(find.text('备份压缩包损坏或格式无效'), findsOneWidget);
      },
    );

    testWidgets(
      'supports merge restore, theme switching, and custom font import/reset',
      (tester) async {
        tester.view.devicePixelRatio = 1.0;
        tester.view.physicalSize = const Size(1280, 720);
        addTearDown(tester.view.reset);

        final backupRepo = _FakeBackupRepository();
        final platform = _FakePlatformBridge()
          ..filesToPick = const <String>[r'D:\backups\merge_me.pureread.zip'];
        final themeRepo = _FakeThemeRepository();
        final fontGateway = _FakeFontLoaderGateway();

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              backupRepositoryProvider.overrideWithValue(backupRepo),
              cacheManagementGatewayProvider.overrideWithValue(
                _FakeCacheGateway(),
              ),
              platformBridgeProvider.overrideWithValue(platform),
              themeRepositoryProvider.overrideWithValue(themeRepo),
              fontLoaderGatewayProvider.overrideWithValue(fontGateway),
            ],
            child: const MaterialApp(home: SettingsPage()),
          ),
        );
        await tester.pumpAndSettle();

        // Merge restore path
        await tester.tap(find.text('导入并校验'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('合并恢复'));
        await tester.pumpAndSettle();
        expect(backupRepo.lastRestoredMode, BackupRestoreMode.merge);
        expect(find.textContaining('已按合并模式恢复整库备份'), findsOneWidget);

        // Switch theme chip
        await tester.tap(find.text('静谧暗灰'));
        await tester.pumpAndSettle();
        expect(themeRepo.settings['active_theme_id']?.value, 'slate_night');
        expect(find.text('当前主题：静谧暗灰'), findsOneWidget);

        // Import & reset custom font
        platform.filesToPick = const <String>[r'D:\fonts\custom.otf'];
        await tester.tap(find.text('导入字体'));
        await tester.pumpAndSettle();
        expect(fontGateway.importCalls, 1);
        expect(find.text('当前字体：pureread_custom_font'), findsOneWidget);

        await tester.tap(find.text('恢复默认'));
        await tester.pumpAndSettle();
        expect(find.text('当前字体：系统默认字体'), findsOneWidget);
      },
    );
  });
}
