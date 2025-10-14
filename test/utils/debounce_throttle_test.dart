
import 'package:flutter_test/flutter_test.dart';
import 'package:my_app_gps/core/utils/timing.dart';

void main() {
  group('Debouncer', () {
    test('runs only once after delay despite rapid calls', () async {
      final debouncer = Debouncer(const Duration(milliseconds: 100));
      var count = 0;
      for (var i = 0; i < 5; i++) {
        debouncer.run(() => count++);
      }
      // Immediately after, nothing should have run
      expect(count, 0);
      // Wait a bit longer than the delay
      await Future<void>.delayed(const Duration(milliseconds: 130));
      expect(count, 1);
    });

    test('cancel prevents pending callback from firing', () async {
      final debouncer = Debouncer(const Duration(milliseconds: 100));
      var count = 0;
      debouncer.run(() => count++);
      debouncer.cancel();
      await Future<void>.delayed(const Duration(milliseconds: 130));
      expect(count, 0);
    });
  });

  group('Throttler', () {
    test('runs at most once within the throttle window', () async {
      final throttler = Throttler(const Duration(milliseconds: 150));
      var count = 0;
      for (var i = 0; i < 5; i++) {
        throttler.run(() => count++);
      }
      // Should have run only once immediately
      expect(count, 1);
      // After the window passes, next call should run
      await Future<void>.delayed(const Duration(milliseconds: 170));
      throttler.run(() => count++);
      expect(count, 2);
    });
  });
}
