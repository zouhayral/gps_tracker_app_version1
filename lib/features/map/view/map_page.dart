import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
// import 'package:flutter_map/flutter_map.dart';
// import 'package:flutter_map_tile_caching/flutter_map_tile_caching.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';
import 'package:my_app_gps/core/data/vehicle_data_repository.dart';
import 'package:my_app_gps/core/diagnostics/frame_timing_summarizer.dart';
import 'package:my_app_gps/core/diagnostics/performance_metrics_service.dart';
import 'package:my_app_gps/core/diagnostics/rebuild_tracker.dart';
import 'package:my_app_gps/core/map/bitmap_descriptor_cache.dart';
import 'package:my_app_gps/core/map/enhanced_marker_cache.dart';
import 'package:my_app_gps/core/map/fleet_map_prefetch.dart';
import 'package:my_app_gps/core/map/marker_cache.dart';
import 'package:my_app_gps/core/map/marker_icon_manager.dart';
import 'package:my_app_gps/core/map/marker_performance_monitor.dart';
import 'package:my_app_gps/core/map/marker_processing_isolate.dart';
import 'package:my_app_gps/core/map/rebuild_profiler.dart';
import 'package:my_app_gps/core/providers/connectivity_providers.dart';
import 'package:my_app_gps/core/providers/vehicle_providers.dart';
import 'package:my_app_gps/core/utils/throttled_value_notifier.dart';
import 'package:my_app_gps/core/utils/timing.dart';
import 'package:my_app_gps/features/dashboard/controller/devices_notifier.dart';
import 'package:my_app_gps/features/map/clustering/cluster_hud.dart';
import 'package:my_app_gps/features/map/clustering/cluster_models.dart';
import 'package:my_app_gps/features/map/clustering/spiderfy_overlay.dart';
import 'package:my_app_gps/features/map/controller/fleet_map_telemetry_controller.dart';
import 'package:my_app_gps/features/map/core/map_adapter.dart';
import 'package:my_app_gps/features/map/data/granular_providers.dart';
import 'package:my_app_gps/features/map/data/position_model.dart';
import 'package:my_app_gps/features/map/data/positions_last_known_provider.dart';
import 'package:my_app_gps/features/map/view/flutter_map_adapter.dart';
import 'package:my_app_gps/features/map/view/map_page_lifecycle_mixin.dart';
import 'package:my_app_gps/map/map_tile_providers.dart';
import 'package:my_app_gps/map/map_tile_source_provider.dart';
import 'package:my_app_gps/services/fmtc_initializer.dart';
import 'package:my_app_gps/services/positions_service.dart';
// import 'package:my_app_gps/services/websocket_manager.dart';

// Clean rebuilt MapPage implementation
// Features:
//  - Gated search bar (single tap show suggestions, double tap or keyboard icon to edit)
//  - Tri‑state All devices selection (all / some / none)
//  - Live positions preferred over stored device lat/lon
//  - Multi‑snap bottom panel (stops: 5%, 30%, 50%, 80%) with drag velocity ±250
//  - Deep link preselection focus (preselectedIds)
//  - Single, duplicate‑free implementation (previous corruption removed)
// FMTC tile provider singleton via Riverpod

// Removed shared TileProvider provider; FlutterMapAdapter manages per-source
// cached providers internally to guarantee correct tile switching without
// full map rebuilds and avoid flicker.

// Marker cache provider
final markerCacheProvider = Provider<MarkerCache>((ref) => MarkerCache());

// Debounced positions helper
Map<int, Position> useDebouncedPositions(
  AsyncValue<Map<int, Position>> positionsAsync,
  Duration debounce,
) {
  // Simple debounce: returns latest positions after delay
  var latest = <int, Position>{};
  positionsAsync.when(
    data: (map) {
      Future.delayed(
        debounce,
        () => latest = Map<int, Position>.unmodifiable(map),
      );
    },
    loading: () {},
    error: (_, __) {},
  );
  return latest;
}

/// Debug toggles for map page (safe defaults: all off)
class MapDebugFlags {
  // Toggle to show rebuild counters overlay (console + UI)
  static const bool showRebuildOverlay = false;
  // Toggle to enable frame timing summarizer logs
  static const bool enableFrameTiming = false;
  // Toggle to enable PerformanceMetricsService (FPS/Jank logs, CSV, etc.)
  static const bool enablePerfMetrics = false;
  // Toggle to use FleetMapTelemetryController (async-first) instead of devicesNotifierProvider
  // Set to true to enable the new async controller for testing
  static const bool useFMTCController = false;
  // Toggle to show marker performance stats (cache efficiency, processing time)
  static const bool showMarkerPerformance = false;
  // Toggle to enable tile prefetch and snapshot cache
  static const bool enablePrefetch = false;
  // Toggle to show snapshot overlay during load
  static const bool showSnapshotOverlay = false;
}

// Simple rebuild badge for profiling; increments an internal counter each build.
class _RebuildBadge extends StatefulWidget {
  const _RebuildBadge({required this.label});
  final String label;
  @override
  State<_RebuildBadge> createState() => _RebuildBadgeState();
}

class _RebuildBadgeState extends State<_RebuildBadge> {
  int _count = 0;
  @override
  Widget build(BuildContext context) {
    _count++;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Text(
          '${widget.label}: $_count',
          style: const TextStyle(color: Colors.white, fontSize: 12),
        ),
      ),
    );
  }
}

class MapPage extends ConsumerStatefulWidget {
  const MapPage({super.key, this.preselectedIds});
  final Set<int>? preselectedIds;
  @override
  ConsumerState<MapPage> createState() => _MapPageState();
}

class _MapPageState extends ConsumerState<MapPage>
    with WidgetsBindingObserver, MapPageLifecycleMixin<MapPage> {
  // Selection
  final Set<int> _selectedIds = <int>{};
  // Last-known positions captured by listeners to avoid timing gaps
  final Map<int, Position> _lastPositions = <int, Position>{};

  @override
  List<int> get activeDeviceIds => _selectedIds.toList();

  // Search / suggestions gating
  final _searchCtrl = TextEditingController();
  final _focusNode = FocusNode();
  String _query = '';
  bool _editing = false; // when true TextField accepts input
  bool _showSuggestions = false;
  final _searchDebouncer = Debouncer(const Duration(milliseconds: 250));

  // Map
  final _mapKey = GlobalKey<FlutterMapAdapterState>();
  final _snapshotKey = GlobalKey(); // For RepaintBoundary snapshot capture
  bool _didAutoFocus = false;
  Timer? _preselectSnackTimer;

  // OPTIMIZATION: FleetMapPrefetch manager for tile prefetch + snapshot cache
  FleetMapPrefetchManager? _prefetchManager;
  bool _isShowingSnapshot = false;
  MapSnapshot? _cachedSnapshot;
  // Avoid re-registering position listeners every build which can cause churn
  final Set<int> _positionListenerIds = <int>{};
  // MIGRATION NOTE: Removed _debouncedPositions - repository provides debouncing
  // MIGRATION NOTE: Removed _fitThrottler - camera fit throttling now handled by FlutterMapAdapter
  // Track last selected device to detect changes
  int? _lastSelectedSingleDevice;

  // OPTIMIZATION: Throttled ValueNotifier for marker updates (reduces rebuilds when updates <50ms apart)
  late final ThrottledValueNotifier<List<MapMarkerData>> _markersNotifier;

  // OPTIMIZATION: Enhanced marker cache with intelligent diffing
  final _enhancedMarkerCache = EnhancedMarkerCache();

  // Bottom panel snaps
  final List<double> _panelStops = const [0.05, 0.30, 0.50, 0.80];
  int _panelIndex = 1; // start at 30%

  // Refresh state
  bool _isRefreshing = false;

  // MIGRATION NOTE: Removed _posSub - VehicleDataRepository manages subscriptions

  @override
  void initState() {
    super.initState();

    // OPTIMIZATION: Initialize throttled marker notifier
    // Raised throttle to 80ms to reduce UI thread load
    _markersNotifier = ThrottledValueNotifier<List<MapMarkerData>>(
      const [],
      // Slow down marker list updates to reduce UI churn
      throttleDuration: const Duration(milliseconds: 300),
    );

    _focusNode.addListener(() => setState(() {}));

    // OPTIMIZATION: Initialize FleetMapPrefetch manager
    if (MapDebugFlags.enablePrefetch) {
      _initializePrefetchManager();
    }

    // MIGRATION: Initialize VehicleDataRepository for cache-first startup
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;

      // OPTIMIZATION: Preload bitmap descriptors for instant marker icons
      // This eliminates the "loading" spinner delay on first marker render
      unawaited(
        BitmapDescriptorCache.instance
            .preloadAll(StandardMarkerIcons.assetPaths)
            .catchError((Object e) {
          if (kDebugMode) {
            debugPrint('[MapPage] Bitmap cache preload error (non-fatal): $e');
          }
        }),
      );

      // OPTIMIZATION: Preload marker icons for reduced first-draw latency
      unawaited(
        MarkerIconManager.instance.preloadIcons().catchError((Object e) {
          if (kDebugMode) {
            debugPrint('[MapPage] Icon preload error (non-fatal): $e');
          }
        }),
      );

      // OPTIMIZATION: Initialize background marker processing isolate
      await MarkerProcessingIsolate.instance.initialize();

      // OPTIMIZATION: Frame timing monitoring (disabled by default)
      if (MapDebugFlags.enableFrameTiming) {
        FrameTimingSummarizer.instance.enable();
      }

      // Get repository instance (starts WebSocket + REST fallback)
      final repo = ref.read(vehicleDataRepositoryProvider);

      // Get device IDs to initialize
      final devicesAsync = ref.read(devicesNotifierProvider);
      final devices = devicesAsync.asData?.value ?? [];
      final deviceIds =
          devices.map((d) => d['id'] as int?).whereType<int>().toList();

      if (deviceIds.isNotEmpty) {
        // Fetch from cache (instant) and trigger REST fetch (background)
        unawaited(repo.fetchMultipleDevices(deviceIds));
        if (kDebugMode) {
          debugPrint(
            '[MapPage] Initialized repository with ${deviceIds.length} devices',
          );
        }
      }

      // Register marker count supplier for performance overlay (disabled by default)
      if (MapDebugFlags.enablePerfMetrics) {
        final perfSvc = ref.read(performanceMetricsServiceProvider);
        perfSvc.setMarkerCountSupplier(() => _markersNotifier.value.length);
        perfSvc.start();
      }

      // OPTIMIZATION: Setup marker update listeners (outside build method)
      // This ensures marker processing happens in response to data changes,
      // not during widget rebuilds
      _setupMarkerUpdateListeners();
    });

    // Warm up FMTC asynchronously - do not await here to avoid blocking initState
    unawaited(FMTCInitializer.warmup().then((_) {
      debugPrint('[FMTC] warmup finished');
    }).catchError((Object e, StackTrace? st) {
      debugPrint('[FMTC] warmup error: $e');
    }),);

    // NEW: Warm up per-source FMTC stores used by FlutterMapAdapter
    // Prevents StoreNotExists errors when switching providers at runtime
    unawaited(FMTCInitializer
        .warmupStoresForSources(MapTileProviders.all)
        .then((_) {
      debugPrint('[FMTC] per-source store warmup finished');
    }).catchError((Object e, StackTrace? st) {
      debugPrint('[FMTC] per-source warmup error: $e');
    }),);

    // MIGRATION NOTE: Removed old positionsLiveProvider listening
    // VehicleDataRepository handles WebSocket → Cache → Notifiers internally

    if (widget.preselectedIds != null && widget.preselectedIds!.isNotEmpty) {
      _selectedIds.addAll(widget.preselectedIds!);
      // Snackbar reminder if not focused after delay
      _preselectSnackTimer = Timer(const Duration(seconds: 6), () {
        if (!mounted) return;
        if (!_didAutoFocus && widget.preselectedIds!.isNotEmpty) {
          final ids = widget.preselectedIds!;
          final sample = ids.take(5).join(', ');
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Devices not located yet: $sample${ids.length > 5 ? ' +${ids.length - 5}' : ''}',
              ),
              action: SnackBarAction(
                label: 'Retry',
                onPressed: () => setState(() {}),
              ),
            ),
          );
        }
      });
    }
  }

  /// OPTIMIZATION: Setup marker update listeners outside of build method
  ///
  /// This is critical for performance - marker processing should happen
  /// in response to data changes (via ref.listen), NOT during widget builds.
  ///
  /// Benefits:
  /// - Build method stays pure and fast
  /// - Marker updates only when data actually changes
  /// - No redundant processing on unrelated rebuilds
  void _setupMarkerUpdateListeners() {
    if (kDebugMode) {
      debugPrint('[MAP] _setupMarkerUpdateListeners called');
    }
    
    // Track which devices we've set up listeners for
    final listenedDeviceIds = <int>{};
    
    // Helper to setup position listeners for a device
    void setupPositionListener(int deviceId) {
      if (listenedDeviceIds.contains(deviceId)) {
        if (kDebugMode) {
          debugPrint('[MAP] Skipping duplicate listener for device $deviceId');
        }
        return;
      }
      listenedDeviceIds.add(deviceId);
      
      if (kDebugMode) {
        debugPrint('[MAP] Setting up position listener for device $deviceId');
      }
      
      // Listen to position updates for this device
      // Note: vehiclePositionProvider is a StreamProvider, so we listen to AsyncValue changes
      ref.listen(vehiclePositionProvider(deviceId), (previous, next) {
        if (!mounted) return;
        if (kDebugMode) {
          debugPrint('[MAP] Position listener fired for device $deviceId: '
              'previous=${previous?.valueOrNull != null}, '
              'next=${next.valueOrNull != null}');
        }
        final pos = next.valueOrNull;
        if (pos != null) {
          _lastPositions[deviceId] = pos;
        }
        // When any position updates, refresh all markers
        final currentDevices = ref.read(devicesNotifierProvider);
        currentDevices.whenData(_triggerMarkerUpdate);
      });
    }
    
    // Listen to device list changes
    ref.listen(devicesNotifierProvider, (previous, next) {
      next.whenData((devices) {
        if (!mounted) return;
        
        // Setup position listeners for any new devices
        for (final device in devices) {
          final deviceId = device['id'] as int?;
          if (deviceId != null) {
            setupPositionListener(deviceId);
          }
        }
        
        _triggerMarkerUpdate(devices);
      });
    });

    // Listen to last-known positions updates (REST/DAO seeded)
    // This ensures markers appear even when WebSocket is disconnected
    ref.listen(positionsLastKnownProvider, (previous, next) {
      if (!mounted) return;
      if (kDebugMode) {
        final prevCount = previous?.valueOrNull?.length ?? 0;
        final nextCount = next.valueOrNull?.length ?? 0;
        debugPrint('[MAP] positionsLastKnown changed: $prevCount -> $nextCount');
      }
      final devices = ref.read(devicesNotifierProvider).asData?.value ?? const <Map<String, dynamic>>[];
      if (devices.isNotEmpty) {
        _triggerMarkerUpdate(devices);
      }
    });

    // Prime last-known provider to start background fetch/cache
    // Safe to read here; provider manages its own lifecycle
    // ignore: unused_local_variable
    final _ = ref.read(positionsLastKnownProvider);

    // Get initial devices and trigger first update
    final devicesAsync = ref.read(devicesNotifierProvider);
    devicesAsync.whenData((devices) {
      if (mounted) {
        // Setup position listeners for all initial devices
        for (final device in devices) {
          final deviceId = device['id'] as int?;
          if (deviceId != null) {
            setupPositionListener(deviceId);
          }
        }
        
        _triggerMarkerUpdate(devices);
      }
    });
  }

  /// Trigger marker update with current state
  /// Called by listeners when data changes
  void _triggerMarkerUpdate(List<Map<String, dynamic>> devices) {
    if (kDebugMode) {
      debugPrint('[MAP] _triggerMarkerUpdate called for ${devices.length} devices');
    }
    
    // Use last-known positions captured by listeners to avoid timing gaps
    final positions = <int, Position>{}..addAll(_lastPositions);

    // Merge in last-known positions from REST/DAO provider
    final lastKnownAsync = ref.read(positionsLastKnownProvider);
    final lastKnown = lastKnownAsync.valueOrNull;
    if (lastKnown != null && lastKnown.isNotEmpty) {
      // Do not overwrite fresher live positions
      for (final entry in lastKnown.entries) {
        positions.putIfAbsent(entry.key, () => entry.value);
      }
    }

    if (kDebugMode) {
      final selInfo = _selectedIds.isEmpty ? 'none' : _selectedIds.join(',');
      debugPrint('[MAP] Found ${positions.length} positions for marker update (selected: $selInfo)');
    }

    // Process markers asynchronously
    _processMarkersAsync(
      positions,
      devices,
      _selectedIds,
      _query,
    );
  }

  @override
  void dispose() {
    // MIGRATION NOTE: Removed _posSub.close() and _positionsDebounceTimer - repository manages lifecycle
    _preselectSnackTimer?.cancel();
    _searchDebouncer.cancel();
    _searchCtrl.dispose();
    _focusNode.dispose();
    _markersNotifier
        .dispose(); // OPTIMIZATION: Clean up throttled marker notifier

    // OPTIMIZATION: Cleanup prefetch manager
    if (MapDebugFlags.enablePrefetch) {
      _prefetchManager?.dispose();
      _captureSnapshotBeforeDispose();
    }

    // OPTIMIZATION: Cleanup frame timing and marker isolate
    if (MapDebugFlags.enableFrameTiming) {
      FrameTimingSummarizer.instance.disable();
    }
    MarkerProcessingIsolate.instance.dispose();

    super.dispose();
  }

  // ---------- Prefetch & Snapshot Helpers ----------

  /// Initialize FleetMapPrefetch manager and load cached snapshot
  Future<void> _initializePrefetchManager() async {
    try {
      final prefs = ref.read(sharedPreferencesProvider);
      _prefetchManager = FleetMapPrefetchManager(
        prefs: prefs,
        debugMode: kDebugMode,
      );

      await _prefetchManager!.initialize();

      // Load cached snapshot if available
      _cachedSnapshot = _prefetchManager!.getCachedSnapshot();

      if (_cachedSnapshot != null) {
        setState(() {
          _isShowingSnapshot = true;
        });

        if (kDebugMode) {
          debugPrint(
            '[MapPage] Loaded snapshot: age=${_cachedSnapshot!.age.inMinutes}m, '
            'size=${(_cachedSnapshot!.imageBytes.length / 1024).toStringAsFixed(1)}KB',
          );
        }

        // Prefetch tiles for cached region
        WidgetsBinding.instance.addPostFrameCallback((_) async {
          await _prefetchCachedRegion();

          // Hide snapshot after tiles loaded
          if (mounted) {
            setState(() {
              _isShowingSnapshot = false;
            });
          }
        });
      }
    } catch (e) {
      debugPrint('[MapPage] Prefetch init error: $e');
    }
  }

  /// Prefetch tiles for cached snapshot region
  Future<void> _prefetchCachedRegion() async {
    if (_cachedSnapshot == null || _mapKey.currentState == null) return;

    try {
      await _prefetchManager!.prefetchVisibleTiles(
        controller: _mapKey.currentState!.mapController,
        center: _cachedSnapshot!.center,
        zoom: _cachedSnapshot!.zoom,
      );

      if (kDebugMode) {
        debugPrint('[MapPage] Prefetch completed for cached region');
      }
    } catch (e) {
      debugPrint('[MapPage] Prefetch error: $e');
    }
  }

  /// Capture snapshot before dispose
  void _captureSnapshotBeforeDispose() {
    if (_mapKey.currentState == null) return;

    final controller = _mapKey.currentState!.mapController;
    final center = controller.camera.center;
    final zoom = controller.camera.zoom;

    // Fire-and-forget snapshot capture
    _prefetchManager
        ?.captureSnapshot(
      mapKey: _snapshotKey,
      center: center,
      zoom: zoom,
    )
        .catchError((Object e) {
      debugPrint('[MapPage] Snapshot capture error: $e');
    });
  }

  // ---------- Marker Processing Helpers ----------

  /// Smooth camera move with animation (uses FleetMapPrefetch if enabled)
  void _smoothMoveTo(
    LatLng target, {
    double zoom = 16,
  }) {
    final state = _mapKey.currentState;
    if (state == null) return;

    // Always use immediate moves (smooth animations disabled to prevent test timer issues)
    state.moveTo(target, zoom: zoom);
  }

  // ---------- Marker Processing Helpers ----------

  /// OPTIMIZATION: Process markers with intelligent diffing and caching
  /// Uses EnhancedMarkerCache to minimize marker object creation
  Future<void> _processMarkersAsync(
    Map<int, Position> positions,
    List<Map<String, dynamic>> devices,
    Set<int> selectedIds,
    String query,
  ) async {
    try {
      final stopwatch = Stopwatch()..start();

      if (kDebugMode) {
        debugPrint(
          '[MapPage] Processing ${positions.length} positions for markers...',
        );
      }

      // CRITICAL: Ensure first non-empty dataset is not dropped by throttling.
      // If current UI has no markers yet but we now have positions or devices with
      // valid stored coordinates, force an update to render immediately.
      bool valid(double? lat, double? lon) =>
          lat != null &&
          lon != null &&
          !lat.isNaN &&
          !lon.isNaN &&
          lat.isFinite &&
          lon.isFinite &&
          lat >= -90 &&
          lat <= 90 &&
          lon >= -180 &&
          lon <= 180;

      bool hasAnyDeviceStoredCoords() {
        for (final d in devices) {
          final lat = _asDouble(d['latitude']);
          final lon = _asDouble(d['longitude']);
          if (valid(lat, lon)) return true;
        }
        return false;
      }

      final forceFirstRender = _markersNotifier.value.isEmpty &&
          (positions.isNotEmpty || hasAnyDeviceStoredCoords());

      // OPTIMIZATION: Use enhanced marker cache with intelligent diffing
      final diffResult = _enhancedMarkerCache.getMarkersWithDiff(
        positions,
        devices,
        selectedIds,
        query,
        forceUpdate: forceFirstRender,
      );

      stopwatch.stop();

      // Record performance metrics
      MarkerPerformanceMonitor.instance.recordUpdate(
        markerCount: diffResult.markers.length,
        created: diffResult.created,
        reused: diffResult.reused,
        removed: diffResult.removed,
        processingTime: stopwatch.elapsed,
      );

      // Update notifier. For the first non-empty render, bypass throttle to ensure
      // immediate visibility of markers.
    if (diffResult.created > 0 ||
      diffResult.removed > 0 ||
      diffResult.modified > 0 ||
      _markersNotifier.value.length != diffResult.markers.length) {
        if (kDebugMode) {
          debugPrint('[MapPage] 📊 $diffResult');
          debugPrint(
            '[MapPage] ⚡ Processing: ${stopwatch.elapsedMilliseconds}ms',
          );
        }
        final isFirstNonEmpty = _markersNotifier.value.isEmpty &&
            diffResult.markers.isNotEmpty;
        if (isFirstNonEmpty || diffResult.modified > 0) {
          _markersNotifier.forceUpdate(diffResult.markers);
        } else {
          _markersNotifier.value = diffResult.markers;
        }
      } else if (kDebugMode && diffResult.reused > 0) {
        debugPrint(
          '[MapPage] ♻️  All ${diffResult.reused} markers reused (no update)',
        );
      }
    } catch (e, stackTrace) {
      if (kDebugMode) {
        debugPrint('[MapPage] ❌ Marker processing error: $e');
        debugPrint('[MapPage] Stack trace: $stackTrace');
      }
    }
  }

  double? _asDouble(dynamic v) {
    if (v == null) return null;
    if (v is double) return v;
    if (v is int) return v.toDouble();
    if (v is String) return double.tryParse(v);
    return null;
  }

  // DEFENSIVE: Validate coordinates are not null, NaN, or out of range
  bool _valid(double? lat, double? lon) =>
      lat != null &&
      lon != null &&
      !lat.isNaN &&
      !lon.isNaN &&
      lat.isFinite &&
      lon.isFinite &&
      lat >= -90 &&
      lat <= 90 &&
      lon >= -180 &&
      lon <= 180;

  void _onMarkerTap(String id) {
    final n = int.tryParse(id);
    if (n == null) return;

    // Trigger fresh fetch for this device immediately
    refreshDevice(n);

    setState(() {
      if (_selectedIds.contains(n)) {
        _selectedIds.remove(n);
      } else {
        _selectedIds.add(n);
      }
    });

    // Ensure we have a position for this tapped/selected device
    // Fire-and-forget to enrich markers without blocking UI
    unawaited(_ensureSelectedDevicePositions({n}));

    // CRITICAL FIX: Trigger immediate camera fit after device selection
    // This ensures the camera moves immediately to show the selected device(s)
    // without waiting for the throttled didUpdateWidget in FlutterMapAdapter
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _mapKey.currentState?.fitCameraImmediate();
    });

    // OPTIMIZATION: Trigger marker update with new selection state
    final devicesAsync = ref.read(devicesNotifierProvider);
    devicesAsync.whenData(_triggerMarkerUpdate);

    // New: if multiple devices are near the tapped one (within ~40m),
    // show a spiderfy overlay for quick disambiguation.
    _maybeShowSpiderfyForNearby(n);
  }

  // Group nearby markers around a tapped device and show spiderfy overlay for small groups
  void _maybeShowSpiderfyForNearby(int tappedId) {
    // Build a local list of nearby devices within ~40 meters
    const distanceMeters = 40;
    // Haversine approximation using latlong2 Distance
    const d = Distance();

    // Current merged positions from our local cache (built by listeners)
    final positions = Map<int, Position>.from(_lastPositions);
    if (positions.length <= 1) return; // nothing to group

    final center = positions[tappedId];
    if (center == null) return;
    final centerLL = LatLng(center.latitude, center.longitude);

    // Find members within radius
    final memberIds = <int>[];
    for (final entry in positions.entries) {
      if (entry.key == tappedId) {
        memberIds.add(entry.key);
        continue;
      }
      final p = entry.value;
      final ll = LatLng(p.latitude, p.longitude);
      final meters = d.as(LengthUnit.Meter, centerLL, ll);
      if (meters <= distanceMeters) memberIds.add(entry.key);
      if (memberIds.length > 5) break; // spiderfy only for small groups
    }

    if (memberIds.length <= 1 || memberIds.length > 5) return;

    // Build ClusterableMarker list
    final members = <ClusterableMarker>[];
    for (final id in memberIds) {
      final p = positions[id]!;
      members.add(
        ClusterableMarker(
          id: '$id',
          position: LatLng(p.latitude, p.longitude),
          metadata: {'deviceId': id},
        ),
      );
    }

    // Show overlay at center
    SpiderfyOverlay.show(
      context,
      center: centerLL,
      members: members,
    );
  }

  void _onMapTap() {
    var changed = false;
    if (_selectedIds.isNotEmpty) {
      _selectedIds.clear();
      changed = true;

      // OPTIMIZATION: Trigger marker update when selection cleared
      final devicesAsync = ref.read(devicesNotifierProvider);
      devicesAsync.whenData(_triggerMarkerUpdate);
    }
    if (!_editing && _showSuggestions) {
      _showSuggestions = false;
      changed = true;
    }
    if (changed) setState(() {});
  }

  /// Show layer selection menu
  void _showLayerMenu(BuildContext context, MapTileSource activeLayer) {
    final notifier = ref.read(mapTileSourceProvider.notifier);
    final button = context.findRenderObject()! as RenderBox;
    final overlay = Navigator.of(context).overlay!.context.findRenderObject()! as RenderBox;
    final position = RelativeRect.fromRect(
      Rect.fromPoints(
        button.localToGlobal(Offset.zero, ancestor: overlay),
        button.localToGlobal(button.size.bottomRight(Offset.zero), ancestor: overlay),
      ),
      Offset.zero & overlay.size,
    );

    showMenu<MapTileSource>(
      context: context,
      position: position,
      items: MapTileProviders.all.map((source) {
        return PopupMenuItem<MapTileSource>(
          value: source,
          child: Row(
            children: [
              Icon(
                source.id == MapTileProviders.esriSatellite.id
                    ? Icons.satellite_alt
                    : Icons.map,
                size: 20,
              ),
              const SizedBox(width: 12),
              Expanded(child: Text(source.name)),
              if (source.id == activeLayer.id)
                const Icon(Icons.check, size: 18, color: Color(0xFFA6CD27)),
            ],
          ),
        );
      }).toList(),
    ).then((selectedSource) {
      if (selectedSource != null) {
        if (kDebugMode) {
          debugPrint('[TOGGLE] User switched to ${selectedSource.id} (${selectedSource.name})');
        }
        notifier.setSource(selectedSource);
      }
    });
  }

  // Ensure we have last-known positions for the given selected devices by
  // asking the PositionsService for latest positions. This supplements
  // WebSocket and DAO data when they are unavailable.
  Future<void> _ensureSelectedDevicePositions(Set<int> deviceIds) async {
    if (!mounted || deviceIds.isEmpty) return;
    try {
      final service = ref.read(positionsServiceProvider);
      final list = await service.fetchLatestPositions(
        deviceIds: deviceIds.toList(),
        // Keep defaults for freshness and concurrency
      );
      if (list.isEmpty) return;
      // Update local last positions map
      for (final p in list) {
        _lastPositions[p.deviceId] = p;
      }
      // Trigger marker update after enrichment
      final devices = ref.read(devicesNotifierProvider).asData?.value;
      if (devices != null) {
        _triggerMarkerUpdate(devices);
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[MapPage] _ensureSelectedDevicePositions error: $e');
      }
    }
  }

  void _focusSelected() =>
      setState(() {}); // triggers rebuild to adjust camera fit

  String _deviceStatus(Map<String, dynamic>? device, Position? pos) {
    final raw = device?['status']?.toString().toLowerCase();
    if (raw == 'online' || raw == 'offline' || raw == 'unknown') return raw!;
    DateTime? last;
    final lu = device?['lastUpdateDt'];
    if (lu is DateTime) last = lu.toUtc();
    if (pos != null) {
      final pt = pos.deviceTime.toUtc();
      if (last == null || pt.isAfter(last)) last = pt;
    }
    if (last == null) return 'unknown';
    final age = DateTime.now().toUtc().difference(last);
    if (age < const Duration(minutes: 5)) return 'online';
    if (age < const Duration(hours: 12)) return 'offline';
    return 'unknown';
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'online':
        return const Color(0xFFA6CD27);
      case 'offline':
        return const Color(0xFFFF383C);
      default:
        return const Color(0xFF49454F);
    }
  }

  String _formatRelativeAge(DateTime? dt) {
    if (dt == null) return 'n/a';
    final diff = DateTime.now().difference(dt);
    if (diff.inSeconds < 60) return '${diff.inSeconds}s ago';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    final d = diff.inDays;
    if (d < 7) return '${d}d ago';
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
  }

  // ---------- Build ----------
  @override
  Widget build(BuildContext context) {
    // CRITICAL FIX: Setup position update listeners in build method
    // ref.listen() must be called in build method, not in initState
    _setupPositionListenersInBuild();
    
    var content = _buildMapContent();

    // Add performance profiling overlay (disabled by default)
    if (MapDebugFlags.showRebuildOverlay) {
      content = RebuildProfilerOverlay(
        child: RebuildCounter(
          name: 'FlutterMap',
          child: content,
        ),
      );
    }

    return content;
  }

  /// Setup position listeners for all devices (called in build method)
  /// This ensures markers update when positions change via WebSocket
  void _setupPositionListenersInBuild() {
    final devicesAsync = ref.watch(devicesNotifierProvider);
    final devices = devicesAsync.asData?.value ?? [];
    var newlyAdded = 0;
    // Watch each device's position to trigger marker updates
    for (final device in devices) {
      final deviceId = device['id'] as int?;
      if (deviceId == null) continue;
      if (_positionListenerIds.contains(deviceId)) continue;
      // Watch position changes - this will trigger rebuild and marker update
      ref.listen(vehiclePositionProvider(deviceId), (previous, next) {
        if (!mounted) return;
        
        if (kDebugMode) {
          debugPrint('[MAP] Position changed for device $deviceId, triggering marker update');
        }
        final pos = next.valueOrNull;
        if (pos != null) {
          _lastPositions[deviceId] = pos;
        }
        
        // Trigger marker update when position changes
        final currentDevices = ref.read(devicesNotifierProvider).asData?.value ?? [];
        _triggerMarkerUpdate(currentDevices);
      });
      _positionListenerIds.add(deviceId);
      newlyAdded++;
    }
    if (kDebugMode && newlyAdded > 0) {
      debugPrint('[MAP] Registered $newlyAdded new position listeners (total: ${_positionListenerIds.length})');
    }
  }

  Widget _buildMapContent() {
    // PERFORMANCE: Track rebuilds for validation (disabled by default)
    if (MapDebugFlags.showRebuildOverlay) {
      RebuildTracker.instance.trackRebuild('MapPage');
    }

    // ASYNC OPTIMIZATION: Use FleetMapTelemetryController if enabled
    if (MapDebugFlags.useFMTCController) {
      return _buildMapContentWithFMTC();
    }

    // Watch entire devices list only once; consider splitting into smaller providers later
    final devicesAsync = ref.watch(devicesNotifierProvider);

    // MIGRATION: Repository-backed position watching (replaces positionsLiveProvider + positionsLastKnownProvider)
    // Build positions map from per-device snapshots (cache-first, WebSocket updates)
    final devices = devicesAsync.asData?.value ?? [];
    final positions = <int, Position>{};
    for (final device in devices) {
      final deviceId = device['id'] as int?;
      if (deviceId == null) continue;

      // Watch per-device position (cache-first, triggers on WebSocket updates)
      // vehiclePositionProvider is now StreamProvider, so get AsyncValue and extract value
      final asyncPosition = ref.watch(vehiclePositionProvider(deviceId));
      final position = asyncPosition.valueOrNull;
      if (position != null) {
        positions[deviceId] = position;
      }
    }

    // Use marker cache to memoize marker creation
    // Note: markerCache not used directly anymore - background isolate handles it

    return Scaffold(
      body: SafeArea(
        child: devicesAsync.when(
          data: (devices) {
            // OPTIMIZATION: Removed _processMarkersAsync from build method
            // Marker processing now happens via listeners (see _setupMarkerUpdateListeners)
            // This prevents unnecessary processing during widget rebuilds

            // Use current marker value from notifier for UI decisions
            final currentMarkers = _markersNotifier.value;
            final q = _query.trim().toLowerCase();

            // If exactly one device is selected, center to its position IMMEDIATELY
            if (_selectedIds.length == 1) {
              final sid = _selectedIds.first;

              // Try to get position from provider (live or last-known)
              final merged = ref.watch(positionByDeviceProvider(sid));
              double? targetLat;
              double? targetLon;

              if (merged != null && _valid(merged.latitude, merged.longitude)) {
                targetLat = merged.latitude;
                targetLon = merged.longitude;
              } else {
                // Fallback to device's stored lat/lon if no position data
                final device = ref.read(deviceByIdProvider(sid));
                final lat = _asDouble(device?['latitude']);
                final lon = _asDouble(device?['longitude']);
                if (_valid(lat, lon)) {
                  targetLat = lat;
                  targetLon = lon;
                }
              }

              // Center camera if we have valid coordinates
              if (targetLat != null && targetLon != null) {
                final selectionChanged = _lastSelectedSingleDevice != sid;
                if (selectionChanged) {
                  _lastSelectedSingleDevice = sid;
                  // OPTIMIZATION: Use smooth camera move for better UX
                  final lat = targetLat;
                  final lon = targetLon;
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    _smoothMoveTo(
                      LatLng(lat, lon),
                    );
                  });
                }
              } else {
                // Device has no location data - show a message
                final selectionChanged = _lastSelectedSingleDevice != sid;
                if (selectionChanged) {
                  _lastSelectedSingleDevice = sid;
                  // Show snackbar to inform user
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (!mounted) return;
                    final device = ref.read(deviceByIdProvider(sid));
                    final deviceName = device?['name'] ?? 'Device $sid';
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          '$deviceName has no location data yet',
                        ),
                        duration: const Duration(seconds: 3),
                        backgroundColor: Colors.orange,
                      ),
                    );
                  });
                }
              }
            } else {
              _lastSelectedSingleDevice = null;
            }

            // Camera fit with defensive NaN checks
            MapCameraFit fit;
            final selectedMarkers = _selectedIds.isEmpty
                ? <MapMarkerData>[]
                : currentMarkers
                    .where(
                      (m) => _selectedIds.contains(int.tryParse(m.id) ?? -1),
                    )
                    .toList();
            final target =
                selectedMarkers.isNotEmpty ? selectedMarkers : currentMarkers;
            
            // DEFENSIVE: Filter out markers with invalid positions
            final validTarget = target
                .where((m) => _valid(m.position.latitude, m.position.longitude))
                .toList();
            
            if (validTarget.isEmpty) {
              // No valid markers - use safe default
              fit = const MapCameraFit(center: LatLng(33.5731, -7.5898)); // Casablanca
            } else if (validTarget.length == 1) {
              fit = MapCameraFit(center: validTarget.first.position);
            } else {
              fit = MapCameraFit(
                boundsPoints: [for (final m in validTarget) m.position],
              );
            }

            // Deep link autofocus one-time
            if (!_didAutoFocus &&
                widget.preselectedIds != null &&
                widget.preselectedIds!.isNotEmpty) {
              final hasAny = currentMarkers.any(
                (m) =>
                    widget.preselectedIds!.contains(int.tryParse(m.id) ?? -1),
              );
              if (hasAny) {
                _didAutoFocus = true;
                // CRITICAL FIX: Camera must move IMMEDIATELY to show preselected devices
                // The map adapter's initState will handle immediate fitting via _maybeFit(immediate: true)
                // No need to delay or throttle here - just mark as focused
              }
            }

            // Suggestions list
            final suggestions = _showSuggestions
                ? [
                    if (_query.isEmpty || 'all devices'.contains(q))
                      {'__all__': true, 'name': 'All devices'},
                    ...devices.where((d) {
                      final n = d['name']?.toString().toLowerCase() ?? '';
                      return _query.isEmpty || n.contains(q);
                    }),
                  ]
                : const <Map<String, dynamic>>[];

            return Stack(
              children: [
                // OPTIMIZATION: Wrap map in RepaintBoundary for snapshot capture
                RepaintBoundary(
                  key: _snapshotKey,
                  child: FlutterMapAdapter(
                    key: _mapKey,
                    markers: currentMarkers,
                    cameraFit: fit,
                    onMarkerTap: _onMarkerTap,
                    onMapTap: _onMapTap,
                    markersNotifier:
                        _markersNotifier, // OPTIMIZATION: Use throttled ValueNotifier
                  ),
                ),
                // Clustering HUD (non-intrusive)
                const Positioned(
                  left: 12,
                  bottom: 12,
                  child: ClusterHud(),
                ),
                // OPTIMIZATION: Show cached snapshot overlay during initial load
                if (MapDebugFlags.showSnapshotOverlay &&
                    _isShowingSnapshot &&
                    _cachedSnapshot != null)
                  Positioned.fill(
                    child: ColoredBox(
                      color: Colors.white,
                      child: Stack(
                        children: [
                          Image.memory(
                            _cachedSnapshot!.imageBytes,
                            fit: BoxFit.cover,
                            gaplessPlayback: true,
                          ),
                          Positioned(
                            bottom: 16,
                            left: 16,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 8,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.7),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      valueColor: AlwaysStoppedAnimation<Color>(
                                        Colors.white,
                                      ),
                                    ),
                                  ),
                                  SizedBox(width: 8),
                                  Text(
                                    'Loading map tiles...',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                if (MapDebugFlags.showRebuildOverlay)
                  const Positioned(
                    top: 56,
                    left: 16,
                    child: _RebuildBadge(label: 'MapPage'),
                  ),
                // Search + suggestions
                Positioned(
                  top: 12,
                  left: 16,
                  right: 88,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _SearchBar(
                        controller: _searchCtrl,
                        focusNode: _focusNode,
                        editing: _editing,
                        suggestionsVisible: _showSuggestions,
                        onChanged: (v) => _searchDebouncer.run(
                          () {
                            setState(() => _query = v);
                            // OPTIMIZATION: Trigger marker update with new query
                            final devicesAsync =
                                ref.read(devicesNotifierProvider);
                            devicesAsync.whenData(_triggerMarkerUpdate);
                          },
                        ),
                        onClear: () {
                          _searchCtrl.clear();
                          _searchDebouncer.run(() {
                            setState(() => _query = '');
                            // OPTIMIZATION: Trigger marker update when query cleared
                            final devicesAsync =
                                ref.read(devicesNotifierProvider);
                            devicesAsync.whenData(_triggerMarkerUpdate);
                          });
                        },
                        onRequestEdit: () {
                          setState(() {
                            _editing = true;
                            _showSuggestions = true;
                          });
                          FocusScope.of(context).requestFocus(_focusNode);
                        },
                        onCloseEditing: () {
                          setState(() => _editing = false);
                          _focusNode.unfocus();
                        },
                        onSingleTap: () {
                          if (!_showSuggestions) {
                            setState(() => _showSuggestions = true);
                          }
                        },
                        onDoubleTap: () {
                          if (!_editing) {
                            setState(() {
                              _editing = true;
                              _showSuggestions = true;
                            });
                            FocusScope.of(context).requestFocus(_focusNode);
                          }
                        },
                        onToggleSuggestions: () => setState(
                          () => _showSuggestions = !_showSuggestions,
                        ),
                      ),
                      AnimatedSize(
                        duration: const Duration(milliseconds: 200),
                        curve: Curves.easeInOut,
                        child: suggestions.isNotEmpty
                            ? Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const SizedBox(height: 5),
                                  RepaintBoundary(
                                    child: Container(
                                      decoration: BoxDecoration(
                                        color: Colors.white,
                                        borderRadius:
                                            const BorderRadius.vertical(
                                          bottom: Radius.circular(22),
                                        ),
                                        border:
                                            Border.all(color: Colors.black12),
                                      ),
                                      constraints: const BoxConstraints(
                                        maxHeight: 260,
                                      ),
                                      child: ListView.builder(
                                        shrinkWrap: true,
                                        itemCount: suggestions.length,
                                        itemBuilder: (ctx, i) {
                                          final d = suggestions[i];
                                          if (d['__all__'] == true) {
                                            final total = devices.length;
                                            final allSelected =
                                                _selectedIds.length == total &&
                                                    total > 0;
                                            final someSelected =
                                                _selectedIds.isNotEmpty &&
                                                    !allSelected;
                                            return CheckboxListTile(
                                              key: const ValueKey('__all__'),
                                              dense: true,
                                              tristate: true,
                                              controlAffinity:
                                                  ListTileControlAffinity
                                                      .leading,
                                              title:
                                                  Text('All devices ($total)'),
                                              value: allSelected
                                                  ? true
                                                  : (someSelected
                                                      ? null
                                                      : false),
                                              onChanged: (_) {
                                                setState(() {
                                                  if (allSelected) {
                                                    _selectedIds.clear();
                                                  } else {
                                                    _selectedIds
                                                      ..clear()
                                                      ..addAll(
                                                        devices
                                                            .map((e) => e['id'])
                                                            .whereType<int>(),
                                                      );
                                                  }
                                                });
                                                // Trigger marker update after selection change
                                                final devicesAsync = ref.read(devicesNotifierProvider);
                                                devicesAsync.whenData(_triggerMarkerUpdate);
                                                // Ensure we have positions for selected devices (fire-and-forget)
                                                if (!allSelected && _selectedIds.isNotEmpty) {
                                                  unawaited(_ensureSelectedDevicePositions(_selectedIds));
                                                }
                                              },
                                            );
                                          }
                                          final name =
                                              d['name']?.toString() ?? 'Device';
                                          final idRaw = d['id'];
                                          final id = (idRaw is int)
                                              ? idRaw
                                              : int.tryParse(
                                                  idRaw?.toString() ?? '',
                                                );
                                          final pos =
                                              id == null ? null : positions[id];
                                          final lat = pos?.latitude ??
                                              _asDouble(d['latitude']);
                                          final lon = pos?.longitude ??
                                              _asDouble(d['longitude']);
                                          final hasCoords = _valid(lat, lon);
                                          final selected = id != null &&
                                              _selectedIds.contains(id);
                                          DateTime? last;
                                          final devLast = d['lastUpdateDt'];
                                          if (devLast is DateTime) {
                                            last = devLast.toLocal();
                                          }
                                          final posTime =
                                              pos?.deviceTime.toLocal();
                                          if (posTime != null &&
                                              (last == null ||
                                                  posTime.isAfter(last))) {
                                            last = posTime;
                                          }
                                          final subtitle = last == null
                                              ? 'No update yet'
                                              : 'Updated ${_formatRelativeAge(last)}';
                                          return CheckboxListTile(
                                            key: ValueKey('sugg_${id ?? name}'),
                                            dense: true,
                                            controlAffinity:
                                                ListTileControlAffinity.leading,
                                            value: selected,
                                            title: Text(
                                              name,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                            subtitle: Text(subtitle),
                                            onChanged: id == null
                                                ? null
                                                : (val) {
                                                    setState(() {
                                                      if (val ?? false) {
                                                        _selectedIds.add(id);
                                                      } else {
                                                        _selectedIds.remove(id);
                                                      }
                                                    });
                                                    // Immediately center on selected device
                                                    if (hasCoords &&
                                                        (val ?? false)) {
                                                      // Direct synchronous update for instant response
                                                      _mapKey.currentState
                                                          ?.moveTo(
                                                        LatLng(lat!, lon!),
                                                      );
                                                    }
                                                    // Ensure we have a position for this selected device
                                                    if (val ?? false) {
                                                      unawaited(_ensureSelectedDevicePositions({id}));
                                                    }
                                                    // Trigger marker update after selection change
                                                    final devicesAsync = ref.read(devicesNotifierProvider);
                                                    devicesAsync.whenData(_triggerMarkerUpdate);
                                                  },
                                          );
                                        },
                                      ),
                                    ),
                                  ),
                                ],
                              )
                            : const SizedBox.shrink(),
                      ),
                    ],
                  ),
                ),
                // Map action buttons
                Positioned(
                  top: 12,
                  right: 16,
                  child: Column(
                    children: [
                      _ActionButton(
                        icon: Icons.refresh,
                        tooltip: 'Refresh data',
                        isLoading: _isRefreshing,
                        onTap: () async {
                          if (_isRefreshing) return;

                          setState(() => _isRefreshing = true);

                          try {
                            // 1) Refresh static data from Traccar (devices list)
                            await ref
                                .read(devicesNotifierProvider.notifier)
                                .refresh();

                            // 2) Refresh repository (re-fetch positions from REST + reconnect WebSocket)
                            final repo =
                                ref.read(vehicleDataRepositoryProvider);
                            final devices = ref
                                    .read(devicesNotifierProvider)
                                    .asData
                                    ?.value ??
                                [];
                            final deviceIds = devices
                                .map((d) => d['id'] as int?)
                                .whereType<int>()
                                .toList();

                            if (deviceIds.isNotEmpty) {
                              unawaited(repo.refreshAll());
                              await repo.fetchMultipleDevices(deviceIds);
                            }

                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Data refreshed successfully'),
                                  duration: Duration(seconds: 2),
                                  backgroundColor: Color(0xFFA6CD27),
                                ),
                              );
                            }
                          } catch (e) {
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text('Refresh failed: $e'),
                                  duration: const Duration(seconds: 3),
                                  backgroundColor: Colors.redAccent,
                                ),
                              );
                            }
                          } finally {
                            if (mounted) {
                              setState(() => _isRefreshing = false);
                            }
                          }
                        },
                      ),
                      const SizedBox(height: 8),
                      _ActionButton(
                        icon: Icons.center_focus_strong,
                        tooltip: _selectedIds.isNotEmpty
                            ? 'Auto-zoom to selected'
                            : 'Auto-zoom (all devices)',
                        onTap: () {
                          // Call the public auto-zoom method on FlutterMapAdapter
                          _mapKey.currentState?.autoZoomToSelected();
                        },
                      ),
                      const SizedBox(height: 8),
                      // Layer toggle button
                      Builder(
                        builder: (context) {
                          final activeLayer = ref.watch(mapTileSourceProvider);
                          return _ActionButton(
                            icon: Icons.layers,
                            tooltip: 'Map layer: ${activeLayer.name}',
                            onTap: () {
                              _showLayerMenu(context, activeLayer);
                            },
                          );
                        },
                      ),
                    ],
                  ),
                ),
                // Offline network banner (appears at top when network is offline)
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: _OfflineBanner(
                    networkState: ref.watch(networkStateProvider),
                    connectionStatus: ref.watch(connectionStatusProvider),
                  ),
                ),
                // Bottom multi-snap panel
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 200),
                    child: _selectedIds.isEmpty
                        ? const SizedBox.shrink()
                        : LayoutBuilder(
                            key: ValueKey(_selectedIds.hashCode ^ _panelIndex),
                            builder: (ctx, _) {
                              final screenH = MediaQuery.of(
                                context,
                              ).size.height;
                              final height =
                                  (screenH * _panelStops[_panelIndex]).clamp(
                                90.0,
                                screenH * 0.9,
                              );
                              return GestureDetector(
                                onVerticalDragEnd: (details) {
                                  final v = details.primaryVelocity ?? 0;
                                  if (v > 250) {
                                    setState(
                                      () => _panelIndex = (_panelIndex - 1)
                                          .clamp(0, _panelStops.length - 1),
                                    );
                                  } else if (v < -250) {
                                    setState(
                                      () => _panelIndex = (_panelIndex + 1)
                                          .clamp(0, _panelStops.length - 1),
                                    );
                                  }
                                },
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 200),
                                  curve: Curves.easeOut,
                                  height: height,
                                  width: double.infinity,
                                  padding: const EdgeInsets.fromLTRB(
                                    16,
                                    10,
                                    16,
                                    16,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: const BorderRadius.vertical(
                                      top: Radius.circular(24),
                                    ),
                                    border: Border.all(
                                      color: const Color(0xFFA6CD27),
                                      width: 2,
                                    ),
                                  ),
                                  child: Column(
                                    children: [
                                      InkWell(
                                        onTap: () => setState(
                                          () => _panelIndex =
                                              (_panelIndex + 1) %
                                                  _panelStops.length,
                                        ),
                                        borderRadius: BorderRadius.circular(40),
                                        child: Padding(
                                          padding: const EdgeInsets.only(
                                            top: 4,
                                            bottom: 8,
                                          ),
                                          child: Container(
                                            width: 56,
                                            height: 6,
                                            decoration: BoxDecoration(
                                              color: Colors.grey[400],
                                              borderRadius:
                                                  BorderRadius.circular(40),
                                            ),
                                          ),
                                        ),
                                      ),
                                      Expanded(
                                        child: ClipRect(
                                          child: SingleChildScrollView(
                                            padding: EdgeInsets.zero,
                                            physics:
                                                const BouncingScrollPhysics(),
                                            child: RepaintBoundary(
                                              child: AnimatedSwitcher(
                                                duration: const Duration(
                                                  milliseconds: 220,
                                                ),
                                                switchInCurve: Curves.easeInOut,
                                                switchOutCurve:
                                                    Curves.easeInOut,
                                                transitionBuilder:
                                                    (child, animation) {
                                                  final slide = Tween<Offset>(
                                                    begin:
                                                        const Offset(0, 0.02),
                                                    end: Offset.zero,
                                                  ).animate(animation);
                                                  return FadeTransition(
                                                    opacity: animation,
                                                    child: SlideTransition(
                                                      position: slide,
                                                      child: child,
                                                    ),
                                                  );
                                                },
                                                child: _selectedIds.length == 1
                                                    ? _InfoBox(
                                                        key: const ValueKey(
                                                          'single-info',
                                                        ),
                                                        deviceId:
                                                            _selectedIds.first,
                                                        devices: devices,
                                                        position: ref.watch(
                                                          positionByDeviceProvider(
                                                            _selectedIds.first,
                                                          ),
                                                        ),
                                                        statusResolver:
                                                            _deviceStatus,
                                                        statusColorBuilder:
                                                            _statusColor,
                                                        onClose: () => setState(
                                                          _selectedIds.clear,
                                                        ),
                                                        onFocus: _focusSelected,
                                                      )
                                                    : _MultiSelectionInfoBox(
                                                        key: const ValueKey(
                                                          'multi-info',
                                                        ),
                                                        selectedIds:
                                                            _selectedIds,
                                                        devices: devices,
                                                        positions: positions,
                                                        statusResolver:
                                                            _deviceStatus,
                                                        statusColorBuilder:
                                                            _statusColor,
                                                        onClear: () => setState(
                                                          _selectedIds.clear,
                                                        ),
                                                        onFocus: _focusSelected,
                                                      ),
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                      if (_panelIndex == 0)
                                        Padding(
                                          padding: const EdgeInsets.only(
                                            top: 6,
                                          ),
                                          child: Text(
                                            'Tap or swipe up for more',
                                            style: Theme.of(
                                              context,
                                            ).textTheme.labelSmall,
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                  ),
                ),
              ],
            );
          },
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, st) => Center(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text('Failed to load devices for map: $e'),
            ),
          ),
        ),
      ),
    );
  }

  /// ASYNC OPTIMIZATION: Build map content using FleetMapTelemetryController
  /// This version uses AsyncNotifier for non-blocking device loading
  Widget _buildMapContentWithFMTC() {
    final fmState = ref.watch(fleetMapTelemetryControllerProvider);

    return fmState.when(
      // Loading state - show centered spinner
      loading: () {
        return Scaffold(
          body: SafeArea(
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const CircularProgressIndicator(),
                  const SizedBox(height: 16),
                  Text(
                    'Loading fleet data...',
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                ],
              ),
            ),
          ),
        );
      },

      // Error state - show error message with retry button
      error: (error, stackTrace) {
        if (kDebugMode) {
          debugPrint('[FMTC] Error in UI: $error');
          debugPrint('[FMTC] Stack: $stackTrace');
        }

        return Scaffold(
          body: SafeArea(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(
                      Icons.error_outline,
                      size: 64,
                      color: Colors.red,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Failed to load fleet data',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      error.toString(),
                      style: Theme.of(context).textTheme.bodyMedium,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 24),
                    ElevatedButton.icon(
                      onPressed: () {
                        ref
                            .read(fleetMapTelemetryControllerProvider.notifier)
                            .refreshDevices();
                      },
                      icon: const Icon(Icons.refresh),
                      label: const Text('Retry'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },

      // Data state - render map with devices
      data: (fmtcState) {
        if (kDebugMode) {
          debugPrint(
            '[FMTC] Rendering with ${fmtcState.devices.length} devices (updated: ${fmtcState.lastUpdated})',
          );
        }

        final devices = fmtcState.devices;
        final positions = <int, Position>{};

        // Build positions map from per-device snapshots
        for (final device in devices) {
          final deviceId = device['id'] as int?;
          if (deviceId == null) continue;

          final asyncPosition = ref.watch(vehiclePositionProvider(deviceId));
          final position = asyncPosition.valueOrNull;
          if (position != null) {
            positions[deviceId] = position;
          }
        }

        // Process markers asynchronously
        _processMarkersAsync(positions, devices, _selectedIds, _query);

        // Continue with existing map rendering logic
        final currentMarkers = _markersNotifier.value;

        // Single device selection centering logic
        if (_selectedIds.length == 1) {
          final sid = _selectedIds.first;
          final merged = ref.watch(positionByDeviceProvider(sid));
          double? targetLat;
          double? targetLon;

          if (merged != null && _valid(merged.latitude, merged.longitude)) {
            targetLat = merged.latitude;
            targetLon = merged.longitude;
          } else {
            final device = ref.read(deviceByIdProvider(sid));
            final lat = _asDouble(device?['latitude']);
            final lon = _asDouble(device?['longitude']);
            if (_valid(lat, lon)) {
              targetLat = lat;
              targetLon = lon;
            }
          }

          if (targetLat != null && targetLon != null) {
            final selectionChanged = _lastSelectedSingleDevice != sid;
            if (selectionChanged) {
              _lastSelectedSingleDevice = sid;
              final lat = targetLat;
              final lon = targetLon;
              WidgetsBinding.instance.addPostFrameCallback((_) {
                // OPTIMIZATION: Use smooth camera move
                _smoothMoveTo(LatLng(lat, lon));
              });
            }
          }
        } else {
          _lastSelectedSingleDevice = null;
        }

        // Render the full map UI using existing _buildMapScaffold logic
        // (Simplified version - reuse scaffold structure from standard path)
        return Scaffold(
          body: SafeArea(
            child: Stack(
              children: [
                // OPTIMIZATION: Wrap map in RepaintBoundary for snapshot capture
                RepaintBoundary(
                  key: _snapshotKey,
                  child: FlutterMapAdapter(
                    key: _mapKey,
                    markers: currentMarkers,
                    cameraFit: MapCameraFit(
                      boundsPoints: currentMarkers.isNotEmpty
                          ? currentMarkers.map((m) => m.position).toList()
                          : [const LatLng(0, 0)],
                    ),
                  ),
                ),
                // OPTIMIZATION: Show cached snapshot overlay during initial load
                if (MapDebugFlags.showSnapshotOverlay &&
                    _isShowingSnapshot &&
                    _cachedSnapshot != null)
                  Positioned.fill(
                    child: Image.memory(
                      _cachedSnapshot!.imageBytes,
                      fit: BoxFit.cover,
                      gaplessPlayback: true,
                    ),
                  ),
                // TODO(my_app): Add full UI overlay (search bar, bottom panel, etc.)
                // For now, this shows the map with markers
              ],
            ),
          ),
        );
      },
    );
  }
}

// ---------------- UI COMPONENTS ----------------

class _SearchBar extends StatelessWidget {
  const _SearchBar({
    required this.controller,
    required this.onChanged,
    required this.onClear,
    required this.focusNode,
    required this.editing,
    required this.onRequestEdit,
    required this.onCloseEditing,
    required this.onSingleTap,
    required this.onDoubleTap,
    required this.onToggleSuggestions,
    required this.suggestionsVisible,
  });
  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;
  final FocusNode focusNode;
  final bool editing;
  final VoidCallback onRequestEdit;
  final VoidCallback onCloseEditing;
  final VoidCallback onSingleTap;
  final VoidCallback onDoubleTap;
  final VoidCallback onToggleSuggestions;
  final bool suggestionsVisible;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasText = controller.text.isNotEmpty;
    final active = editing || focusNode.hasFocus;
    final borderColor = active ? const Color(0xFFA6CD27) : Colors.black12;
    return GestureDetector(
      onTap: onSingleTap,
      onDoubleTap: onDoubleTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: borderColor, width: active ? 1.5 : 1),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        child: Row(
          children: [
            Icon(Icons.search, color: Colors.grey[700], size: 22),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: controller,
                focusNode: focusNode,
                readOnly: !editing,
                onChanged: onChanged,
                cursorColor: const Color(0xFF49454F),
                decoration: const InputDecoration(
                  isDense: true,
                  hintText: 'Search vehicle',
                  border: InputBorder.none,
                ),
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            InkWell(
              borderRadius: BorderRadius.circular(18),
              onTap: onToggleSuggestions,
              child: Padding(
                padding: const EdgeInsets.all(4),
                child: Icon(
                  suggestionsVisible ? Icons.expand_less : Icons.expand_more,
                  size: 20,
                  color: Colors.black54,
                ),
              ),
            ),
            if (hasText)
              InkWell(
                borderRadius: BorderRadius.circular(18),
                onTap: onClear,
                child: const Padding(
                  padding: EdgeInsets.all(4),
                  child: Icon(Icons.close, size: 20, color: Colors.black54),
                ),
              )
            else
              InkWell(
                borderRadius: BorderRadius.circular(18),
                onTap: () => editing ? onCloseEditing() : onRequestEdit(),
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: Icon(
                    editing ? Icons.keyboard_hide : Icons.keyboard,
                    size: 20,
                    color: Colors.black54,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.icon,
    required this.tooltip,
    this.onTap,
    this.isLoading = false,
  });
  final IconData icon;
  final String tooltip;
  final VoidCallback? onTap;
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
  final disabled = onTap == null || isLoading;
    final bg = disabled ? Colors.white.withValues(alpha: 0.6) : Colors.white;
    final fg = disabled ? Colors.black26 : Colors.black87;
    return Material(
      color: bg,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      elevation: 4,
      child: InkWell(
        onTap: disabled ? null : onTap,
        borderRadius: BorderRadius.circular(18),
        child: Tooltip(
          message: tooltip,
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: isLoading
                ? SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      valueColor: AlwaysStoppedAnimation<Color>(fg),
                    ),
                  )
                : Icon(icon, size: 22, color: fg),
          ),
        ),
      ),
    );
  }
}

class _InfoBox extends StatelessWidget {
  const _InfoBox({
    required this.deviceId,
    required this.devices,
    required this.position,
    required this.statusResolver,
    required this.statusColorBuilder,
    required this.onClose,
    super.key,
    this.onFocus,
  });
  final int deviceId;
  final List<Map<String, dynamic>> devices;
  final Position? position;
  final String Function(Map<String, dynamic>?, Position?) statusResolver;
  final Color Function(String) statusColorBuilder;
  final VoidCallback onClose; // currently unused but reserved for close button
  final VoidCallback? onFocus;
  @override
  Widget build(BuildContext context) {
    assert(
      debugCheckHasDirectionality(context),
      '_InfoBox requires Directionality above in the tree',
    );
    String relativeAge(DateTime? dt) {
      if (dt == null) return 'n/a';
      final diff = DateTime.now().difference(dt);
      if (diff.inSeconds < 60) return '${diff.inSeconds}s ago';
      if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
      if (diff.inHours < 24) return '${diff.inHours}h ago';
      final d = diff.inDays;
      if (d < 7) return '${d}d ago';
      return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
    }

    var name = 'Device $deviceId';
    for (final d in devices) {
      if (d['id'] == deviceId) {
        name = d['name']?.toString() ?? name;
        break;
      }
    }
    var deviceMap = const <String, dynamic>{};
    for (final d in devices) {
      if (d['id'] == deviceId) {
        deviceMap = d;
        break;
      }
    }
    final status = statusResolver(deviceMap, position);
    final statusColor = statusColorBuilder(status);
    final engineAttr = position?.attributes['ignition'];
    final engine = engineAttr is bool ? (engineAttr ? 'on' : 'off') : '_';
    final speed = position?.speed.toStringAsFixed(0) ?? '--';
    final distanceAttr = position?.attributes['distance'] ??
        position?.attributes['totalDistance'];
    String distance;
    if (distanceAttr is num) {
      final km = distanceAttr / 1000;
      distance = km >= 0.1 ? km.toStringAsFixed(0) : '00';
    } else {
      distance = '--';
    }
    // Try to get coordinates from position, then fallback to device data
    final String lastLocation;
    final pos = position;
    if (pos != null) {
      final posAddress = pos.address;
      if (posAddress != null && posAddress.isNotEmpty) {
        lastLocation = posAddress;
      } else {
        lastLocation =
            '${pos.latitude.toStringAsFixed(5)}, ${pos.longitude.toStringAsFixed(5)}';
      }
    } else {
      // Fallback to device's stored lat/lon if no position
      final devLat = deviceMap['latitude'];
      final devLon = deviceMap['longitude'];
      if (devLat != null && devLon != null) {
        lastLocation = '$devLat, $devLon (stored)';
      } else {
        lastLocation = 'No location data available';
      }
    }
    final deviceTime = position?.deviceTime.toLocal();
    final lastUpdateDt = (deviceMap['lastUpdateDt'] is DateTime)
        ? (deviceMap['lastUpdateDt'] as DateTime).toLocal()
        : deviceTime;
    final lastAge = relativeAge(lastUpdateDt);
    return Material(
      borderRadius: BorderRadius.circular(16),
      color: Colors.white,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFE0E0E0)),
        ),
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    name,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          color: statusColor,
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Engine & Movement',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                          letterSpacing: .3,
                        ),
                  ),
                  const SizedBox(height: 4),
                  _InfoLine(
                    icon: Icons.power_settings_new,
                    label: 'Engine',
                    value: engine,
                    valueColor: engine == 'on' ? statusColor : null,
                  ),
                  _InfoLine(
                    icon: Icons.speed,
                    label: 'Speed',
                    value: speed == '--' ? '-- km/h' : '$speed km/h',
                  ),
                  _InfoLine(
                    icon: Icons.route,
                    label: 'Distance',
                    value: distance == '--' ? '-- km' : '$distance km',
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Last Location',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                          letterSpacing: .3,
                        ),
                  ),
                  const SizedBox(height: 4),
                  _InfoLine(
                    icon: Icons.place_outlined,
                    label: 'Coordinates',
                    value: lastLocation,
                    valueColor: lastLocation == 'No location data available'
                        ? Colors.orange
                        : null,
                  ),
                  _InfoLine(
                    icon: Icons.update,
                    label: 'Updated',
                    value: lastAge,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MultiSelectionInfoBox extends StatelessWidget {
  const _MultiSelectionInfoBox({
    required this.selectedIds,
    required this.devices,
    required this.positions,
    required this.statusResolver,
    required this.statusColorBuilder,
    required this.onClear,
    super.key,
    this.onFocus,
  });
  final Set<int> selectedIds;
  final List<Map<String, dynamic>> devices;
  final Map<int, Position> positions;
  final String Function(Map<String, dynamic>?, Position?) statusResolver;
  final Color Function(String) statusColorBuilder;
  final VoidCallback onClear;
  final VoidCallback? onFocus;
  @override
  Widget build(BuildContext context) {
    assert(
      debugCheckHasDirectionality(context),
      '_MultiSelectionInfoBox requires Directionality above in the tree',
    );
    final selectedDevices = devices
        .whereType<Map<String, dynamic>>()
        .where((d) => selectedIds.contains(d['id']))
        .toList();
    var online = 0;
    var offline = 0;
    var unknown = 0;
    for (final d in selectedDevices) {
      final s = statusResolver(d, positions[d['id']]);
      switch (s) {
        case 'online':
          online++;
        case 'offline':
          offline++;
        default:
          unknown++;
      }
    }
    final total = selectedDevices.length;
    final onlinePct = total == 0 ? 0 : (online / total * 100).round();
    return Material(
      borderRadius: BorderRadius.circular(16),
      color: Colors.white,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFE0E0E0)),
        ),
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Text(
                  '$total devices selected',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 12,
              runSpacing: 8,
              children: [
                _StatusStat(
                  label: 'Online',
                  count: online,
                  color: statusColorBuilder('online'),
                ),
                _StatusStat(
                  label: 'Offline',
                  count: offline,
                  color: statusColorBuilder('offline'),
                ),
                _StatusStat(
                  label: 'Unknown',
                  count: unknown,
                  color: statusColorBuilder('unknown'),
                ),
                Text(
                  'Online: $onlinePct%',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (selectedDevices.isNotEmpty)
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final d in selectedDevices.take(5))
                    _InfoLine(
                      icon: Icons.device_hub,
                      label: d['name']?.toString() ?? 'Device',
                      value: statusResolver(d, positions[d['id']]),
                      valueColor: statusColorBuilder(
                        statusResolver(d, positions[d['id']]),
                      ),
                    ),
                  if (selectedDevices.length > 5)
                    Text(
                      '+ ${selectedDevices.length - 5} more...',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class _InfoLine extends StatelessWidget {
  const _InfoLine({
    required this.icon,
    required this.label,
    required this.value,
    this.valueColor,
  });
  final IconData icon;
  final String label;
  final String value;
  final Color? valueColor;
  @override
  Widget build(BuildContext context) {
    final base = Theme.of(context).textTheme.bodySmall;
    final styleLabel = base?.copyWith(
      fontWeight: FontWeight.w500,
      color: Colors.grey[800],
    );
    final styleValue = base?.copyWith(
      fontWeight: FontWeight.w700,
      color: valueColor ?? Colors.black87,
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 28,
            alignment: Alignment.centerLeft,
            child: Icon(icon, size: 18, color: valueColor ?? Colors.black87),
          ),
          const SizedBox(width: 2),
          Text('$label: ', style: styleLabel),
          Expanded(
            child: Text(
              value,
              style: styleValue ?? base,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusStat extends StatelessWidget {
  const _StatusStat({
    required this.label,
    required this.count,
    required this.color,
  });
  final String label;
  final int count;
  final Color color;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          '$label: $count',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: color,
                fontWeight: FontWeight.w600,
              ),
        ),
      );
}

/// Offline banner widget that appears when network is unavailable
/// Shows connection status (offline/reconnecting/unstable)
class _OfflineBanner extends StatelessWidget {
  const _OfflineBanner({
    required this.networkState,
    required this.connectionStatus,
  });

  final NetworkState networkState;
  final ConnectionStatus connectionStatus;

  @override
  Widget build(BuildContext context) {
    // Determine what to show based on network and connection status
    final isOffline = networkState == NetworkState.offline;
    final isReconnecting = connectionStatus == ConnectionStatus.reconnecting;
    final isUnstable = connectionStatus == ConnectionStatus.unstable;

    // Only show banner if offline, reconnecting, or unstable
    if (!isOffline && !isReconnecting && !isUnstable) {
      return const SizedBox.shrink();
    }

    // Determine banner properties
    Color bgColor;
    IconData icon;
    String message;

    if (isOffline) {
      bgColor = Colors.red.shade700;
      icon = Icons.cloud_off;
      message = 'No network connection - Showing cached data';
    } else if (isUnstable) {
      bgColor = Colors.orange.shade700;
      icon = Icons.warning;
      message = 'Unstable connection - Reconnecting frequently';
    } else {
      // reconnecting
      bgColor = Colors.orange;
      icon = Icons.sync;
      message = 'Reconnecting to server...';
    }

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
      color: bgColor,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: SafeArea(
        bottom: false,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: Colors.white, size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Marker performance overlay showing cache efficiency and processing time
class _MarkerPerformanceOverlay extends StatefulWidget {
  const _MarkerPerformanceOverlay();

  @override
  State<_MarkerPerformanceOverlay> createState() =>
      _MarkerPerformanceOverlayState();
}

class _MarkerPerformanceOverlayState extends State<_MarkerPerformanceOverlay> {
  Timer? _updateTimer;

  @override
  void initState() {
    super.initState();
    // Update every 500ms
    _updateTimer = Timer.periodic(const Duration(milliseconds: 500), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _updateTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final stats = MarkerPerformanceMonitor.instance.getStats();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.green.withValues(alpha: 0.5)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '⚡ Marker Performance',
            style: TextStyle(
              color: Colors.green[300],
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          _StatRow(
            'Updates',
            stats.totalUpdates.toString(),
            Colors.white70,
          ),
          _StatRow(
            'Avg Time',
            '${stats.averageProcessingMs.toStringAsFixed(1)}ms',
            stats.averageProcessingMs < 16
                ? Colors.green[300]!
                : Colors.orange[300]!,
          ),
          _StatRow(
            'Reuse',
            '${(stats.averageReuseRate * 100).toStringAsFixed(0)}%',
            stats.averageReuseRate > 0.7
                ? Colors.green[300]!
                : Colors.orange[300]!,
          ),
          _StatRow(
            'Created',
            stats.totalCreated.toString(),
            Colors.white70,
          ),
          _StatRow(
            'Reused',
            stats.totalReused.toString(),
            Colors.green[300]!,
          ),
        ],
      ),
    );
  }
}

class _StatRow extends StatelessWidget {
  const _StatRow(this.label, this.value, this.color);

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          '$label: ',
          style: const TextStyle(color: Colors.white70, fontSize: 11),
        ),
        Text(
          value,
          style: TextStyle(
            color: color,
            fontSize: 11,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }
}
