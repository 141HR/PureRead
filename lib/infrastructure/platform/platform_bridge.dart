/// Hardware volume key press direction emitted on Android when volume-key
/// paging is active.
enum VolumeKeyDirection { up, down }

/// Zero-plugin native platform abstraction for file picking, screen keep-awake,
/// Android hardware volume-key paging, immersive fullscreen, and boss-key hide.
abstract interface class PlatformBridge {
  /// Opens a native file picker filtered by lowercase [extensions] (e.g.
  /// `['txt']` or `['ttf', 'otf']`), returning readable local file paths.
  /// Returns an empty list if the user cancels.
  Future<List<String>> pickFiles({
    required List<String> extensions,
    bool allowMultiple = false,
  });

  /// Keeps the device screen awake while reading when [enabled] is true.
  Future<void> setKeepScreenOn(bool enabled);

  /// Enables or disables intercepting hardware volume keys on Android.
  Future<void> setVolumeKeyPaging(bool enabled);

  /// Broadcast stream of intercepted volume key events (`up` / `down`).
  Stream<VolumeKeyDirection> get volumeKeyEvents;

  /// Toggles immersive fullscreen (Android system bars / Windows borderless).
  Future<void> setImmersiveMode(bool enabled);

  /// Immediately minimizes or hides the application window (boss key).
  Future<void> bossKeyHide();
}
