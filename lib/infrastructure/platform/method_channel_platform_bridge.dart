import 'dart:async';

import 'package:flutter/services.dart';

import 'platform_bridge.dart';

/// MethodChannel / EventChannel implementation of [PlatformBridge] communicating
/// with the zero-plugin Windows Win32 and Android Kotlin hosts on
/// `com.pureread.app/platform`.
class MethodChannelPlatformBridge implements PlatformBridge {
  static const String channelName = 'com.pureread.app/platform';
  static const String volumeChannelName = 'com.pureread.app/platform/volume_keys';

  MethodChannelPlatformBridge({
    MethodChannel? methodChannel,
    EventChannel? volumeEventChannel,
  }) : _methodChannel = methodChannel ?? const MethodChannel(channelName),
       _volumeEventChannel =
           volumeEventChannel ?? const EventChannel(volumeChannelName);

  final MethodChannel _methodChannel;
  final EventChannel _volumeEventChannel;

  StreamController<VolumeKeyDirection>? _volumeController;
  StreamSubscription<dynamic>? _eventSubscription;
  bool _disposed = false;

  @override
  Future<List<String>> pickFiles({
    required List<String> extensions,
    bool allowMultiple = false,
  }) async {
    try {
      final normalized = extensions
          .map((e) => e.trim().replaceFirst(RegExp(r'^\.+'), '').toLowerCase())
          .where((e) => e.isNotEmpty)
          .toList(growable: false);
      final result = await _methodChannel.invokeListMethod<String>(
        'pickFiles',
        <String, Object>{
          'extensions': normalized,
          'allowMultiple': allowMultiple,
        },
      );
      return result ?? const <String>[];
    } on MissingPluginException {
      return const <String>[];
    }
  }

  @override
  Future<void> setKeepScreenOn(bool enabled) async {
    try {
      await _methodChannel.invokeMethod<void>(
        'setKeepScreenOn',
        <String, Object>{'enabled': enabled},
      );
    } on MissingPluginException {
      // Headless tests or unsupported host platforms can safely ignore.
    }
  }

  @override
  Future<void> setVolumeKeyPaging(bool enabled) async {
    try {
      await _methodChannel.invokeMethod<void>(
        'setVolumeKeyPaging',
        <String, Object>{'enabled': enabled},
      );
    } on MissingPluginException {
      // Headless tests or non-Android platforms can safely ignore.
    }
  }

  @override
  Stream<VolumeKeyDirection> get volumeKeyEvents {
    if (_disposed) {
      return const Stream<VolumeKeyDirection>.empty();
    }
    _volumeController ??= StreamController<VolumeKeyDirection>.broadcast(
      onListen: _startListeningVolumeEvents,
      onCancel: _stopListeningVolumeEvents,
    );
    return _volumeController!.stream;
  }

  void _startListeningVolumeEvents() {
    if (_disposed || _eventSubscription != null) return;
    _eventSubscription = _volumeEventChannel.receiveBroadcastStream().listen(
      (dynamic event) {
        if (_disposed) return;
        if (event == 'up') {
          _volumeController?.add(VolumeKeyDirection.up);
        } else if (event == 'down') {
          _volumeController?.add(VolumeKeyDirection.down);
        }
      },
      onError: (Object error, StackTrace stackTrace) {
        if (error is MissingPluginException) {
          return;
        }
        _volumeController?.addError(error, stackTrace);
      },
    );
  }

  Future<void> _stopListeningVolumeEvents() async {
    await _eventSubscription?.cancel();
    _eventSubscription = null;
  }

  @override
  Future<void> setImmersiveMode(bool enabled) async {
    try {
      await _methodChannel.invokeMethod<void>(
        'setImmersiveMode',
        <String, Object>{'enabled': enabled},
      );
    } on MissingPluginException {
      // Headless tests can safely ignore.
    }
  }

  @override
  Future<void> bossKeyHide() async {
    try {
      await _methodChannel.invokeMethod<void>('bossKeyHide');
    } on MissingPluginException {
      // Headless tests can safely ignore.
    }
  }

  /// Releases the underlying EventChannel subscription and stream controller.
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await _stopListeningVolumeEvents();
    await _volumeController?.close();
    _volumeController = null;
  }
}
