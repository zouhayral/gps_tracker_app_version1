import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
// import 'package:flutter/physics.dart';
// import 'package:flutter_map/flutter_map.dart';
// import 'package:flutter_map_tile_caching/flutter_map_tile_caching.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';
import 'package:my_app_gps/core/data/vehicle_data_repository.dart';
import 'package:my_app_gps/core/diagnostics/frame_timing_summarizer.dart';
import 'package:my_app_gps/core/diagnostics/map_performance_monitor.dart';
import 'package:my_app_gps/core/diagnostics/performance_metrics_service.dart';
import 'package:my_app_gps/core/diagnostics/rebuild_tracker.dart';
import 'package:my_app_gps/core/map/bitmap_descriptor_cache.dart';
import 'package:my_app_gps/core/map/enhanced_marker_cache.dart';
import 'package:my_app_gps/core/map/fleet_map_prefetch.dart';
import 'package:my_app_gps/core/map/map_debug_flags.dart';
import 'package:my_app_gps/core/map/marker_cache.dart';
import 'package:my_app_gps/core/map/marker_icon_manager.dart';
import 'package:my_app_gps/core/map/marker_motion_controller.dart';
import 'package:my_app_gps/core/map/marker_performance_monitor.dart';
import 'package:my_app_gps/core/map/marker_processing_isolate.dart';
import 'package:my_app_gps/core/map/rebuild_profiler.dart';
import 'package:my_app_gps/core/providers/connectivity_providers.dart';
import 'package:my_app_gps/core/providers/vehicle_providers.dart';
import 'package:my_app_gps/core/utils/app_logger.dart';
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
import 'package:my_app_gps/features/map/providers/map_search_provider.dart';
import 'package:my_app_gps/features/map/view/flutter_map_adapter.dart';
import 'package:my_app_gps/features/map/view/map_debug_overlay.dart';
import 'package:my_app_gps/features/map/view/map_page_lifecycle_mixin.dart';
import 'package:my_app_gps/features/map/widgets/map_action_button.dart';
import 'package:my_app_gps/features/map/widgets/map_bottom_sheet.dart';
import 'package:my_app_gps/features/map/widgets/map_info_boxes.dart';
import 'package:my_app_gps/features/map/widgets/map_overlays.dart';
import 'package:my_app_gps/features/map/widgets/map_search_bar.dart';
import 'package:my_app_gps/features/notifications/view/notification_banner.dart';
import 'package:my_app_gps/map/map_tile_providers.dart';
import 'package:my_app_gps/map/map_tile_source_provider.dart';
import 'package:my_app_gps/services/fmtc_initializer.dart';
import 'package:my_app_gps/services/positions_service.dart';
import 'package:my_app_gps/services/websocket_manager.dart';
import 'package:url_launcher/url_launcher.dart';
// Removed SmoothSheetController; using direct controller-driven logic
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

class MapPage extends ConsumerStatefulWidget {
  const MapPage({super.key, this.preselectedIds});
  final Set<int>? preselectedIds;
  @override
  ConsumerState<MapPage> createState() => _MapPageState();
}

class _MapPageState extends ConsumerState<MapPage>
    with
        WidgetsBindingObserver,
        MapPageLifecycleMixin<MapPage>,
        AutomaticKeepAliveClientMixin<MapPage> {
  // Logger
  static final _log = 'MapPage'.logger;
  
  // TASK 6: Keep map alive to prevent frame drops during view transitions
  @override
  bool get wantKeepAlive => true;

  // Selection
  final Set<int> _selectedIds = <int>{};
  // Last-known positions captured by listeners to avoid timing gaps
  final Map<int, Position> _lastPositions = <int, Position>{};

  @override
  List<int> get activeDeviceIds => _selectedIds.toList();

  // Search / suggestions gating
  // OPTIMIZATION: Moved _query to mapSearchQueryProvider to prevent parent rebuilds
  final _searchCtrl = TextEditingController();
  final _focusNode = FocusNode();
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
  
  // OPTIMIZATION: Marker cache statistics
  int _cacheHits = 0;
  int _cacheMisses = 0;
  double get _cacheHitRate => _cacheHits + _cacheMisses == 0 
      ? 0.0 
      : _cacheHits / (_cacheHits + _cacheMisses);
  // Avoid re-registering position listeners every build which can cause churn
  final Set<int> _positionListenerIds = <int>{};
  // MIGRATION NOTE: Removed _debouncedPositions - repository provides debouncing
  // MIGRATION NOTE: Removed _fitThrottler - camera fit throttling now handled by FlutterMapAdapter
  // Track last selected device to detect changes
  int? _lastSelectedSingleDevice;

  // Store listener subscriptions for manual disposal
  final List<ProviderSubscription<dynamic>> _listenerCleanups = [];

  // OPTIMIZATION: Throttled ValueNotifier for marker updates (reduces rebuilds when updates <50ms apart)
  late final ThrottledValueNotifier<List<MapMarkerData>> _markersNotifier;

  // OPTIMIZATION: Enhanced marker cache with intelligent diffing
  // TASK 3: Using singleton instance for lifecycle persistence
  final _enhancedMarkerCache = EnhancedMarkerCache.instance;

  // LIVE MOTION FIX: MarkerMotionController for smooth position interpolation
  // Provides animated transitions between WebSocket updates (200ms tick, 1200ms interpolation)
  late final MarkerMotionController _motionController;

  // PERF PHASE 2: Marker update debouncing (collapses rapid bursts into single rebuild)
  // Unified: rely on ThrottledValueNotifier for marker update throttling

  // PERF PHASE 2: Map repaint throttling (caps re-paints to ~6 fps during heavy bursts)
  DateTime? _lastRepaint;
  static const _kMinRepaintInterval = Duration(milliseconds: 180);

  // Instant sheet has no controller; no fields required
  // 7B.2: Instant sheet control key + debounce
  final GlobalKey<MapBottomSheetState> _sheetKey =
      GlobalKey<MapBottomSheetState>();
  Timer? _sheetDebounce;
  String? _sheetLastAction; // 'expand' | 'collapse'
  
  // Hide/show sheet visibility
  bool _isSheetVisible = false;

  // 7E: Auto-camera fit debounce timer
  Timer? _debouncedCameraFit;

  // Refresh state
  bool _isRefreshing = false;

  // MIGRATION NOTE: Removed _posSub - VehicleDataRepository manages subscriptions

  // LIFECYCLE: App lifecycle state tracking
  bool _isPaused = false;

  // REBUILD CONTROL: Camera position tracking with threshold-based rebuilds
  final ValueNotifier<LatLng?> _cameraCenterNotifier = ValueNotifier<LatLng?>(null);
  static const _kCameraMovementThreshold = 0.001; // ~111 meters at equator
  
  // PERFORMANCE: Rebuild tracking
  int _rebuildCount = 0;
  int _skippedRebuildCount = 0;
  final Stopwatch _rebuildStopwatch = Stopwatch();
  DateTime? _lastRebuildTime;

  // TRIPS INTEGRATION: Track trips refresh state
  final bool _isTripsRefreshing = false;
  DateTime? _tripsLastRefreshTime;

  // CONNECTIVITY: Track WebSocket connection state
  bool _showConnectivityBanner = false;
  WebSocketStatus? _lastWsStatus;

  // TASK 7: Performance diagnostics timer
  Timer? _perfDiagnosticsTimer;
  int _wsReconnectCount = 0;
  DateTime? _lastPerfLog;

  @override
  void initState() {
    super.initState();

    // No sheet controller to initialize for InstantInfoSheet

    // LIVE MOTION FIX: Initialize motion controller with smooth interpolation
    // - 200ms tick rate for fluid animation (5 FPS)
    // - 1200ms interpolation window matches typical WebSocket update intervals
    // - Cubic easing for natural deceleration
    // - Dead-reckoning extrapolation for moving vehicles (speed ≥ 3 km/h)
    _motionController = MarkerMotionController(
      
    );

    // LIVE MOTION FIX: Listen to motion controller's global tick
    // Triggers marker layer rebuild during active animations (any device moving)
    // This ensures smooth visual updates without widget rebuilds
    _motionController.globalTick.addListener(_onMotionTick);

    // OPTIMIZATION: Initialize throttled marker notifier
    // Raised throttle to 80ms to reduce UI thread load
    _markersNotifier = ThrottledValueNotifier<List<MapMarkerData>>(
      const [],
      // Increase throttle to reduce micro-flicker on rapid WS bursts
      throttleDuration: const Duration(seconds: 1),
    );

    // OPTIMIZATION: Only rebuild when focus changes if search bar visibility depends on it
    _focusNode.addListener(_handleFocusChange);

    // OPTIMIZATION: Initialize FleetMapPrefetch manager
    if (MapDebugFlags.enablePrefetch) {
      _initializePrefetchManager();
    }

    // MIGRATION: Initialize VehicleDataRepository for cache-first startup
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;

      // OPTIMIZATION: Preload bitmap descriptors for instant marker icons
      // This eliminates the "loading" spinner delay on first marker render
      // Now uses Flutter Material Icons instead of PNG assets
      unawaited(
        BitmapDescriptorCache.instance
            .preloadAll(null) // Uses default StandardMarkerIcons.configs
            .catchError((Object e) {
          _log.warning('Bitmap cache preload error (non-fatal)', error: e);
        }),
      );

      // OPTIMIZATION: Preload marker icons for reduced first-draw latency
      unawaited(
        MarkerIconManager.instance.preloadIcons().catchError((Object e) {
          _log.warning('Icon preload error (non-fatal)', error: e);
        }),
      );

      // OPTIMIZATION: Initialize background marker processing isolate
      await MarkerProcessingIsolate.instance.initialize();

      // OPTIMIZATION: Lightweight performance monitoring (debug mode only)
      if (kDebugMode && MapDebugFlags.enablePerfMetrics) {
        MapPerformanceMonitor.startProfiling();
      }

      // TASK 7: Start lightweight performance diagnostics (debug mode only)
      if (kDebugMode) {
        _startPerformanceDiagnostics();
      }

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
        _log.debug('Initialized repository with ${deviceIds.length} devices');
      }

      // Register marker count supplier for performance overlay (disabled by default)
      if (MapDebugFlags.enablePerfMetrics) {
  final perfSvc = ref.read(performanceMetricsServiceProvider);
  perfSvc.markerCountSupplier = () => _markersNotifier.value.length;
        perfSvc.start();
      }

      // OPTIMIZATION: Setup marker update listeners (outside build method)
      // This ensures marker processing happens in response to data changes,
      // not during widget rebuilds
      _setupMarkerUpdateListeners();
    });

    // OPTIMIZATION: Parallel FMTC warmup (saves ~30-50ms startup)
    // Both warmup tasks are I/O-bound, so parallelization is safe
    unawaited(
      Future.wait([
        FMTCInitializer.warmup(),
        FMTCInitializer.warmupStoresForSources(MapTileProviders.all),
      ]).then((_) {
        _log.debug('[FMTC] ✅ Parallel warmup finished (core + per-source stores)');
      }).catchError((Object e, StackTrace? st) {
        _log.warning('[FMTC] Warmup error', error: e);
      }),
    );

    // Initialize FMTC debug overlay with current tile source and network status
    if (kDebugMode) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final currentSource = ref.read(mapTileSourceProvider);
        MapDebugInfo.instance.updateTileSource(currentSource.name);
        
        final networkState = ref.read(networkStateProvider);
        MapDebugInfo.instance.updateNetworkStatus(
          networkState == NetworkState.online ? 'Online' : 'Offline',
        );
      });
    }

    // MIGRATION NOTE: Removed old positionsLiveProvider listening
    // VehicleDataRepository handles WebSocket → Cache → Notifiers internally

    if (widget.preselectedIds != null && widget.preselectedIds!.isNotEmpty) {
      _selectedIds.addAll(widget.preselectedIds!);
      _isSheetVisible = true; // Make sheet visible for preselected devices
      // Auto-expand on first frame when deep-link preselection provided
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scheduleSheetAnimation(expand: true);
      });
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
                // OPTIMIZATION: Retry triggers actual position fetch instead of empty setState
                onPressed: () => _ensureSelectedDevicePositions(_selectedIds),
              ),
            ),
          );
        }
      });
    }
  }

  /// OPTIMIZATION: Handle focus changes only when necessary
  void _handleFocusChange() {
    if (!mounted) return;
    // Only rebuild if the focus state affects visible UI
    // (e.g., search bar border color, keyboard visibility)
    setState(() {
      // State will be read from _focusNode.hasFocus in build method
    });
  }

  /// OPTIMIZATION: Setup marker update listeners outside of build method
  ///
  /// This is critical for performance - marker processing should happen
  /// in response to data changes (via ref.listenManual), NOT during widget builds.
  ///
  /// Benefits:
  /// - Build method stays pure and fast
  /// - Marker updates only when data actually changes
  /// - No redundant processing on unrelated rebuilds
  void _setupMarkerUpdateListeners() {
    _log.debug('_setupMarkerUpdateListeners called');
    
    // Track which devices we've set up listeners for
    final listenedDeviceIds = <int>{};
    
    // Helper to setup position listeners for a device
    void setupPositionListener(int deviceId) {
      if (listenedDeviceIds.contains(deviceId)) {
        _log.debug('Skipping duplicate listener for device $deviceId');
        return;
      }
      listenedDeviceIds.add(deviceId);
      
      _log.debug('Setting up position listener for device $deviceId');
      
      // 🎯 PRIORITY 1: Listen to optimized per-device stream
      // Benefits: 99% fewer broadcasts, only this device notifies on change
      final removeListener = ref.listenManual(
        devicePositionStreamProvider(deviceId),
        (previous, next) {
          if (!mounted) return;
          _log.debug('Position listener fired for device $deviceId: '
              'previous=${previous?.valueOrNull != null}, '
              'next=${next.valueOrNull != null}');
          final pos = next.valueOrNull;
          if (pos != null) {
            _lastPositions[deviceId] = pos;
          }
          // When any position updates, refresh all markers
          final currentDevices = ref.read(devicesNotifierProvider);
          currentDevices.whenData(_scheduleMarkerUpdate);
        },
      );
      _listenerCleanups.add(removeListener);
    }
    
    // Listen to device list changes using listenManual
    final removeDevicesListener = ref.listenManual(
      devicesNotifierProvider,
      (previous, next) {
        next.whenData((devices) {
          if (!mounted) return;
          
          // Setup position listeners for any new devices
          for (final device in devices) {
            final deviceId = device['id'] as int?;
            if (deviceId != null) {
              setupPositionListener(deviceId);
            }
          }
          
          _scheduleMarkerUpdate(devices);
        });
      },
    );
    _listenerCleanups.add(removeDevicesListener);

    // Listen to last-known positions updates (REST/DAO seeded) using listenManual
    // This ensures markers appear even when WebSocket is disconnected
    final removeLastKnownListener = ref.listenManual(
      positionsLastKnownProvider,
      (previous, next) {
        if (!mounted) return;
        final prevCount = previous?.valueOrNull?.length ?? 0;
        final nextCount = next.valueOrNull?.length ?? 0;
        _log.debug('positionsLastKnown changed: $prevCount -> $nextCount');
        final devices = ref.read(devicesNotifierProvider).asData?.value ?? const <Map<String, dynamic>>[];
        if (devices.isNotEmpty) {
          _scheduleMarkerUpdate(devices);
        }
      },
    );
    _listenerCleanups.add(removeLastKnownListener);

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
        
        _scheduleMarkerUpdate(devices);
      }
    });
  }

  // OPTIMIZATION: Marker update throttling timer
  Timer? _markerUpdateDebouncer;
  List<Map<String, dynamic>>? _pendingDevices;
  
  // OPTIMIZATION: Increased debounce from 300ms to 500ms
  // Target: ~20 rebuilds per 10 seconds (was ~33 with 300ms)
  // Calculation: 10000ms / 500ms = 20 updates
  static const _kMarkerUpdateDebounce = Duration(milliseconds: 500);
  
  /// PERF PHASE 2: Schedule a debounced marker update
  /// Collapses multiple rapid updates into a single rebuild frame (500ms window)
  void _scheduleMarkerUpdate(List<Map<String, dynamic>> devices) {
    if (kDebugMode) {
      debugPrint('[PERF] Scheduling marker update for ${devices.length} devices (500ms debounce)');
    }
    
    // Store pending devices for batching
    _pendingDevices = devices;
    
    // Cancel existing timer and create new one
    _markerUpdateDebouncer?.cancel();
    _markerUpdateDebouncer = Timer(_kMarkerUpdateDebounce, () {
      if (!mounted) {
        debugPrint('[MAP][PERF] Marker update cancelled (widget disposed)');
        return;
      }
      
      final devicesToProcess = _pendingDevices;
      if (devicesToProcess != null) {
        _triggerMarkerUpdate(devicesToProcess);
      }
      _pendingDevices = null;
    });
  }

  /// Trigger marker update with current state
  /// Called by debounced timer when data changes
  void _triggerMarkerUpdate(List<Map<String, dynamic>> devices) {
    if (kDebugMode) {
      debugPrint('[MAP] _triggerMarkerUpdate called for ${devices.length} devices');
    }
    
    // Safety check: prevent update after disposal
    if (!mounted) {
      debugPrint('[MAP][PERF] ⏸️ Marker update skipped (widget disposed)');
      return;
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

    final selInfo = _selectedIds.isEmpty ? 'none' : _selectedIds.join(',');
    _log.debug(
      '🎯 Marker Update Triggered: ${positions.length} positions '
      '(_lastPositions: ${_lastPositions.length}, '
      'lastKnown: ${lastKnown?.length ?? 0}), '
      '${devices.length} devices, selected: $selInfo',
    );

    // Process markers asynchronously
    _processMarkersAsync(
      positions,
      devices,
      _selectedIds,
      ref.read(mapSearchQueryProvider), // Read from provider
    );
  }

  // 7B.2: Debounced auto expand/collapse of the info sheet based on selection
  void _scheduleSheetAnimation({required bool expand}) {
    final action = expand ? 'expand' : 'collapse';
    // Prevent redundant animations on identical consecutive actions
    if (_sheetLastAction == action) return;
    _sheetDebounce?.cancel();
    _sheetLastAction = action;
    _sheetDebounce = Timer(const Duration(milliseconds: 80), () {
      if (!mounted) return;
      final sheet = _sheetKey.currentState;
      if (sheet == null) return;
      if (expand) {
        sheet.expand();
      } else {
        sheet.collapse();
      }
    });
  }

  void _scheduleSheetForSelection() {
    final shouldShow = _selectedIds.isNotEmpty;
    if (shouldShow != _isSheetVisible) {
      setState(() {
        _isSheetVisible = shouldShow;
      });
    }
  }

  // 7E: Auto-camera fit scheduler - debounced to prevent rapid camera jumps
  void _scheduleCameraFitForSelection() {
    if (_selectedIds.isEmpty) {
      // 🧭 No selection → fit to all markers (fleet view)
      _debouncedCameraFit?.cancel();
      _debouncedCameraFit = Timer(const Duration(milliseconds: 150), _fitToAllMarkers);
      return;
    }

    // 🗺 One or more selected → fit to their positions
    _debouncedCameraFit?.cancel();
    _debouncedCameraFit = Timer(const Duration(milliseconds: 150), _fitToSelectedMarkers);
  }

  // 7E: Fit camera to selected markers with smooth animation
  Future<void> _fitToSelectedMarkers() async {
    if (_selectedIds.isEmpty) return;
    
    // Gather positions for selected devices
    final selectedPositions = <LatLng>[];
    for (final deviceId in _selectedIds) {
      final position = ref.read(positionByDeviceProvider(deviceId));
      if (position != null && _valid(position.latitude, position.longitude)) {
        selectedPositions.add(LatLng(position.latitude, position.longitude));
      } else {
        // Fallback to device stored coordinates
        final device = ref.read(deviceByIdProvider(deviceId));
        if (device != null) {
          final lat = _asDouble(device['latitude']);
          final lon = _asDouble(device['longitude']);
          if (_valid(lat, lon)) {
            selectedPositions.add(LatLng(lat!, lon!));
          }
        }
      }
    }
    
    if (selectedPositions.isEmpty) return;

    _log.debug('Fitting to ${_selectedIds.length} selected markers');

    await _animatedMoveToBounds(
      selectedPositions,
      padding: 60,
    );
  }

  // 7E: Fit camera to all markers (fleet view)
  Future<void> _fitToAllMarkers() async {
    // Gather all valid positions
    final allPositions = <LatLng>[];
    for (final entry in _lastPositions.entries) {
      final pos = entry.value;
      if (_valid(pos.latitude, pos.longitude)) {
        allPositions.add(LatLng(pos.latitude, pos.longitude));
      }
    }
    
    if (allPositions.isEmpty) return;

    _log.debug('Fitting to all ${allPositions.length} markers (fleet view)');

    await _animatedMoveToBounds(
      allPositions,
      padding: 40,
    );
  }

  // 7E: Animated camera move to fit bounds with smooth spring-like curve
  Future<void> _animatedMoveToBounds(
    List<LatLng> points, {
    double padding = 50,
  }) async {
    if (points.isEmpty || _mapKey.currentState == null) return;

    // Calculate bounds manually
    var minLat = points.first.latitude;
    var maxLat = points.first.latitude;
    var minLng = points.first.longitude;
    var maxLng = points.first.longitude;

    for (final pos in points) {
      if (pos.latitude < minLat) minLat = pos.latitude;
      if (pos.latitude > maxLat) maxLat = pos.latitude;
      if (pos.longitude < minLng) minLng = pos.longitude;
      if (pos.longitude > maxLng) maxLng = pos.longitude;
    }

    // Calculate center
    final centerLat = (minLat + maxLat) / 2;
    final centerLng = (minLng + maxLng) / 2;
    final center = LatLng(centerLat, centerLng);

    // Calculate appropriate zoom level based on bounds size
    final latDiff = maxLat - minLat;
    final lngDiff = maxLng - minLng;
    final maxDiff = latDiff > lngDiff ? latDiff : lngDiff;

    // Rough zoom calculation (adjust as needed)
    double targetZoom;
    if (maxDiff < 0.01) {
      targetZoom = 16.0;
    } else if (maxDiff < 0.05) {
      targetZoom = 14.0;
    } else if (maxDiff < 0.1) {
      targetZoom = 12.0;
    } else if (maxDiff < 0.5) {
      targetZoom = 10.0;
    } else if (maxDiff < 1.0) {
      targetZoom = 8.0;
    } else {
      targetZoom = 6.0;
    }

    // Clamp zoom to safe range
    targetZoom = targetZoom.clamp(0.0, 18.0);

    // Use the existing safe move method
    _mapKey.currentState!.safeZoomTo(center, targetZoom);

    _log.debug(
      'Moved to center: (${center.latitude.toStringAsFixed(4)}, '
      '${center.longitude.toStringAsFixed(4)}) @ zoom ${targetZoom.toStringAsFixed(1)}',
    );
  }

  /// Open the selected device location in native maps app
  /// Uses geo: URI for native app launch with web URL fallback
  Future<void> _openInMaps() async {
    if (_selectedIds.length != 1) return;

    final deviceId = _selectedIds.first;
    
    // Try to get position from provider (live or last-known)
    final position = ref.read(positionByDeviceProvider(deviceId));
    
    double? lat;
    double? lon;
    
    if (position != null && _valid(position.latitude, position.longitude)) {
      lat = position.latitude;
      lon = position.longitude;
    } else {
      // Fallback: get coordinates from device stored data
      final device = ref.read(deviceByIdProvider(deviceId));
      if (device != null) {
        lat = _asDouble(device['latitude']);
        lon = _asDouble(device['longitude']);
      }
    }
    
    if (lat == null || lon == null || !_valid(lat, lon)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No valid coordinates available for this device'),
            duration: Duration(seconds: 2),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
      return;
    }
    
    // Try geo: URI first for native map app, fallback to web URL
    final geoUri = Uri.parse('geo:${lat.toStringAsFixed(6)},${lon.toStringAsFixed(6)}');
    final webUri = Uri.parse('https://www.google.com/maps/search/?api=1&query=$lat,$lon');
    
    try {
      if (await canLaunchUrl(geoUri)) {
        await launchUrl(geoUri, mode: LaunchMode.externalApplication);
        _log.debug('✅ Opened native Maps app (geo:)');
      } else {
        await launchUrl(webUri, mode: LaunchMode.externalApplication);
        _log.debug('🌐 Opened Google Maps web');
      }
    } catch (e) {
      _log.error('Failed to launch map', error: e);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to open maps: $e'),
            duration: const Duration(seconds: 3),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    
    _log.debug('[LIFECYCLE] App state changed: $state');

    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.inactive:
        _onAppPaused();
      case AppLifecycleState.resumed:
        _onAppResumed();
      case AppLifecycleState.detached:
      case AppLifecycleState.hidden:
        // No action needed
        break;
    }
  }

  /// LIFECYCLE: Handle app pause/inactive state
  /// - Pause live updates and cancel marker debouncer timers
  /// - Stop map animation controllers
  /// - TASK 3: Persist marker cache to disk
  void _onAppPaused() {
    if (_isPaused) return;
    _isPaused = true;

    _log.debug('[LIFECYCLE] Pausing: canceling timers');

    // Cancel marker update debouncer
    _markerUpdateDebouncer?.cancel();
    _pendingDevices = null;

    // Cancel camera fit debouncer
    _debouncedCameraFit?.cancel();

    // Cancel sheet animation debouncer
    _sheetDebounce?.cancel();
    
    // TASK 3: Persist marker cache to disk before app pauses
    // Enables 60-70% cache reuse rate after resume (vs 0% without persistence)
    EnhancedMarkerCache.instance.persistToDisk();
    
    // Note: MarkerMotionController continues running (internal timer-based)
    // This is acceptable as it's lightweight and prevents jarring when resuming
    
    _log.debug('[LIFECYCLE] ⏸️ Paused (debounce timers canceled, cache persisted)');
  }

  /// LIFECYCLE: Handle app resume state
  /// - Resume live WebSocket position updates
  /// - Refresh stale data via repository
  /// - TASK 3: Restore marker cache from disk
  void _onAppResumed() {
    if (!_isPaused) return;
    _isPaused = false;

    _log.debug('[LIFECYCLE] Resuming: restarting live updates');

    // TASK 3: Restore marker cache from disk after resume
    // Provides 60-70% cache hit rate on first rebuild (vs 0% without persistence)
    EnhancedMarkerCache.instance.restoreFromDisk();

    // Trigger fresh marker update with current data
    final devicesAsync = ref.read(devicesNotifierProvider);
    final devices = devicesAsync.asData?.value ?? [];
    if (devices.isNotEmpty) {
      _scheduleMarkerUpdate(devices);
    }

    // Request repository refresh for fresh data
    final repo = ref.read(vehicleDataRepositoryProvider);
    repo.refreshAll();

    _log.debug('[LIFECYCLE] ▶️ Resumed (cache restored, marker updates scheduled, data refresh requested)');
  }

  /// TASK 7: Start lightweight performance diagnostics
  /// Logs aggregated stats every 30 seconds in debug mode only
  void _startPerformanceDiagnostics() {
    _perfDiagnosticsTimer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => _logPerformanceMetrics(),
    );
    
    _log.debug('[PERF] Performance diagnostics started (30s interval)');
  }

  /// TASK 7: Log aggregated performance metrics
  /// Provides dev-time visibility for faster regression detection
  void _logPerformanceMetrics() {
    if (!kDebugMode) return; // Safety check
    if (!mounted) return; // Don't log if disposed
    
    final now = DateTime.now();
    
    // Throttle logs to once per 30 seconds minimum
    if (_lastPerfLog != null && 
        now.difference(_lastPerfLog!).inSeconds < 30) {
      return;
    }
    _lastPerfLog = now;
    
    // Get marker cache stats from EnhancedMarkerCache
    final cacheStats = EnhancedMarkerCache.instance.getStats();
    final cachedMarkers = cacheStats['cached_markers'] as int? ?? 0;
    final snapshots = cacheStats['snapshots'] as int? ?? 0;
    final markerReuseRate = snapshots > 0 
        ? (cachedMarkers / snapshots * 100).clamp(0, 100).toStringAsFixed(1)
        : '0.0';
    
    // Device cache stats (optional - skip if provider not available)
    const deviceHitRate = '0.0%'; // Simplified for now
    
    // Calculate WS reconnect rate (per 30s interval)
    final wsReconnects = _wsReconnectCount;
    _wsReconnectCount = 0; // Reset for next interval
    
    // Get current marker count
    final markerCount = _markersNotifier.value.length;
    
    // Get rebuild stats
    final totalRebuilds = _rebuildCount + _skippedRebuildCount;
    final skipRate = totalRebuilds > 0
        ? (_skippedRebuildCount / totalRebuilds * 100).toStringAsFixed(1)
        : '0.0';
    
    // Log aggregated metrics in a single line
    debugPrint(
      '[PerfMetrics] '
      'markerReuse=$markerReuseRate% '
      'ws=$wsReconnects/30s '
      'deviceCache=$deviceHitRate '
      'markers=$markerCount '
      'rebuilds=$_rebuildCount '
      'skipped=$skipRate%',
    );
  }

  @override
  void dispose() {
    // TASK 7: Cancel performance diagnostics timer
    _perfDiagnosticsTimer?.cancel();
    
    // Clean up manual listeners first
    for (final subscription in _listenerCleanups) {
      subscription.close();
    }
    _listenerCleanups.clear();

    // LIVE MOTION FIX: Clean up motion controller resources
    _motionController.globalTick.removeListener(_onMotionTick);
    _motionController.dispose();

    // OPTIMIZATION: Cancel marker update debouncer to prevent updates after disposal
    _markerUpdateDebouncer?.cancel();
    _markerUpdateDebouncer = null;
    _pendingDevices = null;
    
    // LIFECYCLE: Cleanup camera center notifier
    _cameraCenterNotifier.dispose();
    
    // MIGRATION NOTE: Removed _posSub.close() and _positionsDebounceTimer - repository manages lifecycle
    _preselectSnackTimer?.cancel();
  _debouncedCameraFit?.cancel(); // 7E: Cancel camera fit debounce timer
    _searchDebouncer.cancel();
    _searchCtrl.dispose();
    _focusNode.dispose();
  // No sheet controller to dispose for InstantInfoSheet
    _markersNotifier
        .dispose(); // OPTIMIZATION: Clean up throttled marker notifier
    
    // PERFORMANCE: Print final rebuild statistics
    if (kDebugMode && MapDebugFlags.enablePerfMetrics) {
      final totalRebuilds = _rebuildCount + _skippedRebuildCount;
      final skipRate = totalRebuilds > 0 
          ? (_skippedRebuildCount / totalRebuilds * 100).toStringAsFixed(1)
          : '0.0';
      debugPrint(
        '[MAP][PERF] Final stats: $_rebuildCount rebuilds, '
        '$_skippedRebuildCount skipped ($skipRate% skip rate)',
      );
    }

    // OPTIMIZATION: Cleanup prefetch manager
    if (MapDebugFlags.enablePrefetch) {
      _prefetchManager?.dispose();
      _captureSnapshotBeforeDispose();
    }

    // OPTIMIZATION: Stop performance monitoring and print summary
    if (kDebugMode && MapDebugFlags.enablePerfMetrics) {
      MapPerformanceMonitor.stopProfiling();
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
      if (kDebugMode) {
        debugPrint('[MapPage] Prefetch init error: $e');
      }
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
      if (kDebugMode) {
        debugPrint('[MapPage] Prefetch error: $e');
      }
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
      if (kDebugMode) {
        debugPrint('[MapPage] Snapshot capture error: $e');
      }
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

  /// PERF PHASE 2: Throttled setState to limit map repaints
  /// Caps map re-paints to ~6 fps during heavy bursts, smoothing GPU load
  /// 
  /// Note: Available for use in setState() calls that trigger frequent repaints.
  /// Currently marker updates use ThrottledValueNotifier instead.
  // ignore: unused_element
  void _throttledRepaint(VoidCallback fn) {
    final now = DateTime.now();
    
    // Skip repaint if too soon after last one
    if (_lastRepaint != null &&
        now.difference(_lastRepaint!) < _kMinRepaintInterval) {
      if (kDebugMode) {
        debugPrint(
          '[PERF] Map repaint skipped (too soon: ${now.difference(_lastRepaint!).inMilliseconds}ms)',
        );
      }
      return;
    }
    
    _lastRepaint = now;
    if (mounted) {
      setState(fn);
    }
  }

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

      // LIVE MOTION FIX: Merge motion-controlled positions with static fallbacks
      // Priority: motion controller's interpolated positions > WebSocket positions > device coords
      final motionPositions = <int, Position>{};
      
      for (final deviceId in devices.map((d) => d['id'] as int?).whereType<int>()) {
        // First, try motion controller's live interpolated position
        final motionLatLng = _motionController.currentValue(deviceId);
        
        if (motionLatLng != null) {
          // Use motion controller's animated position
          final basePos = positions[deviceId] ?? _lastPositions[deviceId];
          if (basePos != null) {
            // Create position with interpolated coordinates but original metadata
            motionPositions[deviceId] = Position(
              id: basePos.id,
              deviceId: basePos.deviceId,
              latitude: motionLatLng.latitude,  // ← ANIMATED coordinate
              longitude: motionLatLng.longitude, // ← ANIMATED coordinate
              speed: basePos.speed,
              course: basePos.course,
              serverTime: basePos.serverTime,
              deviceTime: basePos.deviceTime,
              attributes: basePos.attributes,
            );
            
            if (kDebugMode && positions[deviceId] != null) {
              final delta = ((motionLatLng.latitude - positions[deviceId]!.latitude).abs() +
                             (motionLatLng.longitude - positions[deviceId]!.longitude).abs()) * 111000; // rough meters
              if (delta > 1) {
                debugPrint(
                  '[LIVE_MOTION] Device $deviceId: using interpolated position '
                  '(${motionLatLng.latitude.toStringAsFixed(6)}, ${motionLatLng.longitude.toStringAsFixed(6)}) '
                  'delta=${delta.toStringAsFixed(1)}m from WebSocket',
                );
              }
            }
          }
        } else {
          // Fallback: use WebSocket position or cached position
          final pos = positions[deviceId] ?? _lastPositions[deviceId];
          if (pos != null) {
            motionPositions[deviceId] = pos;
          }
        }
      }

      // Use motion-controlled positions for marker generation
      final effectivePositions = motionPositions.isNotEmpty ? motionPositions : positions;

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
          (effectivePositions.isNotEmpty || hasAnyDeviceStoredCoords());

      // OPTIMIZATION: Use enhanced marker cache with intelligent diffing
      final diffResult = _enhancedMarkerCache.getMarkersWithDiff(
        effectivePositions,  // ← Pass motion-controlled positions
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
      
      // Update cache statistics
      _cacheMisses += diffResult.created + diffResult.modified;
      _cacheHits += diffResult.reused;

      // Update notifier. For the first non-empty render, bypass throttle to ensure
      // immediate visibility of markers.
    if (diffResult.created > 0 ||
      diffResult.removed > 0 ||
      diffResult.modified > 0 ||
      _markersNotifier.value.length != diffResult.markers.length) {
        if (kDebugMode) {
          final hitRate = _cacheHitRate * 100;
          debugPrint('[MapPage] 📊 $diffResult');
          debugPrint(
            '[MapPage] ⚡ Processing: ${stopwatch.elapsedMilliseconds}ms',
          );
          debugPrint(
            '[MAP][PERF] Marker rebuild took ${stopwatch.elapsedMilliseconds}ms '
            '(reuse rate: ${diffResult.efficiency * 100}%, '
            'total cache hit rate: ${hitRate.toStringAsFixed(1)}%)',
          );
        }
        final isFirstNonEmpty = _markersNotifier.value.isEmpty &&
            diffResult.markers.isNotEmpty;
        if (isFirstNonEmpty || diffResult.modified > 0) {
          _markersNotifier.forceUpdate(diffResult.markers);
          if (kDebugMode) {
            debugPrint(
              '[MapPage] ✅ Markers successfully placed: '
              '${diffResult.markers.length} markers from '
              '${effectivePositions.length} positions '
              '(devices: ${devices.length})',
            );
          }
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
      _selectedIds.clear();
      _selectedIds.add(n);
    });

    // Ensure we have a position for this tapped/selected device
    // Fire-and-forget to enrich markers without blocking UI
    unawaited(_ensureSelectedDevicePositions({n}));

    // 7E: Auto-fit camera to selected marker
    _scheduleCameraFitForSelection();

    // OPTIMIZATION: Trigger marker update with new selection state
    final devicesAsync = ref.read(devicesNotifierProvider);
    devicesAsync.whenData(_scheduleMarkerUpdate);

    if (kDebugMode) {
      debugPrint('[MARKER_TAP] Selected deviceId=$n');
    }

    // New: if multiple devices are near the tapped one (within ~40m),
    // show a spiderfy overlay for quick disambiguation.
    _maybeShowSpiderfyForNearby(n);

    // 7B.2: Auto-expand/collapse based on selection
    _scheduleSheetForSelection();
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
    // Track if any state changes require a rebuild
    var needsRebuild = false;
    
    if (_selectedIds.isNotEmpty) {
      // OPTIMIZATION: Clear selection inside setState to batch state changes
      setState(_selectedIds.clear);
      needsRebuild = true;

      // 7E: Auto-fit camera to all markers when selection cleared
      _scheduleCameraFitForSelection();

      // OPTIMIZATION: Trigger marker update when selection cleared
      final devicesAsync = ref.read(devicesNotifierProvider);
      devicesAsync.whenData(_scheduleMarkerUpdate);
    }
    
    if (!_editing && _showSuggestions) {
      setState(() {
        _showSuggestions = false;
      });
      needsRebuild = true;
    }
    
    if (needsRebuild) {
      // 7B.2: Collapse when selection cleared
      _scheduleSheetForSelection();
    }
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
          MapDebugInfo.instance.updateTileSource(selectedSource.name);
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
        _scheduleMarkerUpdate(devices);
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[MapPage] _ensureSelectedDevicePositions error: $e');
      }
    }
  }

  /// OPTIMIZATION: Focus on selected devices by triggering camera fit
  /// Instead of empty setState, directly call the camera fit method
  void _focusSelected() {
    _scheduleCameraFitForSelection();
  }

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

  /// TRIPS: Build data freshness indicator banner
  Widget _buildTripsRefreshBanner() {
    final now = DateTime.now();
    final age = _tripsLastRefreshTime != null
        ? now.difference(_tripsLastRefreshTime!)
        : Duration.zero;

    final ageText = age.inMinutes < 1
        ? 'just now'
        : age.inMinutes == 1
            ? '1 min ago'
            : '${age.inMinutes} mins ago';

    return Positioned(
      top: 60,
      right: 16,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.6),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_isTripsRefreshing)
              const SizedBox(
                width: 12,
                height: 12,
                child: CircularProgressIndicator(
                  strokeWidth: 1.5,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              )
            else
              const Icon(
                Icons.check_circle,
                color: Colors.greenAccent,
                size: 14,
              ),
            const SizedBox(width: 6),
            Text(
              _isTripsRefreshing ? 'Refreshing...' : 'Updated $ageText',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Monitor WebSocket connectivity and trigger banner display
  void _monitorConnectivity() {
    final wsState = ref.watch(webSocketManagerProvider);
    
    // Update connectivity banner visibility
    final shouldShow = wsState.status == WebSocketStatus.disconnected ||
        wsState.status == WebSocketStatus.retrying;
    
    if (shouldShow != _showConnectivityBanner) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          setState(() => _showConnectivityBanner = shouldShow);
        }
      });
    }

    // Log status changes
    if (_lastWsStatus != wsState.status) {
      if (kDebugMode) {
        debugPrint('[MAP][WS] Status changed: $_lastWsStatus → ${wsState.status}');
      }
      _lastWsStatus = wsState.status;

      // TASK 7: Track reconnect count for diagnostics
      if (wsState.status == WebSocketStatus.retrying ||
          wsState.status == WebSocketStatus.disconnected) {
        _wsReconnectCount++;
      }

      // Auto-resume marker updates when connection restored
      if (wsState.status == WebSocketStatus.connected && !_isPaused) {
        if (kDebugMode) {
          debugPrint('[MAP][WS] Connection restored, triggering marker refresh');
        }
        final devicesAsync = ref.read(devicesNotifierProvider);
        final devices = devicesAsync.asData?.value ?? [];
        if (devices.isNotEmpty) {
          _scheduleMarkerUpdate(devices);
        }
      }
    }
  }

  /// REBUILD CONTROL: Determine if map rebuild should proceed
  /// 
  /// Only rebuilds when:
  /// - Camera center moved beyond threshold (> 50m or 0.001° lat/lon)
  /// - Device selection changed
  /// - Search query changed
  /// - Refresh is in progress
  /// - App lifecycle resumed
  /// 
  /// Returns true to proceed with rebuild, false to skip
  bool _shouldTriggerRebuild(BuildContext context, WidgetRef ref) {
    // Always rebuild if paused (lifecycle resume triggers rebuild)
    if (_isPaused) {
      if (kDebugMode && MapDebugFlags.enablePerfMetrics) {
        debugPrint('[MAP][PERF] Rebuild triggered (app lifecycle resumed)');
      }
      return true;
    }
    
    // Always rebuild if refreshing
    if (_isRefreshing) {
      if (kDebugMode && MapDebugFlags.enablePerfMetrics) {
        debugPrint('[MAP][PERF] Rebuild triggered (manual refresh)');
      }
      return true;
    }
    
    // Check if camera moved significantly
    final mapState = _mapKey.currentState;
    if (mapState != null) {
      final currentCenter = mapState.mapController.camera.center;
      final previousCenter = _cameraCenterNotifier.value;
      
      if (previousCenter != null) {
        final latDiff = (currentCenter.latitude - previousCenter.latitude).abs();
        final lonDiff = (currentCenter.longitude - previousCenter.longitude).abs();
        
        if (latDiff > _kCameraMovementThreshold || lonDiff > _kCameraMovementThreshold) {
          _cameraCenterNotifier.value = currentCenter;
          if (kDebugMode && MapDebugFlags.enablePerfMetrics) {
            final distanceMeters = ((latDiff + lonDiff) * 111000).toStringAsFixed(0);
            debugPrint(
              '[MAP][PERF] Rebuild triggered (camera moved ~${distanceMeters}m)',
            );
          }
          return true;
        }
      } else {
        // First time - record position
        _cameraCenterNotifier.value = currentCenter;
        return true;
      }
    }
    
    // If we get here, no significant changes detected
    return false;
  }

  // 7F: Build device overlay info card
  // ---------- Build ----------
  @override
  @override
  Widget build(BuildContext context) {
    // TASK 6: Call super.build for AutomaticKeepAliveClientMixin
    super.build(context);
    
    // PERFORMANCE: Track rebuild timing
    _rebuildStopwatch.reset();
    _rebuildStopwatch.start();
    final now = DateTime.now();
    
    // CONNECTIVITY: Monitor WebSocket status and update banner
    _monitorConnectivity();
    
    // CRITICAL FIX: Setup position update listeners in build method
    // ref.listen() must be called in build method, not in initState
    _setupPositionListenersInBuild();
    
    // REBUILD CONTROL: Check if rebuild is necessary based on data changes
    final shouldRebuild = _shouldTriggerRebuild(context, ref);
    
    if (!shouldRebuild) {
      _skippedRebuildCount++;
      _rebuildStopwatch.stop();
      
      if (kDebugMode && MapDebugFlags.enablePerfMetrics) {
        final timeSinceLastRebuild = _lastRebuildTime != null
            ? now.difference(_lastRebuildTime!).inMilliseconds
            : 0;
        debugPrint(
          '[MAP][PERF] Skipped rebuild (no data change, '
          '${timeSinceLastRebuild}ms since last rebuild)',
        );
      }
      
      // Return previous content without rebuilding
      return _buildMapContent();
    }
    
    // Proceeding with rebuild
    _rebuildCount++;
    _lastRebuildTime = now;
    
    var content = _buildMapContent();
    
    _rebuildStopwatch.stop();
    
    // Log rebuild performance
    if (kDebugMode && MapDebugFlags.enablePerfMetrics) {
      final duration = _rebuildStopwatch.elapsedMilliseconds;
      final totalRebuilds = _rebuildCount + _skippedRebuildCount;
      final skipRate = totalRebuilds > 0 
          ? (_skippedRebuildCount / totalRebuilds * 100).toStringAsFixed(1)
          : '0.0';
      debugPrint(
        '[MAP][PERF] Map rebuild triggered (reason: data change) '
        'took ${duration}ms (rebuild #$_rebuildCount, skip rate: $skipRate%)',
      );
    }

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

      // 🎯 PRIORITY 1: LIVE MOTION FIX using optimized stream
      // Benefits: Direct repository stream, 99% fewer broadcasts
      ref.listen(devicePositionStreamProvider(deviceId), (previous, next) {
        if (!mounted) return;
        
        final pos = next.valueOrNull;
        if (pos != null) {
          // Cache position for fallback
          _lastPositions[deviceId] = pos;
          
          // CRITICAL: Feed new position to motion controller for smooth interpolation
          // - Motion controller will interpolate from current → target over 1200ms
          // - Extrapolation kicks in for moving vehicles (speed ≥ 3 km/h)
          // - globalTick will notify when animation is active
          _motionController.updatePosition(
            deviceId: deviceId,
            target: LatLng(pos.latitude, pos.longitude),
            timestamp: pos.serverTime,
            speedKmh: pos.speed,
            courseDeg: pos.course,
          );

          if (kDebugMode) {
            debugPrint(
              '[LIVE_MOTION] Device $deviceId: fed position to motion controller '
              '(${pos.latitude.toStringAsFixed(6)}, ${pos.longitude.toStringAsFixed(6)}) '
              'speed=${pos.speed.toStringAsFixed(1)} km/h',
            );
          }
        }
        
        // Also trigger marker update for immediate response (first frame)
        // Motion controller will handle subsequent animation frames via globalTick
        final currentDevices = ref.read(devicesNotifierProvider).asData?.value ?? [];
        _scheduleMarkerUpdate(currentDevices);
      });
      _positionListenerIds.add(deviceId);
      newlyAdded++;
    }
    if (kDebugMode && newlyAdded > 0) {
      debugPrint('[MAP] Registered $newlyAdded new position listeners (total: ${_positionListenerIds.length})');
    }
  }

  // LIVE MOTION FIX: Motion tick callback - rebuilds markers during animation
  // Called by motion controller's globalTick ValueNotifier when any device is animating
  // This provides smooth visual updates (5 FPS) without triggering full widget rebuilds
  void _onMotionTick() {
    if (!mounted) return;

    // Trigger marker layer rebuild with interpolated positions
    // Motion controller provides currentPositions map with animated coordinates
    final devicesAsync = ref.read(devicesNotifierProvider);
    final devices = devicesAsync.asData?.value ?? [];
    
    if (kDebugMode) {
      final animatingCount = _motionController.currentPositions.length;
      debugPrint('[LIVE_MOTION] Motion tick: $animatingCount devices animating');
    }
    
    _scheduleMarkerUpdate(devices);
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

    // OPTIMIZATION: Watch devices list - positions are watched separately below
    // This reduces rebuild triggers when only device metadata changes
    final devicesAsync = ref.watch(devicesNotifierProvider);

    // MIGRATION: Repository-backed position watching (replaces positionsLiveProvider + positionsLastKnownProvider)
    // Build positions map from per-device snapshots (cache-first, WebSocket updates)
    final devices = devicesAsync.asData?.value ?? [];
    final positions = <int, Position>{};
    for (final device in devices) {
      final deviceId = device['id'] as int?;
      if (deviceId == null) continue;

      // 🎯 PRIORITY 1: Watch optimized per-device stream with select()
      // Benefits: Only rebuilds when THIS device's position changes
      final position = ref.watch(
        devicePositionStreamProvider(deviceId).select((async) => async.valueOrNull),
      );
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
            final query = ref.watch(mapSearchQueryProvider); // Watch provider
            final q = query.trim().toLowerCase();

            // If exactly one device is selected, center to its position IMMEDIATELY
            if (_selectedIds.length == 1) {
              final sid = _selectedIds.first;

              // OPTIMIZATION: Watch only the position, not the entire provider
              // This prevents rebuild when provider metadata changes
              final merged = ref.watch(
                positionByDeviceProvider(sid).select((p) => p),
              );
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
                    if (query.isEmpty || 'all devices'.contains(q))
                      {'__all__': true, 'name': 'All devices'},
                    ...devices.where((d) {
                      final n = d['name']?.toString().toLowerCase() ?? '';
                      return query.isEmpty || n.contains(q);
                    }),
                  ]
                : const <Map<String, dynamic>>[];

            return GestureDetector(
              behavior: HitTestBehavior.deferToChild,
              onLongPress: MapDebugFlags.toggleOverlay,
              child: Stack(
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
                  // FMTC Diagnostics Overlay (debug-only, tap-to-toggle)
                  ValueListenableBuilder<bool>(
                    valueListenable: MapDebugFlags.showFmtcOverlay,
                    builder: (context, showOverlay, child) {
                      if (!MapDebugFlags.isOverlayEnabled) {
                        return const SizedBox.shrink();
                      }
                      return const Align(
                        alignment: Alignment.bottomLeft,
                        child: MapDebugOverlay(),
                      );
                    },
                  ),
                  // Notification banner: shows on Map page (bottom)
                  const NotificationBanner(),
                  // CONNECTIVITY: WebSocket connection status banner
                  if (_showConnectivityBanner)
                    Positioned(
                      top: 60,
                      left: 16,
                      right: 16,
                      child: MapConnectivityBanner(
                        visible: _showConnectivityBanner,
                        onDismiss: () {
                          setState(() => _showConnectivityBanner = false);
                        },
                      ),
                    ),
                  // TRIPS: Data freshness indicator banner
                  if (_tripsLastRefreshTime != null)
                    _buildTripsRefreshBanner(),
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
                    child: MapRebuildBadge(label: 'MapPage'),
                  ),
                // Search + suggestions
                Positioned(
                  top: 12,
                  left: 16,
                  right: 88,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      MapSearchBar(
                        controller: _searchCtrl,
                        focusNode: _focusNode,
                        editing: _editing,
                        suggestionsVisible: _showSuggestions,
                        onChanged: (v) => _searchDebouncer.run(
                          () {
                            // OPTIMIZATION: Update provider instead of local state
                            ref.read(mapSearchQueryProvider.notifier).state = v;
                            // Trigger marker update with new query
                            final devicesAsync =
                                ref.read(devicesNotifierProvider);
                            devicesAsync.whenData(_scheduleMarkerUpdate);
                          },
                        ),
                        onClear: () {
                          _searchCtrl.clear();
                          _searchDebouncer.run(() {
                            // OPTIMIZATION: Clear provider instead of local state
                            ref.read(mapSearchQueryProvider.notifier).state = '';
                            // Trigger marker update when query cleared
                            final devicesAsync =
                                ref.read(devicesNotifierProvider);
                            devicesAsync.whenData(_scheduleMarkerUpdate);
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
                                                devicesAsync.whenData(_scheduleMarkerUpdate);
                                                // Ensure we have positions for selected devices (fire-and-forget)
                                                if (!allSelected && _selectedIds.isNotEmpty) {
                                                  unawaited(_ensureSelectedDevicePositions(_selectedIds));
                                                }
                                                // 7B.2: Auto expand/collapse based on selection
                                                _scheduleSheetForSelection();
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
                                                    devicesAsync.whenData(_scheduleMarkerUpdate);
                                                    // 7B.2: Auto expand/collapse based on selection
                                                    _scheduleSheetForSelection();
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
                      MapActionButton(
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
                      MapActionButton(
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
                          // OPTIMIZATION: Watch only the current source name, not entire provider
                          final activeLayer = ref.watch(
                            mapTileSourceProvider.select((source) => source),
                          );
                          return MapActionButton(
                            icon: Icons.layers,
                            tooltip: 'Map layer: ${activeLayer.name}',
                            onTap: () {
                              _showLayerMenu(context, activeLayer);
                            },
                          );
                        },
                      ),
                      // Open in Maps button (only shown when single device selected)
                      if (_selectedIds.length == 1) ...[
                        const SizedBox(height: 8),
                        MapActionButton(
                          icon: Icons.open_in_new,
                          tooltip: 'Open in Maps',
                          onTap: _openInMaps,
                        ),
                      ],
                    ],
                  ),
                ),
                // Offline network banner (appears at top when network is offline)
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: MapOfflineBanner(
                    // OPTIMIZATION: Watch only connectivity state, not full provider
                    networkState: ref.watch(
                      networkStateProvider.select((state) => state),
                    ),
                    connectionStatus: ref.watch(
                      connectionStatusProvider.select((status) => status),
                    ),
                  ),
                ),
                // Bottom info panel - fade/slide in when device selected, completely hidden when none selected
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 250),
                  switchInCurve: Curves.easeOutCubic,
                  switchOutCurve: Curves.easeInCubic,
                  transitionBuilder: (child, animation) {
                    final slide = Tween<Offset>(
                      begin: const Offset(0, 0.1),
                      end: Offset.zero,
                    ).animate(CurvedAnimation(
                      parent: animation,
                      curve: Curves.easeOutCubic,
                    ),);
                    return FadeTransition(
                      opacity: animation,
                      child: SlideTransition(
                        position: slide,
                        child: child,
                      ),
                    );
                  },
                  child: _isSheetVisible
                      ? MapBottomSheet(
                          key: _sheetKey,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 8,
                            ),
                            child: AnimatedSwitcher(
                              duration: const Duration(milliseconds: 220),
                              switchInCurve: Curves.easeInOut,
                              switchOutCurve: Curves.easeInOut,
                              transitionBuilder: (child, animation) {
                                final slide = Tween<Offset>(
                                  begin: const Offset(0, 0.02),
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
                              child: _selectedIds.isEmpty
                                  ? const SizedBox.shrink()
                                  : (_selectedIds.length == 1
                                      ? MapDeviceInfoBox(
                                          key: const ValueKey('single-info'),
                                          deviceId: _selectedIds.first,
                                          devices: devices,
                                          // OPTIMIZATION: Watch only position value
                                          position: ref.watch(
                                            positionByDeviceProvider(
                                              _selectedIds.first,
                                            ).select((p) => p),
                                          ),
                                          statusResolver: _deviceStatus,
                                          statusColorBuilder: _statusColor,
                                          onClose: () {
                                            setState(_selectedIds.clear);
                                            _scheduleSheetForSelection();
                                          },
                                          onFocus: _focusSelected,
                                        )
                                      : MapMultiSelectionInfoBox(
                                          key: const ValueKey('multi-info'),
                                          selectedIds: _selectedIds,
                                          devices: devices,
                                          positions: positions,
                                          statusResolver: _deviceStatus,
                                          statusColorBuilder: _statusColor,
                                          onClear: () {
                                            setState(_selectedIds.clear);
                                            _scheduleSheetForSelection();
                                          },
                                          onFocus: _focusSelected,
                                        )),
                            ),
                          ),
                        )
                      : const SizedBox.shrink(key: ValueKey('no-sheet')),
                ),
              ],
            ),
            ); // Close GestureDetector
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
    // OPTIMIZATION: Watch the entire FMTC state (already optimized controller)
    final fmState = ref.watch(
      fleetMapTelemetryControllerProvider.select((state) => state),
    );

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

          // 🎯 PRIORITY 1: Watch optimized per-device stream with select()
          final position = ref.watch(
            devicePositionStreamProvider(deviceId).select((async) => async.valueOrNull),
          );
          if (position != null) {
            positions[deviceId] = position;
          }
        }

        // Process markers asynchronously
        _processMarkersAsync(
          positions,
          devices,
          _selectedIds,
          ref.read(mapSearchQueryProvider), // Read provider
        );

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
                // TODO(owner): Add full UI overlay (search bar, bottom panel, etc.)
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

// EOF


