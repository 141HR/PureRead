import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pureread/infrastructure/platform/method_channel_platform_bridge.dart';
import 'package:pureread/infrastructure/platform/platform_bridge.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('MethodChannelPlatformBridge', () {
    const channel = MethodChannel(MethodChannelPlatformBridge.channelName);
    const volumeChannelName = MethodChannelPlatformBridge.volumeChannelName;

    late MethodChannelPlatformBridge bridge;
    final recordedCalls = <MethodCall>[];

    setUp(() {
      recordedCalls.clear();
      bridge = MethodChannelPlatformBridge();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            recordedCalls.add(call);
            if (call.method == 'pickFiles') {
              return <String>[r'D:\books\a.txt', r'D:\books\b.txt'];
            }
            return null;
          });
    });

    tearDown(() async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel(volumeChannelName),
            null,
          );
      await bridge.dispose();
    });

    test('normalizes extensions and returns picked file paths', () async {
      final result = await bridge.pickFiles(
        extensions: const <String>['.TXT', ' otf '],
        allowMultiple: true,
      );

      expect(result, equals(<String>[r'D:\books\a.txt', r'D:\books\b.txt']));
      expect(recordedCalls, hasLength(1));
      expect(recordedCalls.single.method, 'pickFiles');
      expect(
        recordedCalls.single.arguments,
        equals(<String, Object>{
          'extensions': <String>['txt', 'otf'],
          'allowMultiple': true,
        }),
      );
    });

    test('invokes screen, volume, immersive, and bossKeyHide methods', () async {
      await bridge.setKeepScreenOn(true);
      await bridge.setVolumeKeyPaging(true);
      await bridge.setImmersiveMode(true);
      await bridge.bossKeyHide();

      expect(
        recordedCalls.map((c) => c.method).toList(),
        equals(<String>[
          'setKeepScreenOn',
          'setVolumeKeyPaging',
          'setImmersiveMode',
          'bossKeyHide',
        ]),
      );
      expect(recordedCalls[0].arguments, equals({'enabled': true}));
      expect(recordedCalls[1].arguments, equals({'enabled': true}));
      expect(recordedCalls[2].arguments, equals({'enabled': true}));
      expect(recordedCalls[3].arguments, isNull);
    });

    test('returns empty list and ignores MissingPluginException safely', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);

      final picked = await bridge.pickFiles(extensions: const <String>['txt']);
      expect(picked, isEmpty);

      await bridge.setKeepScreenOn(false);
      await bridge.setVolumeKeyPaging(false);
      await bridge.setImmersiveMode(false);
      await bridge.bossKeyHide();
    });

    test('forwards volumeKeyEvents up/down from EventChannel', () async {
      const codec = StandardMethodCodec();
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

      messenger.setMockMethodCallHandler(
        const MethodChannel(volumeChannelName),
        (call) async => null,
      );

      final events = <VolumeKeyDirection>[];
      final sub = bridge.volumeKeyEvents.listen(events.add);

      // Give onListen microtask a chance to register before dispatching events.
      await Future<void>.delayed(Duration.zero);

      await messenger.handlePlatformMessage(
        volumeChannelName,
        codec.encodeSuccessEnvelope('up'),
        (_) {},
      );
      await messenger.handlePlatformMessage(
        volumeChannelName,
        codec.encodeSuccessEnvelope('down'),
        (_) {},
      );
      await messenger.handlePlatformMessage(
        volumeChannelName,
        codec.encodeSuccessEnvelope('ignored'),
        (_) {},
      );

      await Future<void>.delayed(Duration.zero);
      expect(
        events,
        equals(<VolumeKeyDirection>[
          VolumeKeyDirection.up,
          VolumeKeyDirection.down,
        ]),
      );
      await sub.cancel();
    });
  });
}
