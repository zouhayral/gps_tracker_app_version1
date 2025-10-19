import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_app_gps/core/map/marker_processing_isolate.dart';

void main() {
  group('MarkerProcessingIsolate', () {
    // Clean up after each test
    tearDown(MarkerProcessingIsolate.instance.dispose);

    test('handles double initialization safely', () async {
      final isolate = MarkerProcessingIsolate.instance;

      // First initialization should work
      await isolate.initialize();

      // Second initialization should skip gracefully
      expect(isolate.initialize, returnsNormally);

      // Dispose should work
      expect(isolate.dispose, returnsNormally);
    });

    test('can reinitialize after dispose', () async {
      final isolate = MarkerProcessingIsolate.instance;

      // Initialize
      await isolate.initialize();

      // Dispose
      isolate.dispose();

  // Should be able to initialize again
  expect(isolate.initialize, returnsNormally);

      // Clean up
      isolate.dispose();
    });

    test('multiple dispose calls are safe', () {
      final isolate = MarkerProcessingIsolate.instance;

      // Multiple dispose calls should not throw
      expect(isolate.dispose, returnsNormally);
      expect(isolate.dispose, returnsNormally);
      expect(isolate.dispose, returnsNormally);
    });

    test('logs "Already initialized, skipping" on double init', () async {
      final isolate = MarkerProcessingIsolate.instance;
      final logs = <String>[];

      // Capture debug prints
      debugPrint = (String? message, {int? wrapWidth}) {
        if (message != null) logs.add(message);
      };

      try {
        // First init
        await isolate.initialize();

        // Second init should log
        await isolate.initialize();

        // Verify the log message
        expect(
          logs.any((log) => log.contains('[ISOLATE] Already initialized')),
          isTrue,
          reason: 'Should log that isolate is already initialized',
        );
      } finally {
        // Restore default debugPrint
        debugPrint = debugPrintThrottled;
        isolate.dispose();
      }
    });

    test('full lifecycle: init -> dispose -> init -> dispose', () async {
      final isolate = MarkerProcessingIsolate.instance;

      // First lifecycle
      await isolate.initialize();
      isolate.dispose();

      // Second lifecycle
      await isolate.initialize();
      isolate.dispose();

      // Third lifecycle
      await isolate.initialize();
      isolate.dispose();

      // All should complete without errors
      expect(true, isTrue);
    });
  });
}
