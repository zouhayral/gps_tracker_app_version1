import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:my_app_gps/features/map/clustering/cluster_provider.dart';

/// Lightweight diagnostics HUD showing clustering telemetry.
class ClusterHud extends ConsumerWidget {
  const ClusterHud({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final telemetry = ref.watch(clusterTelemetryProvider);
    if (telemetry == null) return const SizedBox.shrink();

    final usedIso = telemetry.usedIsolate ? 'iso' : 'sync';
    final hitRate = (telemetry.cacheHitRate * 100).toStringAsFixed(0);

    // OPTIMIZATION (Phase 1, Step 2): Wrap HUD in RepaintBoundary
    // Benefits: Isolates telemetry overlay from map repaints
    // - HUD updates ~1/sec but map can pan/zoom 60fps
    // - Prevents HUD from triggering repaints during map interaction
    // - Lightweight widget but good practice for all overlays
    return RepaintBoundary(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.6),
          borderRadius: BorderRadius.circular(6),
        ),
        child: DefaultTextStyle(
          style: const TextStyle(color: Colors.white, fontSize: 11),
          child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.blur_circular, color: Colors.white, size: 14),
            const SizedBox(width: 6),
            Text('${telemetry.markerCount} pts'),
            const SizedBox(width: 8),
            Text('${telemetry.clusterCount} cls'),
            const SizedBox(width: 8),
            Text('${telemetry.computeTimeMs} ms'),
            const SizedBox(width: 8),
            Text(usedIso),
            const SizedBox(width: 8),
            Text('badge $hitRate%'),
          ],
        ),
      ),
    ),  // Close Container
    );  // Close RepaintBoundary
  }
}
