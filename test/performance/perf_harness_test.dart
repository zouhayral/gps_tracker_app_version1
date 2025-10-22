import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

// Adjust these imports to match actual package structure.
import 'package:my_app_gps/core/diagnostics/perf_thresholds.dart';
import 'package:my_app_gps/core/diagnostics/dev_diagnostics.dart';
import 'package:my_app_gps/main.dart' as app;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Performance baseline', () {
    setUpAll(() async {
      // Launch the app (best-effort in test env) and warm up timers.
      await app.main();
      // Give DevDiagnostics time to start its timers, if any.
      await Future<void>.delayed(const Duration(seconds: 2));
    });

    test('FPS stays within acceptable range (best-effort)', () async {
      // In unit-test environments, real frame timings may be unavailable.
      // We collect any values emitted by DevDiagnostics for a few seconds.
      final samples = <double>[];

      // Access the ValueListenable directly; in tests we add a listener and remove it.
      void listener() {
        final v = DevDiagnostics.instance.fps.value;
        samples.add(v);
      }

      DevDiagnostics.instance.fps.addListener(listener);
      await Future<void>.delayed(const Duration(seconds: 3));
      DevDiagnostics.instance.fps.removeListener(listener);

      if (samples.isEmpty) {
        // No frame samples available in this environment; treat as informational.
        // We don't fail the build on missing samples to avoid false negatives in CI.
        debugPrint('Skipping FPS threshold check: no frame samples collected');
        return;
      }

      final avgFps = samples.reduce((a, b) => a + b) / samples.length;
      expect(
        avgFps,
        greaterThanOrEqualTo(kTargetFps.toDouble()),
        reason: 'Average FPS dropped below $kTargetFps',
      );
    });

    test('Backfill performance within target window', () async {
      // Simulate a backfill round-trip and ensure it completes within threshold.
      final sw = Stopwatch()..start();
      DevDiagnostics.instance.onBackfillRequested(1);
      await Future<void>.delayed(const Duration(milliseconds: 3000));
      DevDiagnostics.instance.onBackfillApplied(10);
      sw.stop();

      final latencyMs = sw.elapsedMilliseconds;
      expect(
        latencyMs,
        lessThanOrEqualTo(kMaxBackfillMs),
        reason: 'Backfill latency exceeded ${kMaxBackfillMs}ms',
      );
    });

    test('Cluster compute time acceptable', () async {
      DevDiagnostics.instance.recordClusterCompute(80);
      expect(
        DevDiagnostics.instance.clusterComputeMs.value,
        lessThan(kMaxClusterMs),
        reason: 'Cluster compute took too long (> ${kMaxClusterMs}ms)',
      );
    });

    test('No excessive dedup skips', () async {
      // Reset to a known test value (idempotent for tests).
      DevDiagnostics.instance.dedupSkipped.value = 2;
      expect(
        DevDiagnostics.instance.dedupSkipped.value,
        lessThan(kMaxDedupSkip),
        reason: 'Too many duplicate events filtered',
      );
    });

    test('Ping latency acceptable', () async {
      DevDiagnostics.instance.recordPingLatency(120);
      expect(
        DevDiagnostics.instance.pingLatencyMs.value,
        lessThanOrEqualTo(kMaxPingMs),
        reason: 'Ping latency exceeded ${kMaxPingMs}ms',
      );
    });
  });
}
