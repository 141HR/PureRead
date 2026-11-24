import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:qjs/qjs.dart' as qjs;

import '../../domain/domain.dart';
import 'js_crypto_helpers.dart';

typedef HostSyncCallback = Object? Function(List<Object?> args);
typedef HostAsyncCallback = Future<Object?> Function(List<Object?> args);

/// Sandboxed QuickJS runtime implementation backed by `package:qjs` (QuickJS-NG
/// via Dart Native Assets + `dart:ffi`).
///
/// Enforces:
/// - [JSRuntimeConfig.hardened] defaults (`enableEval: false`,
///   `es6Proxy: false`, 64 MiB heap, 512 KiB stack)
/// - Native C deadline interruption (`JS_SetInterruptHandler` via `setDeadline`)
/// - Async host Promise bridging (`JSPromise.fromAsyncFunction`) with host-side
///   [Timer] + [qjs.JSInterruptHandle.requestInterrupt] guard
/// - Cooperative [CancellationToken] via [qjs.JSInterruptHandle.requestInterrupt]
/// - Built-in pure-Dart RFC1321 MD5 (`host.md5`, `host.md5Encode16`), Base64
///   (`host.base64Encode`, `host.base64Decode`, global `btoa`/`atob`), and
///   FIPS-197 AES / FIPS-46 DES symmetric crypto (`host.aesEncodeBase64`,
///   `host.aesDecodeBase64`, `host.symmetricCrypto`) helpers
class QjsSandboxRuntime implements JsRuntime {
  static const int defaultMemoryLimitBytes = 64 * 1024 * 1024;
  static const int defaultMaxStackSizeBytes = 512 * 1024;

  final int memoryLimitBytes;
  final int maxStackSizeBytes;
  final bool enableEval;
  final bool es6Proxy;
  final Map<String, HostSyncCallback> _syncHostFunctions;
  final Map<String, HostAsyncCallback> _asyncHostFunctions;
  final String? sourceId;

  qjs.JSRuntime? _rt;
  bool _disposed = false;

  QjsSandboxRuntime({
    this.memoryLimitBytes = defaultMemoryLimitBytes,
    this.maxStackSizeBytes = defaultMaxStackSizeBytes,
    this.enableEval = false,
    this.es6Proxy = false,
    this.sourceId,
    Map<String, HostSyncCallback> syncHostFunctions = const {},
    Map<String, HostAsyncCallback> asyncHostFunctions = const {},
  }) : _syncHostFunctions = Map.of(syncHostFunctions),
       _asyncHostFunctions = Map.of(asyncHostFunctions);

  qjs.JSRuntime _ensureRuntime() {
    if (_disposed) {
      throw StateError('QjsSandboxRuntime has already been disposed.');
    }
    if (_rt != null && !_rt!.isReleased) {
      return _rt!;
    }
    final config = (!enableEval && !es6Proxy)
        ? qjs.JSRuntimeConfig.hardened(
            memoryLimit: memoryLimitBytes,
            maxStackSize: maxStackSizeBytes,
          )
        : qjs.JSRuntimeConfig(
            enableEval: enableEval,
            es6Proxy: es6Proxy,
            microtaskQueue: false,
            memoryLimit: memoryLimitBytes,
            maxStackSize: maxStackSizeBytes,
          );
    final rt = qjs.JSRuntime.create(config);
    _rt = rt;
    return rt;
  }

  /// Resets the underlying QuickJS VM (used after an unrecoverable fault or to
  /// drop stale JS state between untrusted scripts).
  void resetRuntime() {
    final rt = _rt;
    _rt = null;
    if (rt != null && !rt.isReleased) {
      rt.release();
    }
  }

  @override
  Future<JsExecutionResult> evaluate(
    String script, {
    Map<String, Object?> bindings = const {},
    Duration timeout = const Duration(seconds: 5),
    CancellationToken? cancelToken,
  }) async {
    cancelToken?.throwIfCancelled();

    final sw = Stopwatch()..start();
    final logs = <String>[];
    final qjs.JSRuntime rt;
    try {
      rt = _ensureRuntime();
    } catch (e, st) {
      throw JsExecutionFailure(
        message: 'Failed to initialize QuickJS runtime: $e',
        sourceId: sourceId,
        cause: e,
        stackTrace: st,
      );
    }

    final completer = Completer<String>();
    Timer? asyncDeadlineTimer;
    var timedOutByHost = false;
    var cancelledByToken = false;

    void completeErrorOnce(Object err, [StackTrace? st]) {
      if (!completer.isCompleted) {
        completer.completeError(err, st);
      }
    }

    final interruptHandle = rt.interruptHandle;
    void onCancel() {
      cancelledByToken = true;
      interruptHandle.requestInterrupt();
      completeErrorOnce(const CancelledFailure());
    }

    cancelToken?.addListener(onCancel);

    _installConsole(rt, logs);
    _installCryptoGlobals(rt);
    _installHostNamespace(rt, logs);
    for (final entry in bindings.entries) {
      rt.global[entry.key] = _dartToJs(rt, entry.value);
    }

    rt.onUncaughtError = (Object error) {
      if (cancelledByToken || (cancelToken?.isCancelled ?? false)) {
        completeErrorOnce(const CancelledFailure());
        return;
      }
      completeErrorOnce(
        _mapJsObjectError(
          error,
          sourceId: sourceId,
          timedOutByHost: timedOutByHost,
        ),
      );
    };
    rt.onUnhandledRejection = (promise, reason, isHandled) {
      if (!isHandled) {
        if (cancelledByToken || (cancelToken?.isCancelled ?? false)) {
          completeErrorOnce(const CancelledFailure());
          return;
        }
        completeErrorOnce(
          _mapJsValueRejection(
            rt,
            reason,
            sourceId: sourceId,
            timedOutByHost: timedOutByHost,
          ),
        );
      }
    };

    try {
      rt.setDeadline(timeout);

      final onResolve = qjs.JSFunction.createFromHostFunction(
        rt,
        (innerRt, _, args) {
          final out = args.isEmpty ? '' : _jsToString(innerRt, args.first);
          if (!completer.isCompleted) {
            completer.complete(out);
          }
          return qjs.JSValue.undefined(innerRt);
        },
        name: '__pureReadResolve',
        length: 1,
      );
      final onReject = qjs.JSFunction.createFromHostFunction(
        rt,
        (innerRt, _, args) {
          if (cancelledByToken || (cancelToken?.isCancelled ?? false)) {
            completeErrorOnce(const CancelledFailure());
            return qjs.JSValue.undefined(innerRt);
          }
          final errVal = args.isEmpty
              ? qjs.JSValue.string(innerRt, 'Unknown JS rejection')
              : args.first;
          completeErrorOnce(
            _mapJsValueRejection(
              innerRt,
              errVal,
              sourceId: sourceId,
              timedOutByHost: timedOutByHost,
            ),
          );
          return qjs.JSValue.undefined(innerRt);
        },
        name: '__pureReadReject',
        length: 1,
      );

      final result = rt.evaluateJavascript(script, sourceUrl: 'plugin.js');

      if (_isPromiseLike(result)) {
        final thenFn = result.asObject['then'].asFunctionUnsafe;
        thenFn([onResolve.asValue, onReject.asValue], result);

        asyncDeadlineTimer = Timer(timeout, () {
          timedOutByHost = true;
          interruptHandle.requestInterrupt();
          completeErrorOnce(
            JsExecutionFailure(
              message:
                  'JavaScript async execution exceeded ${timeout.inMilliseconds}ms timeout',
              sourceId: sourceId,
              isTimeout: true,
            ),
          );
        });

        final asyncValue = await completer.future;
        sw.stop();
        return JsExecutionResult(
          value: asyncValue,
          logs: List.unmodifiable(logs),
          elapsedMs: sw.elapsedMilliseconds,
        );
      }

      final syncValue = _jsToString(rt, result);
      sw.stop();
      return JsExecutionResult(
        value: syncValue,
        logs: List.unmodifiable(logs),
        elapsedMs: sw.elapsedMilliseconds,
      );
    } on AppFailure {
      rethrow;
    } on qjs.JSException catch (e, st) {
      if (cancelledByToken || (cancelToken?.isCancelled ?? false)) {
        throw CancelledFailure(cause: e, stackTrace: st);
      }
      throw _mapJsObjectError(
        e,
        sourceId: sourceId,
        timedOutByHost: timedOutByHost,
        stackTrace: st,
      );
    } on qjs.JSNativeException catch (e, st) {
      throw JsExecutionFailure(
        message: 'QuickJS native error: ${e.message}',
        sourceId: sourceId,
        cause: e,
        stackTrace: st,
      );
    } catch (e, st) {
      if (cancelledByToken || (cancelToken?.isCancelled ?? false)) {
        throw CancelledFailure(cause: e, stackTrace: st);
      }
      throw JsExecutionFailure(
        message: 'QuickJS execution failed: $e',
        sourceId: sourceId,
        cause: e,
        stackTrace: st,
      );
    } finally {
      asyncDeadlineTimer?.cancel();
      cancelToken?.removeListener(onCancel);
      if (_rt != null && !_rt!.isReleased) {
        _rt!.clearDeadline();
        _rt!.onUncaughtError = null;
        _rt!.onUnhandledRejection = null;
      }
    }
  }

  void _installConsole(qjs.JSRuntime rt, List<String> logs) {
    final consoleObj = qjs.JSObject.create(rt);
    for (final level in ['log', 'info', 'warn', 'error', 'debug']) {
      consoleObj[level] = qjs.JSFunction.createFromHostFunction(
        rt,
        (innerRt, _, args) {
          final text = args.map((a) => _jsToString(innerRt, a)).join(' ');
          logs.add(level == 'log' ? text : '[$level] $text');
          return qjs.JSValue.undefined(innerRt);
        },
        name: level,
      ).asValue;
    }
    rt.global['console'] = consoleObj.asValue;
  }

  void _installCryptoGlobals(qjs.JSRuntime rt) {
    rt.global['btoa'] = qjs.JSFunction.createFromHostFunction(
      rt,
      (innerRt, _, args) {
        final raw = args.isEmpty ? '' : _jsToString(innerRt, args.first);
        return qjs.JSValue.string(
          innerRt,
          JsCryptoHelpers.base64EncodeString(raw),
        );
      },
      name: 'btoa',
    ).asValue;

    rt.global['atob'] = qjs.JSFunction.createFromHostFunction(
      rt,
      (innerRt, _, args) {
        final raw = args.isEmpty ? '' : _jsToString(innerRt, args.first);
        return qjs.JSValue.string(
          innerRt,
          JsCryptoHelpers.base64DecodeString(raw),
        );
      },
      name: 'atob',
    ).asValue;
  }

  void _installHostNamespace(qjs.JSRuntime rt, List<String> logs) {
    final hostObj = qjs.JSObject.create(rt);

    hostObj['log'] = qjs.JSFunction.createFromHostFunction(
      rt,
      (innerRt, _, args) {
        final text = args.map((a) => _jsToString(innerRt, a)).join(' ');
        logs.add(text);
        return qjs.JSValue.undefined(innerRt);
      },
      name: 'log',
    ).asValue;

    hostObj['md5'] = qjs.JSFunction.createFromHostFunction(
      rt,
      (innerRt, _, args) {
        final input = args.isEmpty ? '' : _jsToString(innerRt, args.first);
        return qjs.JSValue.string(innerRt, JsCryptoHelpers.md5Hex(input));
      },
      name: 'md5',
    ).asValue;

    hostObj['md5Encode16'] = qjs.JSFunction.createFromHostFunction(
      rt,
      (innerRt, _, args) {
        final input = args.isEmpty ? '' : _jsToString(innerRt, args.first);
        return qjs.JSValue.string(innerRt, JsCryptoHelpers.md5Hex16(input));
      },
      name: 'md5Encode16',
    ).asValue;

    hostObj['base64Encode'] = qjs.JSFunction.createFromHostFunction(
      rt,
      (innerRt, _, args) {
        final input = args.isEmpty ? '' : _jsToString(innerRt, args.first);
        return qjs.JSValue.string(
          innerRt,
          JsCryptoHelpers.base64EncodeString(input),
        );
      },
      name: 'base64Encode',
    ).asValue;

    hostObj['base64Decode'] = qjs.JSFunction.createFromHostFunction(
      rt,
      (innerRt, _, args) {
        final input = args.isEmpty ? '' : _jsToString(innerRt, args.first);
        return qjs.JSValue.string(
          innerRt,
          JsCryptoHelpers.base64DecodeString(input),
        );
      },
      name: 'base64Decode',
    ).asValue;

    hostObj['strToBytes'] = qjs.JSFunction.createFromHostFunction(
      rt,
      (innerRt, _, args) {
        final input = args.isEmpty ? '' : _jsToString(innerRt, args.first);
        return _dartToJs(innerRt, utf8.encode(input));
      },
      name: 'strToBytes',
    ).asValue;

    hostObj['base64DecodeBytes'] = qjs.JSFunction.createFromHostFunction(
      rt,
      (innerRt, _, args) => _runHostCrypto(innerRt, () {
        final input = args.isEmpty ? '' : _jsToString(innerRt, args.first);
        return JsCryptoHelpers.base64DecodeBytes(input);
      }),
      name: 'base64DecodeBytes',
    ).asValue;

    hostObj['hexDecodeBytes'] = qjs.JSFunction.createFromHostFunction(
      rt,
      (innerRt, _, args) => _runHostCrypto(innerRt, () {
        final input = args.isEmpty ? '' : _jsToString(innerRt, args.first);
        return JsCryptoHelpers.hexDecodeBytes(input);
      }),
      name: 'hexDecodeBytes',
    ).asValue;

    hostObj['aesEncodeBase64'] = qjs.JSFunction.createFromHostFunction(
      rt,
      (innerRt, _, args) => _runHostCrypto(
        innerRt,
        () => _evaluateAesHost(innerRt, args, encrypt: true, outputHex: false),
      ),
      name: 'aesEncodeBase64',
    ).asValue;

    hostObj['aesDecodeBase64'] = qjs.JSFunction.createFromHostFunction(
      rt,
      (innerRt, _, args) => _runHostCrypto(
        innerRt,
        () => _evaluateAesHost(innerRt, args, encrypt: false, outputHex: false),
      ),
      name: 'aesDecodeBase64',
    ).asValue;

    hostObj['aesEncodeHex'] = qjs.JSFunction.createFromHostFunction(
      rt,
      (innerRt, _, args) => _runHostCrypto(
        innerRt,
        () => _evaluateAesHost(innerRt, args, encrypt: true, outputHex: true),
      ),
      name: 'aesEncodeHex',
    ).asValue;

    hostObj['aesDecodeHex'] = qjs.JSFunction.createFromHostFunction(
      rt,
      (innerRt, _, args) => _runHostCrypto(
        innerRt,
        () => _evaluateAesHost(innerRt, args, encrypt: false, outputHex: true),
      ),
      name: 'aesDecodeHex',
    ).asValue;

    hostObj['symmetricCrypto'] = qjs.JSFunction.createFromHostFunction(
      rt,
      (innerRt, _, args) =>
          _runHostCrypto(innerRt, () => _evaluateSymmetricHost(innerRt, args)),
      name: 'symmetricCrypto',
    ).asValue;

    for (final entry in _syncHostFunctions.entries) {
      hostObj[entry.key] = qjs.JSFunction.createFromHostFunction(
        rt,
        (innerRt, _, args) {
          final dartArgs = args.map((a) => _jsToDart(innerRt, a)).toList();
          final res = entry.value(dartArgs);
          return _dartToJs(innerRt, res);
        },
        name: entry.key,
      ).asValue;
    }

    for (final entry in _asyncHostFunctions.entries) {
      hostObj[entry.key] = qjs.JSFunction.createFromHostFunction(
        rt,
        (innerRt, _, args) {
          final dartArgs = args.map((a) => _jsToDart(innerRt, a)).toList();
          return qjs.JSPromise.fromAsyncFunction(innerRt, () async {
            final res = await entry.value(dartArgs);
            if (innerRt.isReleased) {
              throw StateError('JSRuntime released');
            }
            return _dartToJs(innerRt, res);
          });
        },
        name: entry.key,
      ).asValue;
    }

    rt.global['host'] = hostObj.asValue;
  }

  static qjs.JSValue _runHostCrypto(
    qjs.JSRuntime rt,
    Object? Function() action,
  ) {
    try {
      return _dartToJs(rt, action());
    } on Object catch (e) {
      throw qjs.JSException(qjs.JSError.create(rt, e.toString()));
    }
  }

  static Object? _evaluateAesHost(
    qjs.JSRuntime rt,
    List<qjs.JSValue> args, {
    required bool encrypt,
    required bool outputHex,
  }) {
    final dataArg = args.isNotEmpty ? _jsToDart(rt, args[0]) : '';
    final keyArg = args.length > 1 ? _jsToDart(rt, args[1]) : null;
    final rawTransformation = args.length > 2
        ? _jsToOptionalString(rt, args[2])
        : null;
    final ivArg = args.length > 3 ? _jsToDart(rt, args[3]) : null;

    if (keyArg == null) {
      throw ArgumentError('AES key must not be null or undefined.');
    }

    final keyBytes = JsCryptoHelpers.coerceBytes(keyArg, name: 'key');
    final ivBytes = ivArg == null
        ? null
        : JsCryptoHelpers.coerceBytes(ivArg, name: 'iv');
    final spec = SymmetricTransformation.parse(
      rawTransformation,
      defaultAlgorithm: SymmetricAlgorithm.aes,
      hasNonEmptyIv: ivBytes != null && ivBytes.isNotEmpty,
    );
    if (spec.algorithm != SymmetricAlgorithm.aes) {
      throw ArgumentError.value(
        rawTransformation,
        'transformation',
        'AES helper requires an AES transformation.',
      );
    }
    final transformation = spec.canonical;

    if (encrypt) {
      final plainBytes = JsCryptoHelpers.coerceBytes(dataArg, name: 'data');
      final cipher = JsCryptoHelpers.encryptSymmetric(
        data: plainBytes,
        key: keyBytes,
        transformation: transformation,
        iv: ivBytes,
      );
      return outputHex ? JsCryptoHelpers.hexEncode(cipher) : base64Encode(cipher);
    }

    final Uint8List cipherBytes;
    if (dataArg is List || dataArg is Map || dataArg is Uint8List) {
      cipherBytes = JsCryptoHelpers.coerceBytes(dataArg, name: 'data');
    } else {
      final text = (dataArg ?? '').toString();
      cipherBytes = outputHex
          ? JsCryptoHelpers.hexDecodeBytes(text)
          : JsCryptoHelpers.base64DecodeBytes(text);
    }
    final plain = JsCryptoHelpers.decryptSymmetric(
      data: cipherBytes,
      key: keyBytes,
      transformation: transformation,
      iv: ivBytes,
    );
    return utf8.decode(plain, allowMalformed: true);
  }

  static Object? _evaluateSymmetricHost(
    qjs.JSRuntime rt,
    List<qjs.JSValue> args,
  ) {
    final op = args.isNotEmpty ? _jsToString(rt, args[0]) : '';
    final rawTransformation = args.length > 1
        ? _jsToOptionalString(rt, args[1])
        : null;
    final keyArg = args.length > 2 ? _jsToDart(rt, args[2]) : null;
    final ivArg = args.length > 3 ? _jsToDart(rt, args[3]) : null;
    final dataArg = args.length > 4 ? _jsToDart(rt, args[4]) : null;

    if (keyArg == null) {
      throw ArgumentError('Symmetric cipher key must not be null or undefined.');
    }

    final keyBytes = JsCryptoHelpers.coerceBytes(keyArg, name: 'key');
    final ivBytes = ivArg == null
        ? null
        : JsCryptoHelpers.coerceBytes(ivArg, name: 'iv');
    final spec = SymmetricTransformation.parse(
      rawTransformation,
      defaultAlgorithm: SymmetricAlgorithm.aes,
      hasNonEmptyIv: ivBytes != null && ivBytes.isNotEmpty,
    );
    final transformation = spec.canonical;
    JsCryptoHelpers.validateSymmetricConfig(
      key: keyBytes,
      transformation: transformation,
      iv: ivBytes,
    );

    if (op == 'validate') {
      return true;
    }

    if (op == 'encryptBase64' || op == 'encryptHex' || op == 'encrypt') {
      final cipher = JsCryptoHelpers.encryptSymmetric(
        data: JsCryptoHelpers.coerceBytes(dataArg, name: 'data'),
        key: keyBytes,
        transformation: transformation,
        iv: ivBytes,
      );
      return switch (op) {
        'encryptBase64' => base64Encode(cipher),
        'encryptHex' => JsCryptoHelpers.hexEncode(cipher),
        _ => cipher,
      };
    }

    final Uint8List cipherBytes;
    switch (op) {
      case 'decrypt':
      case 'decryptStr':
        cipherBytes = JsCryptoHelpers.decodeCiphertextInput(
          dataArg,
          blockSize: spec.blockSize,
        );
      case 'decryptBase64Str':
      case 'decryptBase64':
        cipherBytes = _isByteContainer(dataArg)
            ? JsCryptoHelpers.coerceBytes(dataArg, name: 'data')
            : JsCryptoHelpers.base64DecodeBytes((dataArg ?? '').toString());
      case 'decryptHexStr':
      case 'decryptHex':
        cipherBytes = _isByteContainer(dataArg)
            ? JsCryptoHelpers.coerceBytes(dataArg, name: 'data')
            : JsCryptoHelpers.hexDecodeBytes((dataArg ?? '').toString());
      default:
        throw ArgumentError.value(op, 'op', 'Unsupported symmetricCrypto op.');
    }

    final plain = JsCryptoHelpers.decryptSymmetric(
      data: cipherBytes,
      key: keyBytes,
      transformation: transformation,
      iv: ivBytes,
    );
    final wantsBytes =
        op == 'decrypt' || op == 'decryptBase64' || op == 'decryptHex';
    return wantsBytes ? plain : utf8.decode(plain, allowMalformed: true);
  }

  static bool _isByteContainer(Object? value) =>
      value is List || value is Map || value is Uint8List;

  static String? _jsToOptionalString(qjs.JSRuntime rt, qjs.JSValue value) {
    if (value.isUndefined || value.isNull) return null;
    final text = _jsToString(rt, value).trim();
    return text.isEmpty ? null : text;
  }

  static bool _isPromiseLike(qjs.JSValue value) {
    if (!value.isObject) return false;
    final obj = value.asObject;
    if (!obj.hasProperty('then')) return false;
    return obj['then'].asFunctionOrNull != null;
  }

  static qjs.JSValue _dartToJs(qjs.JSRuntime rt, Object? value) {
    if (value == null) return qjs.JSValue.null_(rt);
    if (value is bool) return qjs.JSValue.boolean(rt, value);
    if (value is int) return qjs.JSValue.number(rt, value.toDouble());
    if (value is double) return qjs.JSValue.number(rt, value);
    if (value is String) return qjs.JSValue.string(rt, value);
    if (value is List || value is Map) {
      final bytes = Uint8List.fromList(utf8.encode(jsonEncode(value)));
      return qjs.JSValue.fromJsonUtf8(rt, bytes);
    }
    return qjs.JSValue.string(rt, value.toString());
  }

  static Object? _jsToDart(qjs.JSRuntime rt, qjs.JSValue value) {
    if (value.isUndefined || value.isNull) return null;
    if (value.isBoolean) return value.asBoolean;
    if (value.isNumber) {
      final numVal = value.asNumber;
      if (numVal.isFinite && numVal == numVal.truncateToDouble()) {
        return numVal.toInt();
      }
      return numVal;
    }
    if (value.isString) return value.asDartString;
    if (value.isObject) {
      final jsonStr = _stringifyObject(rt, value);
      if (jsonStr == 'undefined') return null;
      return jsonDecode(jsonStr);
    }
    return _jsToString(rt, value);
  }

  static String _jsToString(qjs.JSRuntime rt, qjs.JSValue value) {
    if (value.isUndefined) return '';
    if (value.isNull) return 'null';
    if (value.isBoolean) return value.asBoolean.toString();
    if (value.isNumber) {
      final numVal = value.asNumber;
      if (numVal.isFinite && numVal == numVal.truncateToDouble()) {
        return numVal.toInt().toString();
      }
      return numVal.toString();
    }
    if (value.isString) return value.asDartString;
    if (value.isObject) {
      return _stringifyObject(rt, value);
    }
    return value.type.name;
  }

  static String _stringifyObject(qjs.JSRuntime rt, qjs.JSValue value) {
    final jsonObj = rt.global['JSON'].asObject;
    final stringify = jsonObj['stringify'].asFunctionUnsafe;
    final res = stringify([value], jsonObj.asValue);
    if (res.isString) return res.asDartString;
    return value.asObject.toString();
  }

  static JsExecutionFailure _mapJsObjectError(
    Object error, {
    required String? sourceId,
    required bool timedOutByHost,
    StackTrace? stackTrace,
  }) {
    final msg = error.toString();
    final isInterrupted = msg.contains('interrupted');
    final isTimeout = timedOutByHost || isInterrupted;
    String? jsStack;
    if (error is qjs.JSException && error.value.isObject) {
      try {
        final stackProp = error.value.asObject.getProperty('stack');
        if (stackProp.isString) {
          jsStack = stackProp.asDartString;
        }
      } catch (_) {}
    }
    return JsExecutionFailure(
      message: isTimeout
          ? 'JavaScript execution interrupted due to timeout'
          : msg,
      sourceId: sourceId,
      jsStackTrace: jsStack,
      isTimeout: isTimeout,
      cause: error,
      stackTrace: stackTrace,
    );
  }

  static JsExecutionFailure _mapJsValueRejection(
    qjs.JSRuntime rt,
    qjs.JSValue reason, {
    required String? sourceId,
    required bool timedOutByHost,
  }) {
    if (reason.isObject) {
      final obj = reason.asObject;
      var message = 'JS Promise rejected';
      String? stack;
      try {
        final m = obj.getProperty('message');
        if (m.isString) message = m.asDartString;
        final s = obj.getProperty('stack');
        if (s.isString) stack = s.asDartString;
      } catch (_) {}
      final isTimeout = timedOutByHost || message.contains('interrupted');
      return JsExecutionFailure(
        message: isTimeout
            ? 'JavaScript execution interrupted due to timeout'
            : message,
        sourceId: sourceId,
        jsStackTrace: stack,
        isTimeout: isTimeout,
      );
    }
    final text = _jsToString(rt, reason);
    final isTimeout = timedOutByHost || text.contains('interrupted');
    return JsExecutionFailure(
      message: isTimeout
          ? 'JavaScript execution interrupted due to timeout'
          : text,
      sourceId: sourceId,
      isTimeout: isTimeout,
    );
  }

  @override
  Future<void> dispose() async {
    _disposed = true;
    resetRuntime();
  }
}
