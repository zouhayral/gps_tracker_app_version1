import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_marker_cluster/flutter_map_marker_cluster.dart';
import 'package:flutter_map_tile_caching/flutter_map_tile_caching.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/io_client.dart'; // IOClient for FMTC HTTP/1.1 compatibility
import 'package:latlong2/latlong.dart';

import 'package:my_app_gps/core/diagnostics/rebuild_tracker.dart';
import 'package:my_app_gps/core/map/marker_layer_cache.dart';
import 'package:my_app_gps/core/utils/timing.dart';
import 'package:my_app_gps/features/map/core/map_adapter.dart';
import 'package:my_app_gps/features/map/view/map_marker.dart';
import 'package:my_app_gps/map/map_tile_source_provider.dart';
import 'package:my_app_gps/map/tile_network_client.dart';

class FlutterMapAdapter extends ConsumerStatefulWidget implements MapAdapter {
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
  ConsumerState<FlutterMapAdapter> createState() => FlutterMapAdapterState();
}

class FlutterMapAdapterState extends ConsumerState<FlutterMapAdapter>
    with TickerProviderStateMixin {
  final mapController = MapController();
  final _moveThrottler = Throttler(const Duration(milliseconds: 300));
  // Toggle to force-disable FMTC for troubleshooting
  static const bool kForceDisableFMTC =
      false; // enable FMTC by default; set to true only for troubleshooting
  // Test helper: when true, don't load any remote tiles to avoid HTTP errors in widget tests
  static bool kDisableTilesForTests = false;
  
  // CRITICAL FIX: Dedicated HTTP/1.1 client for FMTC reliability
  // Uses TileNetworkClient helper for proper configuration:
  // - HTTP/1.1 protocol (prevents unknownFetchException)
  // - User-Agent for OpenStreetMap compliance
  // - Short timeouts for fast failure
  late final IOClient _httpClient;

  @override
  void didUpdateWidget(covariant FlutterMapAdapter oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Use throttled fit for subsequent updates to avoid rapid camera jumps
    _maybeFit(immediate: false);
  }

  @override
  void initState() {
    super.initState();
    // Initialize dedicated HTTP/1.1 client for reliable FMTC tile loading
    _httpClient = TileNetworkClient.create();
    // CRITICAL FIX: Initial camera fit must be IMMEDIATE to show selected devices
    // Without this, map shows (0,0) for 300ms+ while throttler delays the fit
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeFit(immediate: true));
  }

  @override
  void dispose() {
    _httpClient.close(); // Clean up HTTP client
    mapController.dispose();
    super.dispose();
  }

  void _maybeFit({bool immediate = false}) {
    final fit = widget.cameraFit;
    
    // DEFENSIVE: Filter out invalid points before camera fit
    if (fit.boundsPoints != null && fit.boundsPoints!.isNotEmpty) {
      final validPoints = fit.boundsPoints!.where(_validLatLng).toList();
      
      if (validPoints.isEmpty) {
        if (kDebugMode) {
          debugPrint('[FlutterMapAdapter] ⚠️ All bounds points are invalid (NaN/out of range)');
        }
        return; // Skip camera fit if no valid points
      }
      
      final bounds = LatLngBounds.fromPoints(validPoints);
      final center = bounds.center;
      
      // DEFENSIVE: Verify center is valid after bounds calculation
      if (!_validLatLng(center)) {
        if (kDebugMode) {
          debugPrint('[FlutterMapAdapter] ⚠️ Bounds center is invalid: $center');
        }
        return;
      }
      
      final zoom = fitZoomForBounds(bounds, paddingFactor: 1.15);
      
      // DEFENSIVE: Ensure zoom is finite
      if (!zoom.isFinite || zoom.isNaN) {
        if (kDebugMode) {
          debugPrint('[FlutterMapAdapter] ⚠️ Invalid zoom calculated: $zoom');
        }
        return;
      }
      
      if (immediate) {
        // Immediate camera move for initial load or user-triggered actions
        _animatedMove(center, zoom);
      } else {
        // Throttled move for automatic updates
        _moveThrottler.run(() => _animatedMove(center, zoom));
      }
    } else if (fit.center != null && _validLatLng(fit.center)) {
      // DEFENSIVE: Validate center before move
      if (immediate) {
        // Immediate camera move for initial load or user-triggered actions
        _animatedMove(fit.center!, mapController.camera.zoom);
      } else {
        // Throttled move for automatic updates
        _moveThrottler
            .run(() => _animatedMove(fit.center!, mapController.camera.zoom));
      }
    }
  }

  double fitZoomForBounds(LatLngBounds b, {double paddingFactor = 1.0}) {
    // DEFENSIVE: Verify bounds values are finite
    if (!b.north.isFinite || !b.south.isFinite || !b.east.isFinite || !b.west.isFinite) {
      if (kDebugMode) {
        debugPrint('[FlutterMapAdapter] ⚠️ Bounds contain non-finite values: $b');
      }
      return 13.0; // Return safe default zoom
    }
    
    // Very naive fit; refine later with size info & padding.
    final latDiff = (b.north - b.south).abs().clamp(0.0001, 180.0);
    final lngDiff = (b.east - b.west).abs().clamp(0.0001, 360.0);
    final maxDiff = latDiff > lngDiff ? latDiff : lngDiff;
    
    // DEFENSIVE: Ensure maxDiff is finite
    if (!maxDiff.isFinite || maxDiff.isNaN) {
      return 13.0; // Safe default
    }
    
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
    final result = base - (paddingFactor > 1.02 ? 1 : 0);
    
    // DEFENSIVE: Final safety check
    return result.isFinite ? result : 13.0;
  }

  // Public method (access via GlobalKey) to move camera immediately to a specific point.
  // This is used for device selection and needs to be FAST (<100ms)
  void moveTo(LatLng target, {double zoom = 16, bool immediate = true}) {
    // DEFENSIVE: Validate target coordinates
    if (!_validLatLng(target)) {
      if (kDebugMode) {
        debugPrint('[FlutterMapAdapter] ⚠️ Cannot move to invalid coordinates: $target');
      }
      return;
    }
    
    // DEFENSIVE: Validate zoom level
    if (!zoom.isFinite || zoom.isNaN || zoom < 0 || zoom > 20) {
      if (kDebugMode) {
        debugPrint('[FlutterMapAdapter] ⚠️ Invalid zoom level: $zoom, using default');
      }
      zoom = 13.0;
    }
    
    if (immediate) {
      // Immediate camera move without throttling - for user selection
      _animatedMove(target, zoom);
    } else {
      // Throttled move - for automatic fits
      _moveThrottler.run(() => _animatedMove(target, zoom));
    }
  }

  // Public method to trigger immediate camera fit (for user interactions)
  void fitCameraImmediate() {
    _maybeFit(immediate: true);
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

    // DEFENSIVE: Filter out markers with invalid coordinates AGAIN (extra safety)
    final safeMarkers = validMarkers.where((m) => _validLatLng(m.position)).toList();
    
    if (safeMarkers.length < validMarkers.length && kDebugMode) {
      debugPrint('[FlutterMapAdapter] ⚠️ Filtered out ${validMarkers.length - safeMarkers.length} markers with invalid coordinates');
    }

    // Use cached marker layer options to avoid rebuilding identical layers
    final cachedMarkers =
        MarkerLayerOptionsCache.instance.getCachedMarkers(safeMarkers);

    return MarkerClusterLayerWidget(
      options: MarkerClusterLayerOptions(
        maxClusterRadius: 45,
        size: const Size(40, 40), // Cluster circle size
        // Reuse cached markers if available to preserve widget identity
        markers: cachedMarkers ??
            [
              for (final m in safeMarkers)
                Marker(
                  key: ValueKey('marker_${m.id}_${m.isSelected}'),
                  point: m.position,
                  width: 56, // Modern circular marker size
                  height: 56,
                  child: Consumer(
                    builder: (context, ref, _) {
                      return GestureDetector(
                        key: ValueKey('tap_${m.id}'),
                        onTap: () => widget.onMarkerTap?.call(m.id),
                        child: MapMarkerWidget(
                          deviceId: int.tryParse(m.id) ?? -1,
                          isSelected: m.isSelected,
                          zoomLevel: mapController.camera.zoom,
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
              color: const Color(0xFFA6CD27).withValues(alpha: 0.9), // App seed color
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

    // NOTE: Tile providers are now created per-layer inside Consumer builders
    // This ensures each layer gets a fresh provider with the correct URL
    // See the Consumer blocks below for tile provider creation

    // CRITICAL FIX: Wrap entire FlutterMap in Consumer to force rebuild on provider change
    // This ensures the map completely rebuilds when switching between OSM, Satellite, and Hybrid
    return Consumer(
      builder: (context, ref, _) {
        final provider = ref.watch(mapTileSourceProvider);
        
        if (kDebugMode) {
          debugPrint('[MAP] 🧭 Active provider: ${provider.id}');
        }
        
        // OPTIMIZATION: Wrap FlutterMap in RepaintBoundary to isolate render pipeline
        // This prevents map tiles from repainting when markers update
        return RepaintBoundary(
          child: FlutterMap(
            // CRITICAL: Timestamp-based key forces complete FlutterMap reconstruction
            // This breaks all tile cache reuse and ensures fresh tiles on every provider switch
            key: ValueKey('map_${provider.id}_${DateTime.now().millisecondsSinceEpoch}'),
            mapController: mapController,
            options: MapOptions(
              initialCenter: const LatLng(0, 0),
              initialZoom: 2,
              onTap: (_, __) => widget.onMapTap?.call(),
            ),
            children: [
          // CRITICAL FIX: Tile layers must be direct children of FlutterMap
          // DO NOT wrap in Column - that causes infinite size errors!
          // KEY FIX: Use ValueKey with provider ID to force rebuild on source change
          if (!kDisableTilesForTests)
            Consumer(
              builder: (context, ref, _) {
                final tileSource = ref.watch(mapTileSourceProvider);
                // Debug: Log provider switches
                if (kDebugMode) {
                  debugPrint('[MAP] Switching to provider: ${tileSource.id} (${tileSource.name})');
                  debugPrint('[MAP] Base URL: ${tileSource.urlTemplate}');
                }
                
                // CRITICAL FIX: Create tile provider per layer to avoid URL caching
                // Use widget provider if available, otherwise create FMTC/Network provider
                final layerTileProvider = widget.tileProvider ?? 
                  (kForceDisableFMTC 
                    ? NetworkTileProvider(httpClient: _httpClient)
                    : FMTCTileProvider(
                        stores: const {'main': null}, // 'main' store initialized in main.dart
                        httpClient: _httpClient,
                      ));
                
                // HYBRID MODE: Render both Esri satellite base + Carto labels overlay
                if (tileSource.id == 'hybrid' || tileSource.id == 'esri_sat_hybrid') {
                  const hybridUrl = 'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}';
                  // Return base layer here, overlay added separately below
                  return TileLayer(
                    // REBUILD KEY: URL hash + provider ID forces fresh tile rendering
                    key: ValueKey('tiles_esri_sat_hybrid_${hybridUrl.hashCode}'),
                    urlTemplate: hybridUrl,
                    // CRITICAL: User-Agent required for CDN compliance
                    userAgentPackageName: TileNetworkClient.userAgent,
                    maxZoom: 19,
                    minZoom: 0,
                    tileProvider: layerTileProvider,
                  );
                }
                
                // STANDARD MODES: Single base tile layer (OSM, Satellite)
                return TileLayer(
                  // REBUILD KEY: URL hash + provider ID breaks tile cache on switch
                  key: ValueKey('tiles_${tileSource.id}_${tileSource.urlTemplate.hashCode}'),
                  urlTemplate: tileSource.urlTemplate,
                  // CRITICAL: User-Agent required for OpenStreetMap and CDN compliance
                  userAgentPackageName: TileNetworkClient.userAgent,
                  maxZoom: tileSource.maxZoom.toDouble(),
                  minZoom: tileSource.minZoom.toDouble(),
                  tileProvider: layerTileProvider,
                );
              },
            ),
          // HYBRID OVERLAY: Carto labels layer for hybrid mode
          // KEY FIX: Separate overlay layer with unique key to force rebuild
          if (!kDisableTilesForTests)
            Consumer(
              builder: (context, ref, _) {
                final tileSource = ref.watch(mapTileSourceProvider);
                
                // Check if hybrid mode OR has overlay URL
                final isHybrid = tileSource.id == 'hybrid' || tileSource.id == 'esri_sat_hybrid';
                final hasOverlay = tileSource.overlayUrlTemplate != null;
                
                if (!isHybrid && !hasOverlay) {
                  if (kDebugMode) {
                    debugPrint('[MAP] No overlay layer for provider: ${tileSource.id}');
                  }
                  return const SizedBox.shrink(); // No overlay
                }
                
                // Debug: Log overlay activation
                if (kDebugMode) {
                  debugPrint('[MAP] Overlay enabled for provider: ${tileSource.id}');
                  if (isHybrid) {
                    debugPrint('[MAP] Overlay URL: https://basemaps.cartocdn.com/light_only_labels/{z}/{x}/{y}.png');
                    debugPrint('[MAP] Overlay opacity: 0.6');
                  } else {
                    debugPrint('[MAP] Overlay URL: ${tileSource.overlayUrlTemplate}');
                    debugPrint('[MAP] Overlay opacity: ${tileSource.overlayOpacity}');
                  }
                }
                
                // CRITICAL FIX: Create tile provider per overlay layer
                // Overlay uses FMTC with httpClient for caching + offline support
                final overlayTileProvider = kForceDisableFMTC
                    ? NetworkTileProvider(httpClient: _httpClient)
                    : FMTCTileProvider(
                        stores: const {'main': null}, // 'main' store initialized in main.dart
                        httpClient: _httpClient,
                      );
                
                // HYBRID MODE: Render Carto labels overlay
                if (isHybrid) {
                  const cartoUrl = 'https://basemaps.cartocdn.com/light_only_labels/{z}/{x}/{y}.png';
                  return Opacity(
                    opacity: 0.6, // Semi-transparent labels
                    child: TileLayer(
                      // REBUILD KEY: URL hash ensures fresh overlay rendering in hybrid mode
                      key: const ValueKey('overlay_carto_labels'),
                      urlTemplate: cartoUrl,
                      // CRITICAL: User-Agent required for Carto CDN compliance
                      userAgentPackageName: TileNetworkClient.userAgent,
                      maxZoom: 19,
                      minZoom: 0,
                      tileProvider: overlayTileProvider,
                    ),
                  );
                }
                
                // STANDARD OVERLAY: Use overlay from MapTileSource
                final overlayUrl = tileSource.overlayUrlTemplate!;
                return Opacity(
                  opacity: tileSource.overlayOpacity,
                  child: TileLayer(
                    // REBUILD KEY: URL hash + provider ID forces overlay refresh
                    key: ValueKey('overlay_${tileSource.id}_${overlayUrl.hashCode}'),
                    urlTemplate: overlayUrl,
                    // CRITICAL: User-Agent required for CDN compliance
                    userAgentPackageName: TileNetworkClient.userAgent,
                    maxZoom: tileSource.maxZoom.toDouble(),
                    minZoom: tileSource.minZoom.toDouble(),
                    tileProvider: overlayTileProvider,
                  ),
                );
              },
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
          // Dynamic attribution based on selected tile source
          Positioned(
            right: 8,
            bottom: 8,
            child: Consumer(
              builder: (context, ref, _) {
                final tileSource = ref.watch(mapTileSourceProvider);
                return Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    tileSource.attribution,
                    style: const TextStyle(color: Colors.white, fontSize: 11),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
      }, // End of outer Consumer builder
    ); // End of outer Consumer
  }
}

// Marker icon visuals moved to MapMarkerWidget to support per-marker rebuild isolation.
