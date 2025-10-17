import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_marker_cluster/flutter_map_marker_cluster.dart';
import 'package:flutter_map_tile_caching/flutter_map_tile_caching.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import 'package:my_app_gps/core/diagnostics/rebuild_tracker.dart';
import 'package:my_app_gps/core/map/marker_layer_cache.dart';
import 'package:my_app_gps/core/utils/timing.dart';
import 'package:my_app_gps/features/map/core/map_adapter.dart';
import 'package:my_app_gps/features/map/view/map_marker.dart';

class FlutterMapAdapter extends StatefulWidget implements MapAdapter {
  const FlutterMapAdapter({
    required this.markers,
    required this.cameraFit,
    super.key,
    this.onMarkerTap,
    this.onMapTap,
    this.tileProvider,
    this.markersNotifier, // OPTIMIZATION: Use ValueNotifier for efficient marker updates
  });

  final TileProvider? tileProvider;

  final List<MapMarkerData> markers;
  final MapCameraFit cameraFit;
  final void Function(String markerId)? onMarkerTap;
  final VoidCallback? onMapTap;

  // OPTIMIZATION: When provided, use ValueListenableBuilder for marker layer
  // This keeps FlutterMap itself static and only rebuilds markers
  final ValueNotifier<List<MapMarkerData>>? markersNotifier;

  @override
  State<FlutterMapAdapter> createState() => FlutterMapAdapterState();
}

class FlutterMapAdapterState extends State<FlutterMapAdapter>
    with TickerProviderStateMixin {
  final mapController = MapController();
  final _moveThrottler = Throttler(const Duration(milliseconds: 300));
  // Toggle to force-disable FMTC for troubleshooting
  static const bool kForceDisableFMTC =
      false; // enable FMTC by default; set to true only for troubleshooting
  // Test helper: when true, don't load any remote tiles to avoid HTTP errors in widget tests
  static bool kDisableTilesForTests = false;

  @override
  void didUpdateWidget(covariant FlutterMapAdapter oldWidget) {
    super.didUpdateWidget(oldWidget);
    _maybeFit();
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeFit());
  }

  @override
  void dispose() {
    mapController.dispose();
    super.dispose();
  }

  void _maybeFit() {
    final fit = widget.cameraFit;
    if (fit.boundsPoints != null && fit.boundsPoints!.isNotEmpty) {
      final bounds = LatLngBounds.fromPoints(fit.boundsPoints!);
      final center = bounds.center;
      final zoom = fitZoomForBounds(bounds, paddingFactor: 1.15);
      _moveThrottler.run(() => _animatedMove(center, zoom));
    } else if (fit.center != null) {
      _moveThrottler
          .run(() => _animatedMove(fit.center!, mapController.camera.zoom));
    }
  }

  double fitZoomForBounds(LatLngBounds b, {double paddingFactor = 1.0}) {
    // Very naive fit; refine later with size info & padding.
    final latDiff = (b.north - b.south).abs().clamp(0.0001, 180.0);
    final lngDiff = (b.east - b.west).abs().clamp(0.0001, 360.0);
    final maxDiff = latDiff > lngDiff ? latDiff : lngDiff;
    double base;
    if (maxDiff < 0.01) {
      base = 16;
    } else if (maxDiff < 0.05) {
      base = 14;
    } else if (maxDiff < 0.1) {
      base = 13;
    } else if (maxDiff < 0.5) {
      base = 11;
    } else if (maxDiff < 1) {
      base = 10;
    } else if (maxDiff < 5) {
      base = 8;
    } else {
      base = 4;
    }
    // Apply padding factor (zoom out slightly >1.0)
    return base - (paddingFactor > 1.02 ? 1 : 0);
  }

  // Public method (access via GlobalKey) to move camera immediately to a specific point.
  // This is used for device selection and needs to be FAST (<100ms)
  void moveTo(LatLng target, {double zoom = 16, bool immediate = true}) {
    if (immediate) {
      // Immediate camera move without throttling - for user selection
      _animatedMove(target, zoom);
    } else {
      // Throttled move - for automatic fits
      _moveThrottler.run(() => _animatedMove(target, zoom));
    }
  }

  void _animatedMove(LatLng dest, double zoom) {
    // Use flutter_map's built-in animated move for smooth transitions
    // Duration optimized for <100ms total response time
    mapController.move(dest, zoom);

    // Note: flutter_map 6.x doesn't have smooth animations built-in.
    // We rely on the map widget's internal interpolation.
    // The actual move is synchronous and fast.
  }

  bool _validLatLng(LatLng? point) {
    if (point == null) return false;
    if (point.latitude.isNaN || point.longitude.isNaN) return false;
    return point.latitude.abs() <= 90 && point.longitude.abs() <= 180;
  }

  // Helper to build marker cluster layer with caching
  Widget _buildMarkerLayer(List<MapMarkerData> validMarkers) {
    // PERFORMANCE: Track marker layer rebuilds (should be ONLY when positions change)
    if (kDebugMode) {
      RebuildTracker.instance.trackRebuild('MarkerLayer');
    }

    // Use cached marker layer options to avoid rebuilding identical layers
    final cachedMarkers =
        MarkerLayerOptionsCache.instance.getCachedMarkers(validMarkers);

    return MarkerClusterLayerWidget(
      options: MarkerClusterLayerOptions(
        maxClusterRadius: 45,
        size: const Size(36, 36),
        // Reuse cached markers if available to preserve widget identity
        markers: cachedMarkers ??
            [
              for (final m in validMarkers)
                Marker(
                  key: ValueKey('marker_${m.id}_${m.isSelected}'),
                  point: m.position,
                  width: 32,
                  height: 32,
                  child: Consumer(
                    builder: (context, ref, _) {
                      return GestureDetector(
                        key: ValueKey('tap_${m.id}'),
                        onTap: () => widget.onMarkerTap?.call(m.id),
                        child: MapMarkerWidget(
                          deviceId: int.tryParse(m.id) ?? -1,
                          isSelected: m.isSelected,
                          key:
                              ValueKey('marker_widget_${m.id}_${m.isSelected}'),
                        ),
                      );
                    },
                  ),
                ),
            ],
        builder: (context, markers) {
          return Container(
            decoration: BoxDecoration(
              color: Colors.blue.withValues(alpha: 0.8),
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: Text(
              markers.length.toString(),
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // PERFORMANCE: Track FlutterMap widget rebuilds (should be ZERO with ValueNotifier!)
    if (kDebugMode) {
      RebuildTracker.instance.trackRebuild('FlutterMapAdapter');
    }

    // Choose tile provider (only if tiles enabled)
    TileProvider? tileProvider;
    if (widget.tileProvider != null) {
      tileProvider = widget.tileProvider;
    } else if (!kDisableTilesForTests) {
      if (kForceDisableFMTC) {
        tileProvider = NetworkTileProvider();
      } else {
        try {
          tileProvider = FMTCTileProvider(stores: const {'main': null});
        } catch (e) {
          tileProvider = NetworkTileProvider();
        }
      }
    }

    // OPTIMIZATION: Wrap FlutterMap in RepaintBoundary to isolate render pipeline
    // This prevents map tiles from repainting when markers update
    return RepaintBoundary(
      child: FlutterMap(
        mapController: mapController,
        options: MapOptions(
          initialCenter: const LatLng(0, 0),
          initialZoom: 2,
          onTap: (_, __) => widget.onMapTap?.call(),
        ),
        children: [
          if (!kDisableTilesForTests)
            TileLayer(
              // Use canonical single-host URL per OSM operations guidance (avoid {s} subdomains).
              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'com.example.my_app_gps',
              maxZoom: 19,
              // Requirement: TileLayer uses FMTC provider by default
              tileProvider: tileProvider,
            ),
          // Defensive: only build cluster layer when we have valid markers
          // OPTIMIZATION: Use ValueListenableBuilder to rebuild only markers, not entire map
          if (widget.markersNotifier != null)
            ValueListenableBuilder<List<MapMarkerData>>(
              valueListenable: widget.markersNotifier!,
              builder: (ctx, markers, _) {
                final validMarkers = markers
                    .where((m) => _validLatLng(m.position))
                    .toList(growable: false);
                if (validMarkers.isEmpty) {
                  debugPrint(
                    '[MAP] Skipping cluster render – no valid markers yet',
                  );
                  return const SizedBox.shrink();
                }
                return _buildMarkerLayer(validMarkers);
              },
            )
          else
            Builder(
              builder: (ctx) {
                final validMarkers = widget.markers
                    .where((m) => _validLatLng(m.position))
                    .toList(growable: false);
                if (validMarkers.isEmpty) {
                  debugPrint(
                    '[MAP] Skipping cluster render – no valid markers yet',
                  );
                  return const SizedBox.shrink();
                }
                return _buildMarkerLayer(validMarkers);
              },
            ),
          Positioned(
            right: 8,
            bottom: 8,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Text(
                '© OpenStreetMap contributors',
                style: TextStyle(color: Colors.white, fontSize: 11),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// Marker icon visuals moved to MapMarkerWidget to support per-marker rebuild isolation.
