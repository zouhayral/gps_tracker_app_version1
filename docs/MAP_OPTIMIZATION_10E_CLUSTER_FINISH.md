# Prompt 10E – Cluster Engine Finishing Pass

This document describes the finishing changes applied to the adaptive clustering subsystem to achieve production-grade performance, UX, and observability.

## Highlights

- Isolate-driven compute for large datasets (>= 800 markers) with 250ms timeout fallback.
- Badge bitmap caching with small LRU to prevent redundant paints and reduce CPU usage.
- Optional spiderfy overlay for small clusters (<= 5 members) to improve tap interaction.
- Telemetry published via Riverpod for future Diagnostics HUD integration.

## Files Added/Updated

- lib/features/map/clustering/cluster_isolate.dart — isolate worker and API
- lib/features/map/clustering/cluster_badge_cache.dart — in-memory PNG cache with hit-rate
- lib/features/map/clustering/spiderfy_overlay.dart — animated radial expansion overlay
- lib/features/map/clustering/cluster_provider.dart — isolate orchestration, timeout, telemetry
- lib/features/map/clustering/cluster_marker_generator.dart — cache integration and hit counting

## Integration Notes

- Use clusterProvider as before; computation path auto-selects isolate for >= 800 markers.
- Access telemetry with clusterTelemetryProvider for rendering in a Diagnostics HUD.
- Use SpiderfyOverlay.show(context, center: cluster.position, members: cluster.members) for small clusters on tap.

## Benchmarks (expected)

- 1,000 markers: < 10ms
- 2,000 markers: < 18ms
- ~70% fewer badge paints on repeated zoom/pan scenarios

## Next Steps

- Wire spiderfy overlay positioning to map screen coordinates.
- Expand cache keying if visual styles become theme-dependent.
- Add integration tests covering cache and isolate timeout fallback.
