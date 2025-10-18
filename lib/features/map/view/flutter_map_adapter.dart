import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
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
import 'package:my_app_gps/providers/connectivity_provider.dart';
import 'package:my_app_gps/providers/map_rebuild_provider.dart';

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
  
  // ZOOM CLAMP: Maximum zoom level to prevent tile loading flicker
  static const double kMaxZoom = 18.0;
  
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

  // Cache tile providers per (layer, source) to avoid recreating on every build,
  // which can cause visible blinking. We still separate base/overlay providers
  // to avoid any internal URL caching cross-talk.
  final Map<String, TileProvider> _tileProviderCache = {};
  String? _lastProviderId;

  TileProvider _getCachedProvider(String key, {String? storeName}) {
    final existing = _tileProviderCache[key];
    if (existing != null) return existing;
    // Use a dedicated FMTC store per map source to prevent cross-source cache collisions.
    final created = kForceDisableFMTC
        ? NetworkTileProvider(httpClient: _httpClient)
        : FMTCStore(storeName ?? 'main').getTileProvider(
            httpClient: _httpClient,
          );
    _tileProviderCache[key] = created;
    return created;
  }

  @override
  void didUpdateWidget(covariant FlutterMapAdapter oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Use throttled fit for subsequent updates to avoid rapid camera jumps
    // NOTE: Camera updates via MapController do NOT trigger widget rebuilds
    _maybeFit();
  }

  @override
  void initState() {
    super.initState();
    // Initialize dedicated HTTP/1.1 client for reliable FMTC tile loading
    _httpClient = TileNetworkClient.shared();
    // CRITICAL FIX: Initial camera fit must be IMMEDIATE to show selected devices
    // Without this, map shows (0,0) for 300ms+ while throttler delays the fit
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeFit(immediate: true));
    
    if (kDebugMode) {
      debugPrint('[MAP_REBUILD] 🎬 FlutterMapAdapter initialized with persistent MapController');
    }

    // NETWORK RESILIENCE: Listen for reconnect events to trigger map refresh
    ref.listenManual(connectivityProvider, (previous, next) {
      if (previous != null && previous.isOffline && next.isOnline) {
        if (kDebugMode) {
          debugPrint(
            '[NETWORK] 🟢 Reconnected → triggering map rebuild for fresh tiles',
          );
        }
        // Trigger full map rebuild to refresh tiles and resume live markers
        ref.read(mapRebuildProvider.notifier).trigger();
      }
    });
  }

  @override
  void dispose() {
    // Do not close the shared client here; it may be reused elsewhere.
    mapController.dispose();
    if (kDebugMode) {
      debugPrint('[MAP_REBUILD] 🗑️ FlutterMapAdapter disposed');
    }
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
      return 13; // Return safe default zoom
    }
    
    // Very naive fit; refine later with size info & padding.
    final latDiff = (b.north - b.south).abs().clamp(0.0001, 180.0);
    final lngDiff = (b.east - b.west).abs().clamp(0.0001, 360.0);
    final maxDiff = latDiff > lngDiff ? latDiff : lngDiff;
    
    // DEFENSIVE: Ensure maxDiff is finite
    if (!maxDiff.isFinite || maxDiff.isNaN) {
      return 13; // Safe default
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

  /// Safe zoom method with automatic clamping to prevent tile flicker
  ///
  /// Clamps zoom to [0, kMaxZoom] range and logs diagnostic when clamped.
  /// Use this instead of direct mapController.move() for programmatic zoom.
  void safeZoomTo(LatLng center, double zoom) {
    final clampedZoom = zoom.clamp(0.0, kMaxZoom);
    if (clampedZoom != zoom && kDebugMode) {
      debugPrint('[MAP] Zoom clamped to $kMaxZoom (requested: ${zoom.toStringAsFixed(1)})');
    }
    mapController.move(center, clampedZoom);
  }

  void _animatedMove(LatLng dest, double zoom) {
    // ZOOM CLAMP: Prevent excessive zoom causing tile flicker
    final clampedZoom = zoom.clamp(0.0, kMaxZoom);
    if (clampedZoom != zoom && kDebugMode) {
      debugPrint('[MAP] Zoom clamped to $kMaxZoom (requested: ${zoom.toStringAsFixed(1)})');
    }
    
    // REBUILD ISOLATION: Camera moves via MapController do NOT trigger widget rebuilds
    // This is critical for performance - moving the camera updates internal state only
    mapController.move(dest, clampedZoom);

    if (kDebugMode) {
      debugPrint('[MAP_REBUILD] 📍 Camera moved to (${dest.latitude.toStringAsFixed(4)}, ${dest.longitude.toStringAsFixed(4)}) @ zoom ${clampedZoom.toStringAsFixed(1)} - NO rebuild');
    }

    // Note: flutter_map's move() is synchronous and does not rebuild the widget tree.
    // The map canvas repaints in place, keeping all layers stable.
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

    // CRITICAL: Deduplicate markers by identity (id + selection state) to avoid duplicate keys
    final dedup = <String>{};
    final dedupMarkers = <MapMarkerData>[];
    for (final m in safeMarkers) {
      final k = '${m.id}_${m.isSelected}';
      if (dedup.add(k)) {
        dedupMarkers.add(m);
      } else if (kDebugMode) {
        debugPrint('[FlutterMapAdapter] ⚠️ Dropping duplicate marker key marker_$k');
      }
    }

    // Use cached marker layer options to avoid rebuilding identical layers
    final cachedMarkers =
        MarkerLayerOptionsCache.instance.getCachedMarkers(dedupMarkers);

    // Use plain MarkerLayer to ensure visibility while we stabilize clustering.
    final markersList = cachedMarkers ?? [
      for (final m in dedupMarkers)
        Marker(
          key: ValueKey('marker_${m.id}_${m.isSelected}'),
          point: m.position,
          width: 56, // Modern marker visual size
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
                  // Fallbacks from MapMarkerData.meta allow immediate render
                  fallbackName: m.meta?['name']?.toString(),
                  fallbackSpeed: (m.meta?['speed'] is num)
                      ? (m.meta?['speed'] as num).toDouble()
                      : null,
                  fallbackEngineOn: m.meta?['engineOn'] as bool?,
                  key: ValueKey('marker_widget_${m.id}_${m.isSelected}'),
                ),
              );
            },
          ),
        ),
    ];

    return MarkerLayer(markers: markersList);
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
  // This ensures the map completely rebuilds when switching between OSM and Satellite
    return Consumer(
      builder: (context, ref, _) {
        final provider = ref.watch(mapTileSourceProvider);
        final lastSwitchTs = ref.read(mapTileSourceProvider.notifier).lastSwitchTimestamp;
        final rebuildEpoch = ref.watch(mapRebuildProvider);
        
        if (kDebugMode) {
          debugPrint('[MAP_REBUILD] 🧭 Epoch: $rebuildEpoch, Source: ${provider.id}, Timestamp: $lastSwitchTs');
        }

        // If provider id changed, clear cached tile providers to force fresh instances
        if (_lastProviderId != provider.id) {
          if (kDebugMode) {
            debugPrint('[MAP_REBUILD] 🔁 Provider changed ${_lastProviderId ?? 'null'} → ${provider.id}; clearing tile provider cache');
          }
          _tileProviderCache.clear();
          _lastProviderId = provider.id;
        }
        
        // OPTIMIZATION: Wrap FlutterMap in RepaintBoundary to isolate render pipeline
        // This prevents map tiles from repainting when markers update
        return RepaintBoundary(
          child: FlutterMap(
            // REBUILD-AWARE KEY: Combines source ID, timestamp, and rebuild epoch
            // This ensures map rebuilds ONLY when:
            // 1. Tile source changes (provider.id)
            // 2. Explicit rebuild triggered (rebuildEpoch)
            // 3. Timestamp-based cache bust (lastSwitchTs)
            // Marker updates and camera moves do NOT trigger rebuilds
            key: ValueKey('map_${provider.id}_${lastSwitchTs}_$rebuildEpoch'),
            mapController: mapController,
            options: MapOptions(
              initialCenter: const LatLng(0, 0),
              initialZoom: 2,
              maxZoom: kMaxZoom, // ZOOM CLAMP: Prevent flicker from excessive zoom
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
                final ts = ref.read(mapTileSourceProvider.notifier).lastSwitchTimestamp;
                // Debug: Log provider switches
                if (kDebugMode) {
                  debugPrint('[MAP] Switching to provider: ${tileSource.id} (${tileSource.name}), ts=$ts');
                  debugPrint('[MAP] Base URL: ${tileSource.urlTemplate}');
                }
                
                // CRITICAL: Use cached per-layer provider to avoid blink,
                // still unique per map source to prevent URL caching issues.
        final layerTileProvider = widget.tileProvider ??
          _getCachedProvider('base_${tileSource.id}_$ts', storeName: 'tiles_${tileSource.id}');

                // Cache-busting: append timestamp query to force fresh tiles on toggle
                final sep = tileSource.urlTemplate.contains('?') ? '&' : '?';
                final effectiveUrl = '${tileSource.urlTemplate}${sep}_v=$ts';
                
                if (kDebugMode && layerTileProvider.runtimeType.toString().contains('FMTC')) {
                  debugPrint('[FMTC][CLIENT] Base layer using shared IOClient for ${tileSource.id}');
                }
                
                // No hybrid mode anymore: render single base layer for the active source
                
                // STANDARD MODES: Single base tile layer (OSM, Satellite)
                return TileLayer(
                  // REBUILD KEY: URL hash + provider ID breaks tile cache on switch
                  // Include ts to force reinit if same id is toggled quickly
                  key: ValueKey('tiles_${tileSource.id}_${effectiveUrl.hashCode}_$ts'),
                  urlTemplate: effectiveUrl,
                  // CRITICAL: User-Agent required for OpenStreetMap and CDN compliance
                  userAgentPackageName: TileNetworkClient.userAgent,
                  maxZoom: tileSource.maxZoom.toDouble(),
                  minZoom: tileSource.minZoom.toDouble(),
                  tileProvider: layerTileProvider,
                  errorTileCallback: (tile, error, stack) {
                    if (kDebugMode) {
                      debugPrint('[FMTC][ERROR] Base tile ${tileSource.id} ${tile}: ${error.runtimeType} -> $error');
                    }
                  },
                );
              },
            ),
          // Overlay layer support (only when overlayUrlTemplate is set)
          if (!kDisableTilesForTests)
            Consumer(
              builder: (context, ref, _) {
                final tileSource = ref.watch(mapTileSourceProvider);
                final ts = ref.read(mapTileSourceProvider.notifier).lastSwitchTimestamp;
                
                final hasOverlay = tileSource.overlayUrlTemplate != null;
                if (!hasOverlay) {
                  if (kDebugMode) {
                    debugPrint('[MAP] No overlay layer for provider: ${tileSource.id} (ts=$ts)');
                  }
                  return const SizedBox.shrink(); // No overlay
                }
                
                // Debug: Log overlay activation
                if (kDebugMode) {
                  debugPrint('[MAP] Overlay enabled for provider: ${tileSource.id}');
                  debugPrint('[MAP] Overlay URL: ${tileSource.overlayUrlTemplate}');
                  debugPrint('[MAP] Overlay opacity: ${tileSource.overlayOpacity}');
                }
                
                // Overlay provider cached per source to avoid flicker
                final overlayTileProvider = _getCachedProvider('overlay_${tileSource.id}_$ts', storeName: 'overlay_${tileSource.id}');
                
                if (kDebugMode && overlayTileProvider.runtimeType.toString().contains('FMTC')) {
                  debugPrint('[FMTC][CLIENT] Overlay layer using shared IOClient');
                }
                
                // Use overlay from MapTileSource
                final overlayUrlRaw = tileSource.overlayUrlTemplate!;
                // Cache-busting for overlay as well
                final overlaySep = overlayUrlRaw.contains('?') ? '&' : '?';
                final overlayUrl = '$overlayUrlRaw${overlaySep}_v=$ts';
                return Opacity(
                  opacity: tileSource.overlayOpacity,
                  child: TileLayer(
                    // REBUILD KEY: URL hash + provider ID forces overlay refresh
                    key: ValueKey('overlay_${tileSource.id}_${overlayUrl.hashCode}_$ts'),
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
                if (kDebugMode) {
                  debugPrint('[MAP] Marker notifier emitted: ${markers.length} markers');
                }
                final validMarkers = markers
                    .where((m) => _validLatLng(m.position))
                    .toList(growable: false);
                if (validMarkers.isEmpty) {
                  if (kDebugMode) {
                    debugPrint('[MAP] Skipping cluster render – no valid markers yet');
                  }
                  return const SizedBox.shrink();
                }
                return _buildMarkerLayer(validMarkers);
              },
            )
          else
            Builder(
              builder: (ctx) {
                if (kDebugMode) {
                  debugPrint('[MAP] Using direct markers list: ${widget.markers.length} markers');
                }
                final validMarkers = widget.markers
                    .where((m) => _validLatLng(m.position))
                    .toList(growable: false);
                if (validMarkers.isEmpty) {
                  if (kDebugMode) {
                    debugPrint('[MAP] Skipping cluster render – no valid markers yet');
                  }
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
