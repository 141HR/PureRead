import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import '../../../domain/failures/app_failure.dart';
import 'txt_chapter_scanner.dart';
import 'txt_codec.dart';
import 'txt_encoding.dart';

/// Reusable long-lived background [Isolate] worker for TXT encoding detection,
/// streaming chapter scanning, file hashing, and `RandomAccessFile` chapter
/// slicing.
///
/// Keeping one worker alive avoids repeated `Isolate` spawn overhead and keeps
/// the 64K GBK lookup table cached in the worker isolate across book opens and
/// chapter turns. Call [dispose] when the owning provider/container shuts down.
class TxtIsolateWorker {
  TxtIsolateWorker();

  Isolate? _isolate;
  SendPort? _workerSendPort;
  Future<SendPort>? _startFuture;

  ReceivePort? _replyPort;
  ReceivePort? _errorPort;
  ReceivePort? _exitPort;

  StreamSubscription<Object?>? _replySub;
  StreamSubscription<Object?>? _errorSub;
  StreamSubscription<Object?>? _exitSub;

  final Map<int, Completer<Object?>> _pending = <int, Completer<Object?>>{};
  int _nextRequestId = 1;
  bool _disposed = false;

  bool get isDisposed => _disposed;
  bool get isRunning => _workerSendPort != null && !_disposed;

  /// Pre-warms the worker isolate and its 64K GBK lookup table.
  Future<void> warmUpGbkTable() async {
    await _dispatch<void>(const _WarmUpGbkTask());
  }

  /// Streams encoding detection on [filePath] in the background isolate.
  Future<EncodingDetectionResult> detectEncoding(
    String filePath, {
    int chunkSize = TxtEncodingDetector.defaultChunkSize,
    int maxSampleBytes = TxtEncodingDetector.defaultMaxSampleBytes,
  }) {
    return _dispatch<EncodingDetectionResult>(
      _DetectEncodingTask(
        filePath: filePath,
        chunkSize: chunkSize,
        maxSampleBytes: maxSampleBytes,
      ),
    );
  }

  /// Streams chapter scanning + encoding detection + fast hash on [filePath].
  Future<TxtScanResult> scanFile(
    String filePath, {
    TxtEncoding? forcedEncoding,
    String? customPattern,
    int chunkBytes = TxtChapterScanner.defaultChunkBytes,
    int maxCandidateLineBytes = TxtChapterScanner.defaultMaxCandidateLineBytes,
    int fallbackSegmentBytes = TxtChapterScanner.defaultFallbackSegmentBytes,
  }) {
    return _dispatch<TxtScanResult>(
      _ScanFileTask(
        filePath: filePath,
        forcedEncoding: forcedEncoding,
        customPattern: customPattern,
        chunkBytes: chunkBytes,
        maxCandidateLineBytes: maxCandidateLineBytes,
        fallbackSegmentBytes: fallbackSegmentBytes,
      ),
    );
  }

  /// Reads and decodes a single `[byteStart, byteEnd)` chapter slice via
  /// `RandomAccessFile` in the background isolate.
  Future<ChapterReadResult> readChapter({
    required String filePath,
    required int chapterIndex,
    required String title,
    required int byteStart,
    required int byteEnd,
    required TxtEncoding encoding,
    bool allowMalformed = false,
  }) {
    return _dispatch<ChapterReadResult>(
      _ReadChapterTask(
        filePath: filePath,
        chapterIndex: chapterIndex,
        title: title,
        byteStart: byteStart,
        byteEnd: byteEnd,
        encoding: encoding,
        allowMalformed: allowMalformed,
      ),
    );
  }

  /// Computes the fast head/tail/size fingerprint hash of [filePath] in the
  /// background isolate.
  Future<String> computeFastFileHash(String filePath) {
    return _dispatch<String>(_HashFileTask(filePath: filePath));
  }

  Future<T> _dispatch<T>(_WorkerTask task) async {
    if (_disposed) {
      throw StateError('TxtIsolateWorker has been disposed');
    }

    final workerPort = await _ensureStarted();
    if (_disposed) {
      throw StateError('TxtIsolateWorker has been disposed');
    }

    final id = _nextRequestId++;
    final completer = Completer<Object?>();
    _pending[id] = completer;

    workerPort.send(_WorkerRequest(id: id, task: task));

    final result = await completer.future;
    return result as T;
  }

  Future<SendPort> _ensureStarted() {
    final existingPort = _workerSendPort;
    if (existingPort != null) {
      return Future<SendPort>.value(existingPort);
    }
    final existingFuture = _startFuture;
    if (existingFuture != null) {
      return existingFuture;
    }

    final startFuture = _spawnWorker();
    _startFuture = startFuture;
    return startFuture;
  }

  Future<SendPort> _spawnWorker() async {
    final replyPort = ReceivePort();
    final errorPort = ReceivePort();
    final exitPort = ReceivePort();

    _replyPort = replyPort;
    _errorPort = errorPort;
    _exitPort = exitPort;

    final readyCompleter = Completer<SendPort>();

    _replySub = replyPort.listen((Object? message) {
      if (message is SendPort) {
        _workerSendPort = message;
        if (!readyCompleter.isCompleted) {
          readyCompleter.complete(message);
        }
        return;
      }
      if (message is _WorkerResponse) {
        final pending = _pending.remove(message.id);
        if (pending == null || pending.isCompleted) return;
        final error = message.error;
        if (error != null) {
          pending.completeError(
            error.toException(),
            StackTrace.fromString(error.stackTrace),
          );
        } else {
          pending.complete(message.value);
        }
      }
    });

    _errorSub = errorPort.listen((Object? err) {
      final failure = FileAccessFailure(
        message: 'TXT worker isolate error: $err',
        cause: err,
      );
      if (!readyCompleter.isCompleted) {
        readyCompleter.completeError(failure);
      }
      _failAllPending(failure);
    });

    _exitSub = exitPort.listen((Object? _) {
      if (!readyCompleter.isCompleted) {
        readyCompleter.completeError(
          const CancelledFailure(
            message: 'TXT worker isolate exited during startup',
          ),
        );
      }
      if (!_disposed) {
        _failAllPending(
          const CancelledFailure(
            message: 'TXT worker isolate exited unexpectedly',
          ),
        );
        unawaited(_resetPorts());
      }
    });

    try {
      final isolate = await Isolate.spawn<SendPort>(
        _workerMain,
        replyPort.sendPort,
        onError: errorPort.sendPort,
        onExit: exitPort.sendPort,
        debugName: 'PureReadTxtWorker',
      );
      _isolate = isolate;

      if (_disposed) {
        isolate.kill(priority: Isolate.immediate);
        await _resetPorts();
        throw StateError('TxtIsolateWorker was disposed during startup');
      }

      return await readyCompleter.future;
    } catch (e) {
      if (!_disposed) {
        await _resetPorts();
      }
      rethrow;
    }
  }

  void _failAllPending(Object error) {
    if (_pending.isEmpty) return;
    final entries = _pending.values.toList(growable: false);
    _pending.clear();
    for (final completer in entries) {
      if (!completer.isCompleted) {
        completer.completeError(error);
      }
    }
  }

  Future<void> _resetPorts() async {
    _workerSendPort = null;
    _startFuture = null;
    _isolate = null;

    await _replySub?.cancel();
    await _errorSub?.cancel();
    await _exitSub?.cancel();
    _replySub = null;
    _errorSub = null;
    _exitSub = null;

    _replyPort?.close();
    _errorPort?.close();
    _exitPort?.close();
    _replyPort = null;
    _errorPort = null;
    _exitPort = null;
  }

  /// Shuts down the background isolate and cancels any pending operations.
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;

    final startFuture = _startFuture;
    if (startFuture != null && _workerSendPort == null) {
      try {
        await startFuture;
      } catch (_) {
        // Startup failed or was cancelled during disposal.
      }
    }

    _failAllPending(
      const CancelledFailure(
        message: 'TxtIsolateWorker disposed before request completed',
      ),
    );

    final workerPort = _workerSendPort;
    if (workerPort != null) {
      workerPort.send(null);
    }

    final isolate = _isolate;
    await _resetPorts();
    isolate?.kill(priority: Isolate.beforeNextEvent);
  }
}

Future<void> _workerMain(SendPort mainPort) async {
  final workerPort = ReceivePort();
  mainPort.send(workerPort.sendPort);

  await for (final Object? msg in workerPort) {
    if (msg == null) {
      break;
    }
    if (msg is! _WorkerRequest) {
      continue;
    }

    try {
      final result = _executeTask(msg.task);
      mainPort.send(_WorkerResponse(id: msg.id, value: result));
    } on AppFailure catch (failure, st) {
      mainPort.send(
        _WorkerResponse(
          id: msg.id,
          error: _WorkerError.fromAppFailure(failure, st),
        ),
      );
    } on FileSystemException catch (e, st) {
      mainPort.send(
        _WorkerResponse(
          id: msg.id,
          error: _WorkerError(
            kind: _WorkerErrorKind.fileAccess,
            message: e.message,
            filePath: e.path,
            stackTrace: st.toString(),
          ),
        ),
      );
    } on FormatException catch (e, st) {
      mainPort.send(
        _WorkerResponse(
          id: msg.id,
          error: _WorkerError(
            kind: _WorkerErrorKind.encoding,
            message: e.message,
            stackTrace: st.toString(),
          ),
        ),
      );
    } catch (e, st) {
      mainPort.send(
        _WorkerResponse(
          id: msg.id,
          error: _WorkerError(
            kind: _WorkerErrorKind.unknown,
            message: e.toString(),
            stackTrace: st.toString(),
          ),
        ),
      );
    }
  }

  workerPort.close();
}

Object? _executeTask(_WorkerTask task) {
  switch (task) {
    case _WarmUpGbkTask():
      TxtCodecHelper.warmUpGbkTable();
      return null;

    case _DetectEncodingTask():
      return TxtEncodingDetector.detectFileSync(
        File(task.filePath),
        chunkSize: task.chunkSize,
        maxSampleBytes: task.maxSampleBytes,
      );

    case _ScanFileTask():
      return TxtChapterScanner.scanFileSync(
        File(task.filePath),
        forcedEncoding: task.forcedEncoding,
        chapterRegex:
            task.customPattern != null ? RegExp(task.customPattern!) : null,
        chunkBytes: task.chunkBytes,
        maxCandidateLineBytes: task.maxCandidateLineBytes,
        fallbackSegmentBytes: task.fallbackSegmentBytes,
      );

    case _ReadChapterTask():
      return TxtChapterScanner.readChapterSliceSync(
        File(task.filePath),
        ChapterIndexEntry(
          chapterIndex: task.chapterIndex,
          title: task.title,
          byteStart: task.byteStart,
          byteEnd: task.byteEnd,
        ),
        task.encoding,
        allowMalformed: task.allowMalformed,
      );

    case _HashFileTask():
      return TxtChapterScanner.computeFastFileHashSync(task.filePath);
  }
}

sealed class _WorkerTask {
  const _WorkerTask();
}

final class _WarmUpGbkTask extends _WorkerTask {
  const _WarmUpGbkTask();
}

final class _DetectEncodingTask extends _WorkerTask {
  const _DetectEncodingTask({
    required this.filePath,
    required this.chunkSize,
    required this.maxSampleBytes,
  });

  final String filePath;
  final int chunkSize;
  final int maxSampleBytes;
}

final class _ScanFileTask extends _WorkerTask {
  const _ScanFileTask({
    required this.filePath,
    required this.forcedEncoding,
    required this.customPattern,
    required this.chunkBytes,
    required this.maxCandidateLineBytes,
    required this.fallbackSegmentBytes,
  });

  final String filePath;
  final TxtEncoding? forcedEncoding;
  final String? customPattern;
  final int chunkBytes;
  final int maxCandidateLineBytes;
  final int fallbackSegmentBytes;
}

final class _ReadChapterTask extends _WorkerTask {
  const _ReadChapterTask({
    required this.filePath,
    required this.chapterIndex,
    required this.title,
    required this.byteStart,
    required this.byteEnd,
    required this.encoding,
    required this.allowMalformed,
  });

  final String filePath;
  final int chapterIndex;
  final String title;
  final int byteStart;
  final int byteEnd;
  final TxtEncoding encoding;
  final bool allowMalformed;
}

final class _HashFileTask extends _WorkerTask {
  const _HashFileTask({required this.filePath});

  final String filePath;
}

final class _WorkerRequest {
  const _WorkerRequest({
    required this.id,
    required this.task,
  });

  final int id;
  final _WorkerTask task;
}

final class _WorkerResponse {
  const _WorkerResponse({
    required this.id,
    this.value,
    this.error,
  });

  final int id;
  final Object? value;
  final _WorkerError? error;
}

enum _WorkerErrorKind { fileAccess, encoding, cancelled, unknown }

final class _WorkerError {
  const _WorkerError({
    required this.kind,
    required this.message,
    this.filePath,
    this.detectedEncoding,
    required this.stackTrace,
  });

  factory _WorkerError.fromAppFailure(AppFailure failure, StackTrace st) {
    return switch (failure) {
      FileAccessFailure() => _WorkerError(
          kind: _WorkerErrorKind.fileAccess,
          message: failure.message,
          filePath: failure.filePath,
          stackTrace: (failure.stackTrace ?? st).toString(),
        ),
      EncodingFailure() => _WorkerError(
          kind: _WorkerErrorKind.encoding,
          message: failure.message,
          filePath: failure.filePath,
          detectedEncoding: failure.detectedEncoding,
          stackTrace: (failure.stackTrace ?? st).toString(),
        ),
      CancelledFailure() => _WorkerError(
          kind: _WorkerErrorKind.cancelled,
          message: failure.message,
          stackTrace: (failure.stackTrace ?? st).toString(),
        ),
      _ => _WorkerError(
          kind: _WorkerErrorKind.unknown,
          message: failure.message,
          stackTrace: (failure.stackTrace ?? st).toString(),
        ),
    };
  }

  final _WorkerErrorKind kind;
  final String message;
  final String? filePath;
  final String? detectedEncoding;
  final String stackTrace;

  Object toException() {
    final st = StackTrace.fromString(stackTrace);
    return switch (kind) {
      _WorkerErrorKind.fileAccess => FileAccessFailure(
          message: message,
          filePath: filePath,
          stackTrace: st,
        ),
      _WorkerErrorKind.encoding => EncodingFailure(
          message: message,
          filePath: filePath,
          detectedEncoding: detectedEncoding,
          stackTrace: st,
        ),
      _WorkerErrorKind.cancelled => CancelledFailure(
          message: message,
          stackTrace: st,
        ),
      _WorkerErrorKind.unknown => StateError(message),
    };
  }
}
