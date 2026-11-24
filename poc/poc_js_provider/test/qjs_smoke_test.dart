import 'dart:isolate';

import 'package:flutter_test/flutter_test.dart';
import 'package:qjs/qjs.dart';

void main() {
  test('qjs executes JS and interrupts infinite loop via setDeadline', () {
    final rt = JSRuntime.create(const JSRuntimeConfig.hardened());
    try {
      final sum = rt.evaluateJavascript('1 + 2 * 3');
      expect(sum.asNumber, 7.0);

      rt.setDeadline(const Duration(milliseconds: 80));
      final sw = Stopwatch()..start();
      expect(
        () => rt.evaluateJavascript('while (true) {}'),
        throwsA(isA<JSException>()),
      );
      sw.stop();
      expect(sw.elapsedMilliseconds, lessThan(1000));

      // Runtime remains usable after clearing deadline.
      rt.clearDeadline();
      expect(rt.evaluateJavascript('"ok"').asDartString, 'ok');
    } finally {
      rt.release();
    }
  });

  test('qjs runs inside background Isolate and supports JSInterruptHandle', () async {
    final readyPort = ReceivePort();
    final resultPort = ReceivePort();

    await Isolate.spawn((List<SendPort> ports) {
      final ready = ports[0];
      final done = ports[1];
      final rt = JSRuntime.create(const JSRuntimeConfig.hardened());
      ready.send(rt.interruptHandle);
      try {
        rt.evaluateJavascript('let x = 0; while (true) { x++; }');
        done.send('completed');
      } catch (e) {
        done.send(e.toString());
      } finally {
        rt.release();
      }
    }, [readyPort.sendPort, resultPort.sendPort]);

    final handle = await readyPort.first as JSInterruptHandle;
    await Future<void>.delayed(const Duration(milliseconds: 60));
    final sent = handle.requestInterrupt();
    expect(sent, isTrue);

    final outcome = await resultPort.first as String;
    expect(outcome, contains('interrupted'));
  });
}
