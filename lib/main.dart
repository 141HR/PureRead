import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/app.dart';
import 'app/providers.dart';
import 'domain/domain.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await _launchPureReadApp();
}

Future<void> _launchPureReadApp() async {
  try {
    final runtime = await bootstrapPureReadRuntime();
    WidgetsBinding.instance.addObserver(_RuntimeLifecycleObserver(runtime));
    runApp(
      ProviderScope(
        overrides: buildPureReadOverrides(
          database: runtime.database,
          pathResolver: runtime.pathResolver,
          localTxtProvider: runtime.localTxtProvider,
          fontStorageService: runtime.fontStorageService,
          sourceHttpClient: runtime.sourceHttpClient,
          chapterCacheStore: runtime.chapterCacheStore,
          bookProviderFactory: runtime.bookProviderFactory,
          sourceImportExportService: runtime.sourceImportExportService,
          backupRepository: runtime.backupRepository,
        ),
        child: const PureReadApp(),
      ),
    );
  } on AppFailure catch (failure) {
    runApp(
      _BootstrapErrorApp(
        failure: failure,
        onRetry: _launchPureReadApp,
      ),
    );
  } catch (error, stackTrace) {
    runApp(
      _BootstrapErrorApp(
        failure: FileAccessFailure(
          message: '应用启动初始化失败：$error',
          cause: error,
          stackTrace: stackTrace,
        ),
        onRetry: _launchPureReadApp,
      ),
    );
  }
}

class _RuntimeLifecycleObserver with WidgetsBindingObserver {
  _RuntimeLifecycleObserver(this.runtime);

  final PureReadRuntime runtime;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.detached) {
      WidgetsBinding.instance.removeObserver(this);
      unawaited(runtime.dispose());
    }
  }
}

class _BootstrapErrorApp extends StatelessWidget {
  const _BootstrapErrorApp({
    required this.failure,
    required this.onRetry,
  });

  final AppFailure failure;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    const seedColor = Color(0xFF4A6B53);
    final detail = switch (failure) {
      DatabaseFailure(:final backupSnapshotPath)
          when backupSnapshotPath != null && backupSnapshotPath.isNotEmpty =>
        '备份快照：$backupSnapshotPath',
      FileAccessFailure(:final filePath)
          when filePath != null && filePath.isNotEmpty =>
        '路径：$filePath',
      _ => null,
    };

    return MaterialApp(
      title: 'PureRead',
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.system,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: seedColor,
          brightness: Brightness.light,
        ),
        scaffoldBackgroundColor: const Color(0xFFF7F4EC),
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: seedColor,
          brightness: Brightness.dark,
        ),
      ),
      home: Scaffold(
        body: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.error_outline, size: 48),
                  const SizedBox(height: 16),
                  const Text(
                    'PureRead 启动失败',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    failure.message,
                    textAlign: TextAlign.center,
                  ),
                  if (detail != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      detail,
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 12),
                    ),
                  ],
                  const SizedBox(height: 20),
                  FilledButton.icon(
                    onPressed: () {
                      unawaited(onRetry());
                    },
                    icon: const Icon(Icons.refresh),
                    label: const Text('重试启动'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
