import '../failures/app_failure.dart';

/// Pure-Dart cooperative cancellation token for long-running provider and
/// preloading tasks.
class CancellationToken {
  bool _isCancelled = false;
  final List<void Function()> _listeners = [];

  bool get isCancelled => _isCancelled;

  /// Marks this token as cancelled and notifies registered listeners once.
  void cancel() {
    if (_isCancelled) return;
    _isCancelled = true;
    final snapshot = List<void Function()>.of(_listeners);
    _listeners.clear();
    for (final listener in snapshot) {
      listener();
    }
  }

  /// Throws [CancelledFailure] if cancellation has already been requested.
  void throwIfCancelled() {
    if (_isCancelled) {
      throw const CancelledFailure();
    }
  }

  /// Registers a callback invoked when [cancel] is called.
  void addListener(void Function() listener) {
    if (_isCancelled) {
      listener();
      return;
    }
    _listeners.add(listener);
  }

  /// Removes a previously registered listener.
  void removeListener(void Function() listener) {
    _listeners.remove(listener);
  }

  /// Clears remaining listeners when the associated operation completes.
  void dispose() {
    _listeners.clear();
  }
}
