import 'dart:async';

/// Simple debouncer: schedules the action after [delay].
/// Repeated calls within the delay reset the timer.
class Debouncer {
  Debouncer(this.delay);
  final Duration delay;
  Timer? _timer;

  void run(void Function() action) {
    _timer?.cancel();
    _timer = Timer(delay, action);
  }

  void cancel() => _timer?.cancel();
}

/// Simple throttler: runs the action at most once within [delay].
class Throttler {
  Throttler(this.delay);
  final Duration delay;
  DateTime? _lastRun;

  void run(void Function() action) {
    final now = DateTime.now();
    if (_lastRun == null || now.difference(_lastRun!) > delay) {
      _lastRun = now;
      action();
    }
  }
}
