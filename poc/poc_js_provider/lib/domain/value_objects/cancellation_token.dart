import '../failures/app_failure.dart';

/// Pure-Dart cooperative cancellation token.
class CancellationToken {
  bool _isCancelled = false;
  final List<void Function()> _listeners = [];

  bool get isCancelled => _isCancelled;

  void cancel() {
    if (_isCancelled) return;
    _isCancelled = true;
    final snapshot = List<void Function()>.of(_listeners);
    _listeners.clear();
    for (final listener in snapshot) {
      listener();
    }
  }

  void throwIfCancelled() {
    if (_isCancelled) {
      throw const CancelledFailure();
    }
  }

  void addListener(void Function() listener) {
    if (_isCancelled) {
      listener();
      return;
    }
    _listeners.add(listener);
  }

  void removeListener(void Function() listener) {
    _listeners.remove(listener);
  }

  void dispose() {
    _listeners.clear();
  }
}
