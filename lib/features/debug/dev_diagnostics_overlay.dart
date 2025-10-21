import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:my_app_gps/core/diagnostics/dev_diagnostics.dart';
import 'package:my_app_gps/core/diagnostics/rebuild_tracker.dart';

/// A compact overlay that shows live debug counters.
/// Only visible in debug mode.
class DevDiagnosticsOverlay extends StatefulWidget {
  const DevDiagnosticsOverlay({required this.child, super.key});
  final Widget child;

  @override
  State<DevDiagnosticsOverlay> createState() => _DevDiagnosticsOverlayState();
}

class _DevDiagnosticsOverlayState extends State<DevDiagnosticsOverlay> {
  @override
  void initState() {
    super.initState();
    if (kDebugMode) {
      // Ensure diagnostics is started
      // Accessing instance triggers start in debug
      // ignore: unnecessary_statements
      DevDiagnostics.instance;
      // Start rebuild tracker as well
      RebuildTracker.instance.start();
    }
  }

  @override
  void dispose() {
    if (kDebugMode) {
      DevDiagnostics.instance.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!kDebugMode) return widget.child;
    final diag = DevDiagnostics.instance;
    return Stack(
      children: [
        widget.child,
        Positioned(
          right: 8,
          top: 8,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.65),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.white24),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              child: DefaultTextStyle(
                style: const TextStyle(color: Colors.white, fontSize: 11, height: 1.2),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        ValueListenableBuilder<int>(
                          valueListenable: diag.wsReconnects,
                          builder: (_, v, __) => Text('WS: $v'),
                        ),
                        const SizedBox(width: 10),
                        ValueListenableBuilder<int>(
                          valueListenable: diag.backfillRequests,
                          builder: (_, v, __) => Text('Backfill req: $v'),
                        ),
                        const SizedBox(width: 10),
                        ValueListenableBuilder<int>(
                          valueListenable: diag.backfillAppliedEvents,
                          builder: (_, v, __) => Text('Applied: $v'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        ValueListenableBuilder<int>(
                          valueListenable: diag.dedupSkipped,
                          builder: (_, v, __) => Text('Dedup skip: $v'),
                        ),
                        const SizedBox(width: 10),
                        ValueListenableBuilder<double>(
                          valueListenable: diag.pingLatencyMs,
                          builder: (_, v, __) => Text('Ping: ${v.toStringAsFixed(1)}ms'),
                        ),
                        const SizedBox(width: 10),
                        ValueListenableBuilder<int>(
                          valueListenable: diag.clusterComputeMs,
                          builder: (_, v, __) => Text('Cluster: ${v}ms'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        ValueListenableBuilder<double>(
                          valueListenable: diag.markerBuildsPerSec,
                          builder: (_, v, __) => Text('Markers/s: ${v.toStringAsFixed(1)}'),
                        ),
                        const SizedBox(width: 10),
                        ValueListenableBuilder<double>(
                          valueListenable: diag.fps,
                          builder: (_, v, __) {
                            final color = v < 45 ? Colors.redAccent : Colors.greenAccent;
                            return Text('FPS: ${v.toStringAsFixed(0)}', style: TextStyle(color: color));
                          },
                        ),
                        const SizedBox(width: 10),
                        Builder(
                          builder: (_) {
                            final total = RebuildTracker.instance.getAllCounts().values
                                .fold<int>(0, (a, b) => a + b);
                            return Text('Rebuilds: $total');
                          },
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
