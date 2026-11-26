import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pureread/application/core_providers.dart';
import 'package:pureread/application/reader/auto_read_controller.dart';
import 'package:pureread/application/reader/auto_read_state.dart';
import 'package:pureread/application/reader/reader_theme_x.dart';
import 'package:pureread/domain/domain.dart';

class _FakeThemeRepo implements ThemeRepository {
  final Map<String, ReaderTheme> themes = <String, ReaderTheme>{
    for (final t in buildDefaultReaderThemes()) t.id: t,
  };
  final Map<String, AppSetting> settings = <String, AppSetting>{};
  bool throwOnGet = false;
  bool throwOnSave = false;

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
  Future<AppSetting?> getSetting(String key) async {
    if (throwOnGet) {
      throw StateError('storage read failed');
    }
    return settings[key];
  }

  @override
  Future<List<AppSetting>> listSettings() async =>
      settings.values.toList(growable: false);

  @override
  Future<void> saveSetting(AppSetting setting) async {
    if (throwOnSave) {
      throw StateError('storage write failed');
    }
    settings[setting.key] = setting;
  }
}

void main() {
  group('AutoReadController', () {
    late _FakeThemeRepo themeRepo;

    setUp(() {
      themeRepo = _FakeThemeRepo();
    });

    ProviderContainer createContainer() {
      return ProviderContainer(
        overrides: [
          themeRepositoryProvider.overrideWithValue(themeRepo),
        ],
      );
    }

    test('exposes expected defaults and derived getters', () {
      final container = createContainer();
      addTearDown(container.dispose);

      final state = container.read(autoReadControllerProvider);
      expect(state.mode, AutoReadMode.curtain);
      expect(state.status, AutoReadStatus.idle);
      expect(state.curtainSeconds, 18);
      expect(state.turnSeconds, 12);
      expect(state.showControls, isTrue);
      expect(state.isActive, isFalse);
      expect(state.isRunning, isFalse);
      expect(state.isPaused, isFalse);
      expect(state.activeDuration, const Duration(seconds: 18));
    });

    test('loads persisted settings and clamps invalid or out-of-range values', () async {
      final now = DateTime.utc(2026, 11, 25);
      themeRepo.settings['auto_read_mode'] = AppSetting(
        key: 'auto_read_mode',
        value: 'timedTurn',
        updatedAt: now,
      );
      themeRepo.settings['auto_read_curtain_seconds'] = AppSetting(
        key: 'auto_read_curtain_seconds',
        value: '99',
        updatedAt: now,
      );
      themeRepo.settings['auto_read_turn_seconds'] = AppSetting(
        key: 'auto_read_turn_seconds',
        value: '1',
        updatedAt: now,
      );

      final container = createContainer();
      addTearDown(container.dispose);

      final controller = container.read(autoReadControllerProvider.notifier);
      await controller.loadSettings();

      var state = container.read(autoReadControllerProvider);
      expect(state.mode, AutoReadMode.timedTurn);
      expect(state.curtainSeconds, 60);
      expect(state.turnSeconds, 3);
      expect(state.activeDuration, const Duration(seconds: 3));

      themeRepo.settings['auto_read_mode'] = AppSetting(
        key: 'auto_read_mode',
        value: 'invalid_mode',
        updatedAt: now,
      );
      themeRepo.settings['auto_read_curtain_seconds'] = AppSetting(
        key: 'auto_read_curtain_seconds',
        value: 'not_a_number',
        updatedAt: now,
      );
      await controller.loadSettings();

      state = container.read(autoReadControllerProvider);
      expect(state.mode, AutoReadMode.timedTurn);
      expect(state.curtainSeconds, 60);
    });

    test('manages start, pause, resume, togglePause, stop, and controls visibility', () async {
      final container = createContainer();
      addTearDown(container.dispose);

      final controller = container.read(autoReadControllerProvider.notifier);

      // Pause/resume/togglePause are ignored while idle.
      controller.pause();
      controller.resume();
      controller.togglePause();
      expect(
        container.read(autoReadControllerProvider).status,
        AutoReadStatus.idle,
      );

      controller.start();
      var state = container.read(autoReadControllerProvider);
      expect(state.isActive, isTrue);
      expect(state.isRunning, isTrue);
      expect(state.isPaused, isFalse);
      expect(state.mode, AutoReadMode.curtain);

      controller.toggleControls();
      expect(container.read(autoReadControllerProvider).showControls, isFalse);
      controller.setControlsVisible(true);
      expect(container.read(autoReadControllerProvider).showControls, isTrue);

      controller.togglePause();
      state = container.read(autoReadControllerProvider);
      expect(state.isActive, isTrue);
      expect(state.isRunning, isFalse);
      expect(state.isPaused, isTrue);

      controller.togglePause();
      state = container.read(autoReadControllerProvider);
      expect(state.isRunning, isTrue);

      controller.pause();
      expect(container.read(autoReadControllerProvider).isPaused, isTrue);
      controller.resume();
      expect(container.read(autoReadControllerProvider).isRunning, isTrue);

      controller.setControlsVisible(false);
      controller.stop();
      state = container.read(autoReadControllerProvider);
      expect(state.status, AutoReadStatus.idle);
      expect(state.isActive, isFalse);
      expect(state.showControls, isTrue);

      controller.start(mode: AutoReadMode.timedTurn);
      await Future<void>.delayed(Duration.zero);
      state = container.read(autoReadControllerProvider);
      expect(state.mode, AutoReadMode.timedTurn);
      expect(state.isRunning, isTrue);
      expect(themeRepo.settings['auto_read_mode']?.value, 'timedTurn');
    });

    test('persists mode and clamped speeds across containers via themeRepositoryProvider', () async {
      final container1 = createContainer();
      final controller1 = container1.read(autoReadControllerProvider.notifier);

      await controller1.setMode(AutoReadMode.timedTurn);
      await controller1.setCurtainSeconds(4); // clamps to 6
      await controller1.setTurnSeconds(75); // clamps to 60

      var state1 = container1.read(autoReadControllerProvider);
      expect(state1.mode, AutoReadMode.timedTurn);
      expect(state1.curtainSeconds, 6);
      expect(state1.turnSeconds, 60);
      expect(state1.activeDuration, const Duration(seconds: 60));

      await controller1.setCurtainSeconds(24);
      await controller1.setTurnSeconds(9);
      await controller1.setMode(AutoReadMode.curtain);
      state1 = container1.read(autoReadControllerProvider);
      expect(state1.activeDuration, const Duration(seconds: 24));

      expect(themeRepo.settings['auto_read_mode']?.value, 'curtain');
      expect(themeRepo.settings['auto_read_curtain_seconds']?.value, '24');
      expect(themeRepo.settings['auto_read_turn_seconds']?.value, '9');
      container1.dispose();

      final container2 = createContainer();
      addTearDown(container2.dispose);
      await container2
          .read(autoReadControllerProvider.notifier)
          .loadSettings();

      final restored = container2.read(autoReadControllerProvider);
      expect(restored.mode, AutoReadMode.curtain);
      expect(restored.curtainSeconds, 24);
      expect(restored.turnSeconds, 9);
      expect(restored.status, AutoReadStatus.idle);
    });

    test('does not let initial microtask load clobber synchronous start or edits', () async {
      final now = DateTime.utc(2026, 11, 25);
      themeRepo.settings['auto_read_mode'] = AppSetting(
        key: 'auto_read_mode',
        value: 'curtain',
        updatedAt: now,
      );
      themeRepo.settings['auto_read_curtain_seconds'] = AppSetting(
        key: 'auto_read_curtain_seconds',
        value: '30',
        updatedAt: now,
      );

      final container = createContainer();
      addTearDown(container.dispose);

      final controller = container.read(autoReadControllerProvider.notifier);
      controller.start(mode: AutoReadMode.timedTurn);
      await controller.setCurtainSeconds(15);

      await Future<void>.delayed(Duration.zero);

      final state = container.read(autoReadControllerProvider);
      expect(state.status, AutoReadStatus.running);
      expect(state.mode, AutoReadMode.timedTurn);
      expect(state.curtainSeconds, 15);
    });

    test('handles repository read/write failures gracefully', () async {
      themeRepo.throwOnGet = true;
      themeRepo.throwOnSave = true;

      final container = createContainer();
      addTearDown(container.dispose);

      final controller = container.read(autoReadControllerProvider.notifier);
      await controller.loadSettings();
      await controller.setMode(AutoReadMode.timedTurn);
      await controller.setCurtainSeconds(22);
      await controller.setTurnSeconds(10);

      final state = container.read(autoReadControllerProvider);
      expect(state.mode, AutoReadMode.timedTurn);
      expect(state.curtainSeconds, 22);
      expect(state.turnSeconds, 10);
    });
  });
}
