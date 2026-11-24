import 'dart:isolate';

import 'package:flutter_test/flutter_test.dart';
import 'package:pureread/domain/domain.dart';
import 'package:pureread/engine/source_engine/parsing/pure_md5.dart';
import 'package:pureread/infrastructure/js/qjs_sandbox_runtime.dart';
import 'package:qjs/qjs.dart';

void main() {
  group('PureMd5', () {
    test('matches RFC 1321 standard test vectors and 16-char slice', () {
      expect(PureMd5.digestHex(''), 'd41d8cd98f00b204e9800998ecf8427e');
      expect(PureMd5.digestHex('a'), '0cc175b9c0f1b6a831c399e269772661');
      expect(PureMd5.digestHex('abc'), '900150983cd24fb0d6963f7d28e17f72');
      expect(
        PureMd5.digestHex('message digest'),
        'f96b697d7cb7938d525a2f31aaf161d0',
      );
      expect(
        PureMd5.digestHex('abcdefghijklmnopqrstuvwxyz'),
        'c3fcd3d76192e4007dfb496cca67e13b',
      );
      expect(PureMd5.digest16Hex('abc'), '3cd24fb0d6963f7d');
    });
  });

  group('QjsSandboxRuntime', () {
    test('enforces hardened config (eval & Proxy disabled) and evaluates bindings + MD5/Base64 helpers', () async {
      final runtime = QjsSandboxRuntime(sourceId: 'qjs-hardened');
      try {
        expect(runtime.memoryLimitBytes, 64 * 1024 * 1024);
        expect(runtime.maxStackSizeBytes, 512 * 1024);

        final res = await runtime.evaluate(
          r'''
          host.log("hello", 42);
          console.warn("warn-msg");
          JSON.stringify({
            sum: x + y,
            md5: host.md5("abc"),
            md516: host.md5Encode16("abc"),
            b64: host.base64Encode("净读PureRead"),
            decoded: host.base64Decode(host.base64Encode("净读PureRead")),
            atobVal: atob(btoa("hello")),
            hasEval: (() => { try { eval("1+1"); return true; } catch (_) { return false; } })(),
            hasProxy: typeof Proxy !== "undefined"
          });
          ''',
          bindings: const <String, Object?>{'x': 19, 'y': 23},
        );

        expect(res.logs, contains('hello 42'));
        expect(res.logs, contains('[warn] warn-msg'));
        expect(res.value, contains('"sum":42'));
        expect(res.value, contains('"md5":"900150983cd24fb0d6963f7d28e17f72"'));
        expect(res.value, contains('"md516":"3cd24fb0d6963f7d"'));
        expect(res.value, contains('"decoded":"净读PureRead"'));
        expect(res.value, contains('"atobVal":"hello"'));
        expect(res.value, contains('"hasEval":false'));
        expect(res.value, contains('"hasProxy":false'));
      } finally {
        await runtime.dispose();
      }
    });

    test('interrupts synchronous infinite loop via setDeadline and recovers cleanly', () async {
      final runtime = QjsSandboxRuntime(sourceId: 'qjs-sync-loop');
      try {
        final sw = Stopwatch()..start();
        await expectLater(
          () => runtime.evaluate(
            'let i = 0; while (true) { i++; }',
            timeout: const Duration(milliseconds: 80),
          ),
          throwsA(
            isA<JsExecutionFailure>().having(
              (e) => e.isTimeout,
              'isTimeout',
              isTrue,
            ),
          ),
        );
        sw.stop();
        expect(sw.elapsedMilliseconds, lessThan(1000));

        final recovery = await runtime.evaluate('6 * 7');
        expect(recovery.value, '42');
      } finally {
        await runtime.dispose();
      }
    });

    test('interrupts post-await async infinite loop via Timer + JSInterruptHandle', () async {
      final runtime = QjsSandboxRuntime(
        sourceId: 'qjs-async-loop',
        asyncHostFunctions: <String, HostAsyncCallback>{
          'fetchDelayed': (_) async {
            await Future<void>.delayed(const Duration(milliseconds: 20));
            return 'ready';
          },
        },
      );
      try {
        final sw = Stopwatch()..start();
        await expectLater(
          () => runtime.evaluate(
            '''
            (async () => {
              const v = await host.fetchDelayed();
              if (v === 'ready') {
                while (true) {}
              }
              return v;
            })();
            ''',
            timeout: const Duration(milliseconds: 120),
          ),
          throwsA(
            isA<JsExecutionFailure>().having(
              (e) => e.isTimeout,
              'isTimeout',
              isTrue,
            ),
          ),
        );
        sw.stop();
        expect(sw.elapsedMilliseconds, lessThan(1500));
      } finally {
        await runtime.dispose();
      }
    });

    test('supports cooperative CancellationToken during async host call and in background Isolate', () async {
      // 1. CancellationToken during pending async host call
      final runtime = QjsSandboxRuntime(
        sourceId: 'qjs-cancel-async',
        asyncHostFunctions: <String, HostAsyncCallback>{
          'slowWait': (_) async {
            await Future<void>.delayed(const Duration(milliseconds: 500));
            return 'late';
          },
        },
      );
      try {
        final cancelToken = CancellationToken();
        Future<void>.delayed(
          const Duration(milliseconds: 50),
          cancelToken.cancel,
        );
        await expectLater(
          () => runtime.evaluate(
            '(async () => await host.slowWait())()',
            timeout: const Duration(seconds: 3),
            cancelToken: cancelToken,
          ),
          throwsA(isA<CancelledFailure>()),
        );
      } finally {
        await runtime.dispose();
      }

      // 2. Background Isolate JSInterruptHandle cooperative cancellation
      final isolateCancel = CancellationToken();
      final readyPort = ReceivePort();
      final sendPort = readyPort.sendPort;

      final futureOutcome = Isolate.run(() async {
        final rt = JSRuntime.create(const JSRuntimeConfig.hardened());
        sendPort.send(rt.interruptHandle);
        try {
          rt.evaluateJavascript('while (true) {}');
          return 'completed';
        } on JSException catch (e) {
          return e.toString();
        } finally {
          rt.release();
        }
      });

      final handle = await readyPort.first as JSInterruptHandle;
      readyPort.close();
      isolateCancel.addListener(handle.requestInterrupt);

      await Future<void>.delayed(const Duration(milliseconds: 60));
      isolateCancel.cancel();
      expect(await futureOutcome, contains('interrupted'));
    });

    test('isolates memory exhaustion and script exceptions into JsExecutionFailure', () async {
      final runtime = QjsSandboxRuntime(
        sourceId: 'qjs-oom',
        memoryLimitBytes: 2 * 1024 * 1024,
      );
      try {
        await expectLater(
          () => runtime.evaluate(
            'const a = []; for (let i = 0; i < 10000; i++) { a.push("x".repeat(4096)); }',
            timeout: const Duration(seconds: 2),
          ),
          throwsA(isA<JsExecutionFailure>()),
        );

        runtime.resetRuntime();

        await expectLater(
          () => runtime.evaluate(
            'function explode() { throw new Error("kaboom"); } explode();',
          ),
          throwsA(
            isA<JsExecutionFailure>()
                .having((e) => e.isTimeout, 'isTimeout', isFalse)
                .having((e) => e.message, 'message', contains('kaboom'))
                .having((e) => e.jsStackTrace, 'jsStackTrace', isNotNull),
          ),
        );
      } finally {
        await runtime.dispose();
      }
    });
  });
}
