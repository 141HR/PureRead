import 'dart:async';

import 'package:flutter/services.dart';

import 'tts_engine.dart';

/// MethodChannel / EventChannel implementation of [TtsEngine] communicating
/// with Android (`TextToSpeech` + `TtsPlaybackService`) and Windows (SAPI 5 /
/// OneCore COM) over `com.pureread.app/tts`.
class MethodChannelTtsEngine implements TtsEngine {
  static const String channelName = 'com.pureread.app/tts';
  static const String eventsChannelName = 'com.pureread.app/tts/events';

  MethodChannelTtsEngine({
    MethodChannel? methodChannel,
    EventChannel? eventChannel,
  }) : _methodChannel = methodChannel ?? const MethodChannel(channelName),
       _eventChannel = eventChannel ?? const EventChannel(eventsChannelName);

  final MethodChannel _methodChannel;
  final EventChannel _eventChannel;

  StreamController<TtsEvent>? _eventsController;
  StreamSubscription<dynamic>? _eventSubscription;
  bool _disposed = false;

  @override
  Future<TtsInitResult> initialize() async {
    try {
      final result = await _methodChannel.invokeMapMethod<String, dynamic>(
        'initialize',
      );
      if (result == null) {
        return const TtsInitResult(
          available: false,
          error: '系统 TTS 初始化无响应',
        );
      }
      return TtsInitResult(
        available: result['available'] == true,
        engine: result['engine']?.toString(),
        error: result['error']?.toString(),
      );
    } on MissingPluginException {
      return const TtsInitResult(
        available: false,
        error: '当前平台未注册系统朗读服务',
      );
    } on PlatformException catch (error) {
      return TtsInitResult(
        available: false,
        error: error.message ?? error.code,
      );
    }
  }

  @override
  Future<List<TtsEngineInfo>> getEngines() async {
    try {
      final rawList = await _methodChannel.invokeListMethod<dynamic>(
        'getEngines',
      );
      if (rawList == null) return const <TtsEngineInfo>[];
      final engines = <TtsEngineInfo>[];
      for (final item in rawList) {
        if (item is! Map<Object?, Object?>) continue;
        final id = item['id']?.toString() ?? '';
        if (id.isEmpty) continue;
        final label = item['label']?.toString() ?? id;
        final isDefault = item['isDefault'] == true;
        engines.add(
          TtsEngineInfo(id: id, label: label, isDefault: isDefault),
        );
      }
      return List<TtsEngineInfo>.unmodifiable(engines);
    } on MissingPluginException {
      return const <TtsEngineInfo>[];
    } on PlatformException {
      return const <TtsEngineInfo>[];
    }
  }

  @override
  Future<bool> setEngine(String engineId) async {
    try {
      final result = await _methodChannel.invokeMethod<bool>(
        'setEngine',
        <String, Object>{'engineId': engineId},
      );
      return result ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  @override
  Future<List<TtsVoiceInfo>> getVoices() async {
    try {
      final rawList = await _methodChannel.invokeListMethod<dynamic>(
        'getVoices',
      );
      if (rawList == null) return const <TtsVoiceInfo>[];
      final voices = <TtsVoiceInfo>[];
      for (final item in rawList) {
        if (item is! Map<Object?, Object?>) continue;
        final id = item['id']?.toString() ?? '';
        if (id.isEmpty) continue;
        final name = item['name']?.toString() ?? id;
        final locale = item['locale']?.toString() ?? '';
        voices.add(
          TtsVoiceInfo(id: id, name: name, locale: locale),
        );
      }
      return List<TtsVoiceInfo>.unmodifiable(voices);
    } on MissingPluginException {
      return const <TtsVoiceInfo>[];
    } on PlatformException {
      return const <TtsVoiceInfo>[];
    }
  }

  @override
  Future<bool> setVoice(String voiceId) async {
    try {
      final result = await _methodChannel.invokeMethod<bool>(
        'setVoice',
        <String, Object>{'voiceId': voiceId},
      );
      return result ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  @override
  Future<void> setSpeechRate(double rate) async {
    final clamped = rate.clamp(0.5, 2.5).toDouble();
    try {
      await _methodChannel.invokeMethod<void>(
        'setSpeechRate',
        <String, Object>{'rate': clamped},
      );
    } on MissingPluginException {
      // Headless tests or unsupported host platforms can safely ignore.
    }
  }

  @override
  Future<void> setPitch(double pitch) async {
    final clamped = pitch.clamp(0.5, 2.0).toDouble();
    try {
      await _methodChannel.invokeMethod<void>(
        'setPitch',
        <String, Object>{'pitch': clamped},
      );
    } on MissingPluginException {
      // Headless tests or unsupported host platforms can safely ignore.
    }
  }

  @override
  Future<bool> speak({
    required String text,
    required String utteranceId,
    String? bookTitle,
    String? chapterTitle,
  }) async {
    try {
      final result = await _methodChannel.invokeMethod<bool>(
        'speak',
        <String, Object>{
          'text': text,
          'utteranceId': utteranceId,
          'bookTitle': ?bookTitle,
          'chapterTitle': ?chapterTitle,
        },
      );
      return result ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  @override
  Future<void> stop() async {
    try {
      await _methodChannel.invokeMethod<void>('stop');
    } on MissingPluginException {
      // Headless tests can safely ignore.
    }
  }

  @override
  Future<void> pauseNotification({
    String? bookTitle,
    String? chapterTitle,
  }) async {
    try {
      await _methodChannel.invokeMethod<void>(
        'pauseNotification',
        <String, Object>{
          'bookTitle': ?bookTitle,
          'chapterTitle': ?chapterTitle,
        },
      );
    } on MissingPluginException {
      // Headless tests can safely ignore.
    }
  }

  @override
  Future<void> updateMetadata({
    String? bookTitle,
    String? chapterTitle,
    required bool isPlaying,
  }) async {
    try {
      await _methodChannel.invokeMethod<void>(
        'updateMetadata',
        <String, Object>{
          'bookTitle': ?bookTitle,
          'chapterTitle': ?chapterTitle,
          'isPlaying': isPlaying,
        },
      );
    } on MissingPluginException {
      // Headless tests can safely ignore.
    }
  }

  @override
  Future<void> shutdown() async {
    try {
      await _methodChannel.invokeMethod<void>('shutdown');
    } on MissingPluginException {
      // Headless tests can safely ignore.
    }
  }

  @override
  Stream<TtsEvent> get events {
    if (_disposed) {
      return const Stream<TtsEvent>.empty();
    }
    _eventsController ??= StreamController<TtsEvent>.broadcast(
      onListen: _startListeningEvents,
      onCancel: _stopListeningEvents,
    );
    return _eventsController!.stream;
  }

  void _startListeningEvents() {
    if (_disposed || _eventSubscription != null) return;
    _eventSubscription = _eventChannel.receiveBroadcastStream().listen(
      (dynamic rawEvent) {
        if (_disposed) return;
        final parsed = _parseEvent(rawEvent);
        if (parsed != null) {
          _eventsController?.add(parsed);
        }
      },
      onError: (Object error, StackTrace stackTrace) {
        if (error is MissingPluginException) {
          return;
        }
        _eventsController?.addError(error, stackTrace);
      },
    );
  }

  Future<void> _stopListeningEvents() async {
    await _eventSubscription?.cancel();
    _eventSubscription = null;
  }

  static TtsEvent? _parseEvent(dynamic rawEvent) {
    if (rawEvent is! Map<Object?, Object?>) return null;
    final type = rawEvent['type']?.toString();
    switch (type) {
      case 'start':
        final utteranceId = rawEvent['utteranceId']?.toString() ?? '';
        if (utteranceId.isEmpty) return null;
        return TtsStartEvent(utteranceId: utteranceId);
      case 'complete':
        final utteranceId = rawEvent['utteranceId']?.toString() ?? '';
        if (utteranceId.isEmpty) return null;
        return TtsCompleteEvent(utteranceId: utteranceId);
      case 'error':
        final utteranceId = rawEvent['utteranceId']?.toString();
        final message = rawEvent['message']?.toString() ?? '语音合成失败';
        return TtsErrorEvent(
          utteranceId: (utteranceId == null || utteranceId.isEmpty)
              ? null
              : utteranceId,
          message: message,
        );
      case 'progress':
        final utteranceId = rawEvent['utteranceId']?.toString() ?? '';
        final start = _asInt(rawEvent['start']);
        final end = _asInt(rawEvent['end']);
        if (utteranceId.isEmpty || start == null || end == null) return null;
        return TtsProgressEvent(
          utteranceId: utteranceId,
          start: start,
          end: end,
        );
      case 'mediaAction':
        final action = TtsMediaAction.fromWire(rawEvent['action']?.toString());
        if (action == null) return null;
        return TtsMediaActionEvent(action: action);
      default:
        return null;
    }
  }

  static int? _asInt(Object? raw) {
    if (raw is int) return raw;
    if (raw is num) return raw.toInt();
    if (raw is String) return int.tryParse(raw);
    return null;
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await _stopListeningEvents();
    await _eventsController?.close();
    _eventsController = null;
  }
}
