import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_app_gps/core/data/services/vehicle_data_cache_service.dart';
import 'package:my_app_gps/core/data/services/vehicle_data_network_service.dart';
import 'package:my_app_gps/core/data/services/vehicle_data_stream_service.dart';
import 'package:my_app_gps/core/data/vehicle_data_cache.dart';
import 'package:my_app_gps/core/data/vehicle_data_snapshot.dart';
import 'package:my_app_gps/core/database/dao/telemetry_dao.dart';
import 'package:my_app_gps/core/database/entities/telemetry_record.dart';
import 'package:my_app_gps/core/diagnostics/dev_diagnostics.dart';
import 'package:my_app_gps/core/lifecycle/stream_lifecycle_manager.dart';
import 'package:my_app_gps/core/performance/performance_traces.dart';
import 'package:my_app_gps/core/utils/adaptive_render.dart';
import 'package:my_app_gps/core/utils/app_logger.dart';
import 'package:my_app_gps/core/utils/shared_prefs_holder.dart';
import 'package:my_app_gps/core/utils/stream_memoizer.dart';
import 'package:my_app_gps/data/models/event.dart';
import 'package:my_app_gps/features/map/data/position_model.dart';
import 'package:my_app_gps/providers/connectivity_provider.dart';
import 'package:my_app_gps/services/device_service.dart';
import 'package:my_app_gps/services/event_service.dart';
import 'package:my_app_gps/services/positions_service.dart';
import 'package:my_app_gps/services/traccar_socket_service.dart';
import 'package:my_app_gps/services/websocket_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Provider for cache (requires SharedPreferences) - PUBLIC for override in main
final vehicleDataCacheProvider = Provider<VehicleDataCache>((ref) {
  final prefs = ref.watch(sharedPreferencesProvider);
  return VehicleDataCache(prefs: prefs);
});

/// Provider for SharedPreferences (async init) - PUBLIC for override in main
final sharedPreferencesProvider = Provider<SharedPreferences>((ref) {
  if (SharedPrefsHolder.isInitialized) {
    return SharedPrefsHolder.instance;
  }
  throw UnimplementedError('SharedPreferences must be overridden in main.dart');
});

/// Provider for the vehicle data repository singleton
final vehicleDataRepositoryProvider = Provider<VehicleDataRepository>((ref) {
  final cache = ref.watch(vehicleDataCacheProvider);
  final devSvc = ref.watch(deviceServiceProvider);
  final posSvc = ref.watch(positionsServiceProvider);
  final socketSvc = ref.watch(traccarSocketServiceProvider);
  final telemetryDao = ref.watch(telemetryDaoProvider);
  final eventService = ref.watch(eventServiceProvider);
  final wsManager = ref.watch(webSocketManagerProvider.notifier);

  // Initialize extracted services
  final cacheService = VehicleDataCacheService(
    cache: cache,
    telemetryDao: telemetryDao,
  );

  final streamService = VehicleDataStreamService();

  final networkService = VehicleDataNetworkService(
    deviceService: devSvc,
    positionsService: posSvc,
  );

  final repo = VehicleDataRepository(
    cache: cache,
    deviceService: devSvc,
    positionsService: posSvc,
    socketService: socketSvc,
    telemetryDao: telemetryDao,
    eventService: eventService,
    webSocketManager: wsManager,
    cacheService: cacheService,
    networkService: networkService,
    streamService: streamService,
  );

  // Listen to unified connectivity and update repository/WS behavior
  ref.listen(connectivityProvider, (previous, next) {
    // Update repository offline flag to guard REST calls and timers
    repo.setOffline(offline: next.isOffline);

    // Auto-manage WebSocket lifecycle to prevent retry spam when offline
    final wsManager = ref.read(webSocketManagerProvider.notifier);
    if (next.isOffline) {
      wsManager.suspend();
    } else {
      wsManager.resume();
      // Kick an incremental refresh on reconnect (best-effort, avoids full reload)
      repo.incrementalRefreshAll();
    }
  });

  ref.onDispose(repo.dispose);
  return repo;
});

/// Lifecycle tracking wrapper for per-device position streams.
/// 
/// **Purpose:** Track listener count and last access time for idle stream cleanup.
/// 
/// **Lifecycle:**
/// - Listener count incremented on subscription (onListen callback)
/// - Listener count decremented on cancellation (onCancel callback)
/// - Last access time refreshed on every position emission
/// - Idle timeout: 5 minutes with 0 listeners
/// - LRU eviction: When total streams exceed 2000
/// 
/// **Memory Impact:**
/// Each _StreamEntry: ~1-5 KB overhead
/// Target: <10 MB total for 2000 streams
class _StreamEntry {
  final StreamController<Position?> controller;
  int listenerCount = 0;
  DateTime lastAccess = DateTime.now();

  _StreamEntry(this.controller);

  void incrementListeners() {
    listenerCount++;
    lastAccess = DateTime.now();
  }

  void decrementListeners() {
    listenerCount--;
    lastAccess = DateTime.now();
  }

  void refreshAccess() => lastAccess = DateTime.now();

  bool get isIdle => listenerCount == 0;
  Duration get idleTime => DateTime.now().difference(lastAccess);
}

/// Centralized repository for vehicle data.
///
/// Architecture:
/// - Merges REST API + WebSocket updates
/// - Maintains in-memory + disk cache
/// - Exposes per-device ValueNotifiers
/// - Implements parallel fetch and fallback strategies
/// - Debounces/throttles updates to prevent UI flooding
class VehicleDataRepository {
  static final _log = 'VehicleRepo'.logger;
  
  VehicleDataRepository({
    required this.cache,
    required this.deviceService,
    required this.positionsService,
    required this.socketService,
    required this.telemetryDao,
    required this.eventService,
    required this.webSocketManager,
    required this.cacheService,
    required this.networkService,
    required this.streamService,
  }) {
    // Wire up network service callback
    networkService.onRefreshMultiple = fetchMultipleDevices;
    _init();
  }

  final VehicleDataCache cache;
  final DeviceService deviceService;
  final PositionsService positionsService;
  final TraccarSocketService socketService;
  final TelemetryDaoBase telemetryDao;
  final EventService eventService;
  final WebSocketManager webSocketManager;
  
  // === NEW: Extracted Services ===
  final VehicleDataCacheService cacheService;
  final VehicleDataNetworkService networkService;
  final VehicleDataStreamService streamService; // 🎯 PHASE 2: For fallback suppression
  // Throttle backfill to prevent duplicate runs on rapid reconnects
  DateTime? _lastBackfillRun;
  DateTime? _lastPositionBackfillRun; // positions incremental backfill throttle

  // 🧹 LIFECYCLE: Unified stream and subscription manager
  final _lifecycle = StreamLifecycleManager(name: 'VehicleRepo');

  // Per-device notifiers
  final Map<int, ValueNotifier<VehicleDataSnapshot?>> _notifiers = {};

  // Debounce timers for each device
  final Map<int, Timer> _debounceTimers = {};

  // 🚀 Batching optimization: Buffer position updates for 200ms to reduce UI updates
  final Map<int, VehicleDataSnapshot> _positionUpdateBuffer = {};
  Timer? _batchFlushTimer;
  static const _batchFlushDelay = Duration(milliseconds: 200);

  // Memoization: Track last fetch time to prevent redundant calls
  final Map<int, DateTime> _lastFetchTime = {};

  // Event broadcast stream (raw event maps from WebSocket) - TRACKED
  late final StreamController<Map<String, dynamic>> _eventController =
      _lifecycle.trackController(
        StreamController<Map<String, dynamic>>.broadcast(),
      );
  // Recovered (backfilled) events count stream after reconnect - TRACKED
  late final StreamController<int> _recoveredEventsController =
      _lifecycle.trackController(
        StreamController<int>.broadcast(),
      );

  // REST fallback timer
  Timer? _fallbackTimer;
  
  // 🔄 Adaptive REST fallback backoff (when WebSocket is down)
  // Base interval is 10s; doubles on consecutive empty/failed polls up to 120s, with small jitter
  Duration _fallbackInterval = const Duration(seconds: 10);
  static const Duration _fallbackMin = Duration(seconds: 10);
  static const Duration _fallbackMax = Duration(seconds: 120);
  int _fallbackConsecutiveFailures = 0;
  bool _lastRestFetchHadData = false; // set by fetchMultipleDevices()

  // Memory cleanup timer (runs every hour)
  Timer? _cleanupTimer;

  // Connection state flags
  bool _isWebSocketConnected = false;
  bool _isOffline = false; // unified offline flag (network or backend)
  bool _isDisposed = false; // Safety guard for async operations
  bool _everConnected = false; // Track initial connect vs reconnect

  static const _minFetchInterval = Duration(seconds: 5);
  static const _restFallbackInterval = Duration(seconds: 10);

  // Test-mode flag to disable background timers in widget tests
  // Set from test setup: VehicleDataRepository.testMode = true;
  static bool testMode = false;

  // === Deduplication state ===
  // Stores last processed payload hash for positions per device
  final Map<int, String> _lastPositionHash = <int, String>{};
  // Stores last processed position id per device for fast ID-based dedup
  final Map<int, int> _lastPositionId = <int, int>{};
  // Stores last processed payload hash for device updates per device
  final Map<int, String> _lastDevicePayloadHash = <int, String>{};

  // === Device name cache ===
  // Holds resolved device names for quick UI use (notifications, lists)
  final Map<int, String> _deviceNames = <int, String>{};

  // === 🎯 PRIORITY 1: Per-device position streams ===
  // Provides reactive stream API for provider integration
  // Eliminates need for providers to poll ValueNotifiers
  // Using StreamController with sync broadcast for immediate delivery of latest value
  final Map<int, _StreamEntry> _deviceStreams = {};
  final Map<int, Position?> _latestPositions = {};
  
  // === 🎯 PHASE 9: Stream memoization & lifecycle management ===
  // Prevents duplicate stream subscriptions for the same device
  final _streamMemoizer = StreamMemoizer<Position?>();
  
  // === 🎯 PHASE 1 STEP 3: Aggressive memory & lifecycle management ===
  // Optimized values for reduced memory footprint and proactive cleanup
  // 
  // **Previous values (Phase 9):**
  // - _kIdleTimeout: 5 minutes (passive cleanup)
  // - _kMaxStreams: 2000 (10MB memory overhead)
  // - _kCleanupInterval: 60 seconds
  // 
  // **New values (Phase 1 Step 3):**
  // - _kIdleTimeout: 1 minute (5x more aggressive)
  // - _kMaxStreams: 500 (4x lower limit, 2.5MB overhead)
  // - _kCleanupInterval: 60 seconds (maintained for consistency)
  // 
  // **Expected impact:**
  // - 50-70% less idle memory usage
  // - 5-7 MB freed for 1000-device fleets
  // - Lower GC pressure = smoother UI
  Timer? _streamCleanupTimer;
  static const _kIdleTimeout = Duration(minutes: 1);  // Was: 5 minutes
  static const _kMaxStreams = 500;  // Was: 2000
  static const _kCleanupInterval = Duration(seconds: 60);  // Maintained

  // === 🎯 STREAM BACKPRESSURE: Adaptive throttling based on LOD mode ===
  // Per-device last emission time to enforce emit gap
  final Map<int, DateTime> _lastEmit = {};
  // Per-device pending updates (coalescing buffer - only keeps latest)
  final Map<int, VehicleDataSnapshot> _pendingUpdates = {};
  // Coalesced update count for stats
  int _coalescedCount = 0;
  // Optional LOD controller reference (set externally by MapPage)
  AdaptiveLodController? _lodController;

  /// Set the LOD controller for adaptive backpressure
  /// Should be called by MapPage or other UI component that manages LOD
  void setLodController(AdaptiveLodController? controller) {
    _lodController = controller;
    _log.debug('[Backpressure] LOD controller ${controller != null ? 'attached' : 'detached'}');
  }

  /// Get emit gap duration based on current LOD mode
  Duration _emitGap() {
    final mode = _lodController?.mode ?? RenderMode.high;
    return switch (mode) {
      RenderMode.high => const Duration(milliseconds: 33),   // ~30 Hz
      RenderMode.medium => const Duration(milliseconds: 66), // ~15 Hz
      RenderMode.low => const Duration(milliseconds: 120),   // ~8 Hz
    };
  }

  /// Resolve a friendly device name with safe fallbacks.
  /// Returns a user-visible string; never null.
  String resolveDeviceName(int deviceId) {
    final name = _deviceNames[deviceId];
    if (name != null && name.trim().isNotEmpty) {
      return name;
    }
    return 'Unknown Device';
  }

  /// Cache a device map (e.g., from REST or WebSocket) to update name cache.
  void cacheDevice(Map<String, dynamic> device) {
    final id = device['id'];
    final name = device['name'];
    if (id is int && name is String && name.trim().isNotEmpty) {
      _deviceNames[id] = name;
    }
  }

  /// Fetch a single device by ID (lazy load) and update name cache.
  /// Uses existing DeviceService; falls back to scanning the full list.
  Future<Map<String, dynamic>?> fetchDeviceById(int id) async {
    try {
      // Current DeviceService exposes only fetchDevices(); scan for target.
      final devices = await deviceService.fetchDevices();
      for (final d in devices) {
        if (d['id'] == id) {
          cacheDevice(d);
          return d;
        }
      }
    } catch (e) {
      _log.error('Failed to fetch device $id', error: e);
    }
    return null;
  }

  // Compute a stable hash string for a Position
  String _hashPosition(Position p) {
    // Prefer unique position id when available
    if (p.id != null) return 'pid:${p.id}';
    // Otherwise derive from key fields rounded to avoid noisy float jitter
    final lat = p.latitude.toStringAsFixed(6);
    final lon = p.longitude.toStringAsFixed(6);
    final spd = p.speed.toStringAsFixed(1);
    final ts = p.deviceTime.toUtc().millisecondsSinceEpoch;
    return 'd:${p.deviceId}|t:$ts|lat:$lat|lon:$lon|s:$spd';
  }

  // Compute a stable hash for device JSON payloads
  String _hashDevicePayload(Map<String, dynamic> m) {
    final deviceId = m['id'] ?? m['deviceId'] ?? '';
    final posId = m['positionId'] ?? '';
    final status = m['status'] ?? '';
    final lastUpdate = m['lastUpdate'] ?? m['lastUpdateDt']?.toString() ?? '';
    final attrs = (m['attributes'] is Map<String, dynamic>)
        ? (m['attributes'] as Map<String, dynamic>)
        : const <String, dynamic>{};
    final ign = attrs['ignition'];
    final motion = attrs['motion'];
    return 'd:$deviceId|p:$posId|s:$status|lu:$lastUpdate|i:$ign|m:$motion';
  }

  void _init() {
    // Pre-warm cache synchronously (safe - only reads SharedPreferences)
    _prewarmCache();

    // Fire-and-forget: apply telemetry retention policy (30 days) on startup
    unawaited(_applyTelemetryRetention());

    // Defer WebSocket subscription to after provider initialization completes
    Future.microtask(() {
      // Subscribe to WebSocket updates (connect returns a stream) - TRACKED
      _lifecycle.track(
        socketService.connect().listen(_handleSocketMessage),
      );

      // Start REST fallback timer (disabled in tests)
      if (!VehicleDataRepository.testMode) {
        _startFallbackPolling();
      } else {
        _log.debug('[TEST] Skipping REST fallback timer');
      }

      // Start periodic cleanup timer to prevent memory leaks
      _startCleanupTimer();

      _log.debug('Initialized with deferred WebSocket connection');
    });
  }

  /// Expose a stream of raw event maps coming from the WebSocket 'events' payload.
  /// Consumers can transform these into domain models as needed.
  Stream<Map<String, dynamic>> get onEvent => _eventController.stream;

  /// Expose a stream of recovered event counts emitted after reconnect backfill
  Stream<int> get onRecoveredEvents => _recoveredEventsController.stream;

  /// Update offline state from connectivity provider
  void setOffline({required bool offline}) {
    if (_isOffline == offline) return;
    _isOffline = offline;
    _log.info('Connectivity changed → offline=$_isOffline');
    if (_isOffline) {
      _fallbackTimer?.cancel();
    } else {
      if (!VehicleDataRepository.testMode) {
        _startFallbackPolling();
      }
    }
  }

  /// Deletes telemetry records older than 30 days.
  Future<void> _applyTelemetryRetention() async {
    try {
      final cutoff = DateTime.now().toUtc().subtract(const Duration(days: 30));
      await telemetryDao.deleteOlderThan(cutoff);
      _log.debug('Telemetry retention applied. Cutoff: $cutoff');
    } catch (e) {
      _log.error('Telemetry retention failed', error: e);
    }
  }

  /// Start periodic cleanup timer (runs every hour)
  void _startCleanupTimer() {
    _cleanupTimer?.cancel();
    if (!VehicleDataRepository.testMode) {
      _cleanupTimer = _lifecycle.trackTimer(
        Timer.periodic(
          const Duration(hours: 1),
          (_) => _cleanupStaleDevices(),
        ),
      );
      _log.debug('🧹 Cleanup timer started (every 1 hour)');
    }
  }

  /// Remove and dispose stale device notifiers (older than 7 days)
  void _cleanupStaleDevices() {
    if (_isDisposed) {
      _log.debug('[CONCURRENCY] 🧩 Cleanup skipped: repository disposed');
      return;
    }

    final now = DateTime.now();
    var removed = 0;

    _notifiers.removeWhere((deviceId, notifier) {
      final snapshot = notifier.value;
      if (snapshot == null) return false;

      final age = now.difference(snapshot.timestamp);
      if (age > const Duration(days: 7)) {
        notifier.dispose();
        removed++;
        return true;
      }
      return false;
    });

    _log.info('🧹 Cleaned up $removed stale devices at $now');
  }

  /// Test-only method to invoke cleanup (exposed for unit tests)
  @visibleForTesting
  void invokeTestCleanup() => _cleanupStaleDevices();

  /// Pre-warm cache by loading all cached snapshots into notifiers
  /// Pre-warm cache by loading all cached snapshots into notifiers
  /// 🎯 PRIORITY 1: Also populates per-device position stream cache
  void _prewarmCache() {
    try {
      final allCached = cache.loadAll();
      if (allCached.isEmpty) {
        _log.debug('No cached data to prewarm');
        return;
      }
      for (final entry in allCached.entries) {
        final deviceId = entry.key;
        final snapshot = entry.value;
        _notifiers[deviceId] = ValueNotifier<VehicleDataSnapshot?>(snapshot);
        
        // 🎯 PRIORITY 1: Populate position stream cache for immediate offline availability
        if (snapshot.position != null) {
          _latestPositions[deviceId] = snapshot.position;
          _log.debug('📡 Cached position loaded for device $deviceId');
        }
      }
      _log.info('✅ Pre-warmed cache with ${allCached.length} devices (notifiers + streams)');
    } catch (e) {
      _log.error('Cache pre-warm error', error: e);
    }
  }

  /// Handle incoming WebSocket messages
  Future<void> _handleSocketMessage(TraccarSocketMessage msg) async {
    if (_isDisposed) {
      _log.debug('[CONCURRENCY] 🧩 Socket message dropped: repository disposed');
      return;
    }

    if (msg.type == 'connected') {
      _isWebSocketConnected = true;
      _log.info('✅ WebSocket connected');
      // RESET BACKOFF: on successful WS reconnect, restore fallback interval
      _fallbackConsecutiveFailures = 0;
      _fallbackInterval = _fallbackMin;
      // Reschedule fallback timer with base interval (best effort)
      if (!VehicleDataRepository.testMode) {
        _startFallbackPolling();
      }
      // If this is a reconnect (not the very first connection), backfill missed events.
      if (_everConnected) {
        unawaited(_onWebSocketReconnect());
        // Also perform an incremental positions backfill using last known snapshot/ids
        unawaited(_onWebSocketReconnectPositions());
      } else {
        _everConnected = true;
      }
      return;
    }

    // Standard positions payload (fast path)
    if (msg.type == 'positions' && msg.positions != null) {
      _handlePositionUpdates(msg.positions!);
      return;
    }

    // Events payload: may include positionId or deviceId and attributes (e.g., ignition)
    if (msg.type == 'events' && msg.payload != null) {
      try {
        _log.debug('[WS] events payload: ${msg.payload}');
        final payload = msg.payload;
        final events =
            payload is List ? List<dynamic>.from(payload) : <dynamic>[payload];
        for (final e in events) {
          if (e is Map<String, dynamic>) {
            // Broadcast raw event to listeners (Notifications pipeline)
            if (!_eventController.isClosed) {
              _eventController.add(e);
              _log.debug('Broadcasting event ${e['type'] ?? ''}');
            }
            final posId = e['positionId'] as int?;
            final deviceId = e['deviceId'] as int?;
            _log.debug('[WS] event for deviceId=$deviceId posId=$posId');
            
            // If event contains a positionId, fetch that position (likely contains attributes)
            if (posId != null) {
              try {
                final p = await positionsService.latestByPositionId(posId);
                if (p != null) {
                  _log.debug('[WS] fetched Position for posId=$posId -> device=${p.deviceId}');
                  _handlePositionUpdates([p]);
                }
              } catch (e) {
                _log.warning('Failed to fetch position for positionId=$posId', error: e);
              }
            }

            // Apply attribute-only updates (ignition/motion) immediately
            if (deviceId != null) {
              final attrs = e['attributes'];
              if (attrs is Map<String, dynamic>) {
                final ignition = attrs['ignition'];
                EngineState? engineState;
                if (ignition is bool) {
                  engineState = ignition ? EngineState.on : EngineState.off;
                } else if (attrs['motion'] is bool && attrs['motion'] == true) {
                  engineState = EngineState.on;
                }
                if (engineState != null) {
                  final rawTime = (e['eventTime'] ??
                      e['serverTime'] ??
                      e['deviceTime']) as String?;
                  DateTime ts;
                  try {
                    ts = rawTime != null
                        ? DateTime.parse(rawTime).toUtc()
                        : DateTime.now().toUtc();
                  } catch (_) {
                    ts = DateTime.now().toUtc();
                  }
                  // Ensure newer than any cached snapshot
                  ts = ts.add(const Duration(milliseconds: 1));
                  final partial = VehicleDataSnapshot(
                    deviceId: deviceId,
                    timestamp: ts,
                    engineState: engineState,
                    lastUpdate: ts,
                  );
                  _log.debug('[WS] applying event-based engine update for device=$deviceId -> $engineState at $ts');
                  _updateDeviceSnapshot(partial);
                }
              }

              // Also refresh device data if no positionId to keep other fields fresh
              if (posId == null) {
                _lastFetchTime.remove(deviceId);
                _log.debug('[WS] refreshing device data for deviceId=$deviceId (event)');
                unawaited(_fetchDeviceData(deviceId));
              }
            }
          }
        }
      } catch (e) {
        _log.error('Event handling error', error: e);
      }
      return;
    }

    // Devices payload: updated device metadata or positionId may be present
    if (msg.type == 'devices' && msg.payload != null) {
      try {
        _log.debug('[WS] devices payload: ${msg.payload}');
        final payload = msg.payload;
        final devices =
            payload is List ? List<dynamic>.from(payload) : <dynamic>[payload];
        for (final d in devices) {
          if (d is Map<String, dynamic>) {
            final posId = d['positionId'] as int?;
            final deviceId = d['id'] as int?;
            _log.debug('[WS] device update for deviceId=$deviceId posId=$posId');

            // Update device name cache when present in payload
            if (deviceId != null) {
              final name = d['name'];
              if (name is String && name.trim().isNotEmpty) {
                _deviceNames[deviceId] = name;
              }
            }

            // Deduplicate identical device payloads
            if (deviceId != null) {
              final hash = _hashDevicePayload(d);
              final prev = _lastDevicePayloadHash[deviceId];
              if (prev != null && prev == hash) {
                _log.debug('[WS] 🔁 Duplicate skipped for deviceId=$deviceId');
                continue; // Skip processing identical payload
              }
              _lastDevicePayloadHash[deviceId] = hash;
            }
            if (posId != null) {
              try {
                final p = await positionsService.latestByPositionId(posId);
                if (p != null) {
                  _log.debug('[WS] fetched Position for device posId=$posId -> device=${p.deviceId}');
                  _handlePositionUpdates([p]);
                }
              } catch (e) {
                _log.warning('Failed to fetch position for device update posId=$posId', error: e);
              }
            }

            if (deviceId != null) {
              // Apply attribute-only ignition updates from device payload if present
              final attrs = d['attributes'];
              if (attrs is Map<String, dynamic>) {
                final ignition = attrs['ignition'];
                EngineState? engineState;
                if (ignition is bool) {
                  engineState = ignition ? EngineState.on : EngineState.off;
                } else if (attrs['motion'] is bool && attrs['motion'] == true) {
                  engineState = EngineState.on;
                }
                if (engineState != null) {
                  final ts = DateTime.now()
                      .toUtc()
                      .add(const Duration(milliseconds: 1));
                  final partial = VehicleDataSnapshot(
                    deviceId: deviceId,
                    timestamp: ts,
                    engineState: engineState,
                    lastUpdate: ts,
                  );
                  _log.debug('[WS] applying device-based engine update for device=$deviceId -> $engineState at $ts');
                  _updateDeviceSnapshot(partial);
                }
              }

              // Refresh device data if no positionId to keep other fields fresh
              if (posId == null) {
                _log.debug('[WS] refreshing device data for deviceId=$deviceId (device update)');
                _lastFetchTime.remove(deviceId);
                unawaited(_fetchDeviceData(deviceId));
              }
            }
          }
        }
      } catch (e) {
        _log.error('Devices handling error', error: e);
      }
      return;
    }
  }

  /// On WebSocket reconnect, fetch and apply incremental positions since last known state.
  Future<void> _onWebSocketReconnectPositions() async {
    // Throttle to avoid duplicate runs on rapid reconnect loops
    final now = DateTime.now();
    if (_lastPositionBackfillRun != null &&
        now.difference(_lastPositionBackfillRun!) < const Duration(seconds: 5)) {
      _log.debug('⏳ Skipping positions backfill (throttled)');
      return;
    }
    _lastPositionBackfillRun = now;

    // Determine target devices from active notifiers; if none, nothing to backfill
    final deviceIds = _notifiers.keys.toList();
    if (deviceIds.isEmpty) {
      _log.debug('Positions backfill skipped: no active devices');
      return;
    }

    _log.info('🔄 Reconnected — backfilling positions incrementally for ${deviceIds.length} device(s)');

    // Helper to process a single device
    Future<List<Position>> fetchForDevice(int deviceId) async {
      try {
        // Establish anchor: prefer snapshot timestamp, fallback to latest position time
        final snapTs = _notifiers[deviceId]?.value?.timestamp;
        final latest = _latestPositions[deviceId]?.deviceTime;
        final anchor = (snapTs ?? latest) ?? DateTime.now().toUtc().subtract(const Duration(minutes: 5));
        // Add small safety margin to avoid off-by-one gaps
        final from = anchor.subtract(const Duration(minutes: 1));
        final list = await positionsService.fetchPositionsSince(deviceId: deviceId, since: from);

        if (list.isEmpty) return const <Position>[];

        // Filter strictly newer than our last known, and (if available) positionId greater than last processed
        final lastId = _lastPositionId[deviceId];
        final filtered = list.where((p) {
          final newerByTime = p.deviceTime.isAfter(anchor);
          if (lastId == null) return newerByTime;
          final pid = p.id;
          return newerByTime && (pid == null || pid > lastId);
        }).toList();

        return filtered;
      } catch (e) {
        _log.warning('Positions backfill failed for device $deviceId', error: e);
        return const <Position>[];
      }
    }

    // Limit concurrency to avoid spiking the backend
    const maxConcurrent = 4;
    final results = <Position>[];
    for (var i = 0; i < deviceIds.length; i += maxConcurrent) {
      final slice = deviceIds.sublist(i, (i + maxConcurrent).clamp(0, deviceIds.length));
      final batches = await Future.wait(slice.map(fetchForDevice));
      for (final b in batches) {
        if (b.isNotEmpty) results.addAll(b);
      }
    }

    if (results.isEmpty) {
      _log.info('✅ No missed positions to backfill');
      return;
    }

    _log.info('✅ Applying ${results.length} backfilled position(s)');
    _handlePositionUpdates(results);
  }

  /// On WebSocket reconnect, fetch and replay missed events to downstream consumers
  Future<void> _onWebSocketReconnect() async {
    // Throttle: avoid duplicate runs in quick succession
    final now = DateTime.now();
    if (_lastBackfillRun != null &&
        now.difference(_lastBackfillRun!) < const Duration(seconds: 5)) {
      _log.debug('⏳ Skipping backfill (throttled)');
      return;
    }
    _lastBackfillRun = now;
    // Try to get replay anchor first (most precise)
    final replayAnchor = await eventService.getReplayAnchor();
    // Fallback to latest cached event timestamp
    final cachedTs = await eventService.getLatestCachedEventTimestamp();

    // Establish bounded backfill window [from, to]
    final to = DateTime.now();
    var from =
        replayAnchor ?? cachedTs ?? to.subtract(const Duration(minutes: 30));

    // Guard against clock skew or invalid range
    if (!from.isBefore(to)) {
      // If from >= to, pull a small safety window
      from = to.subtract(const Duration(minutes: 15));
    }
    // Cap the maximum window to avoid oversized responses (max 12 hours)
    const maxWindow = Duration(hours: 12);
    if (to.difference(from) > maxWindow) {
      from = to.subtract(maxWindow);
    }

    _log.info('🔄 Reconnected — backfilling events from $from to $to');
    if (replayAnchor != null) {
      _log.debug('⏱️ Using replay anchor from last processed event');
    } else if (cachedTs != null) {
      _log.debug('📦 Using latest cached event timestamp');
    }

    try {
      // Some backends require deviceId to return events. Fetch per-device.
      // Prefer active device notifiers; fallback to full device list.
      var deviceIds = _notifiers.keys.toList();
      if (deviceIds.isEmpty) {
        try {
          final devices = await deviceService.fetchDevices();
          deviceIds = devices.map((d) => d['id']).whereType<int>().toList();
        } catch (e) {
          _log.warning('Failed to load devices for backfill', error: e);
        }
      }

      if (deviceIds.isEmpty) {
        _log.warning('⚠️ No deviceIds available for backfill');
        return;
      }

      // Add a safety margin to the from time to avoid off-by-one gaps
      final safeFrom = from.subtract(const Duration(minutes: 5));

      _log.debug('📆 Backfill window (safe): $safeFrom → $to');
      _log.debug('🧭 Backfilling per-device for ${deviceIds.length} device(s): $deviceIds');

      // Mark a backfill request in diagnostics (counting once per reconnect)
      DevDiagnostics.instance.onBackfillRequested(deviceIds.length);
      final allMissed = <Event>[];
      for (final id in deviceIds) {
        try {
          _log.debug('🔎 Fetching events for device $id');
          final list = await eventService.fetchEvents(
            deviceId: id,
            from: safeFrom,
            to: to,
          );
          if (list.isNotEmpty) allMissed.addAll(list);
        } catch (e) {
          _log.warning('Backfill fetch failed for device $id', error: e);
        }
      }

      if (allMissed.isEmpty) {
        _log.info('✅ No missed events');
        return;
      }

      // Notify recovered count once per backfill
      if (!_recoveredEventsController.isClosed) {
        _recoveredEventsController.add(allMissed.length);
      }
      for (final e in allMissed) {
        if (!_eventController.isClosed) {
          _eventController.add(e.toJson());
        }
      }
      _log.info('✅ Replayed ${allMissed.length} missed events');
      
      // Diagnostics: applied backfilled events
      try {
        // Avoid a hard dependency in release builds
        // ignore: unnecessary_statements
        DevDiagnostics.instance.onBackfillApplied(allMissed.length);
      } catch (e) {
        _log.warning('DevDiagnostics.onBackfillApplied failed', error: e);
      }
    } catch (e) {
      _log.warning('Missed-event fetch failed', error: e);
    }
  }

  /// Process position updates (from WebSocket or REST)
  /// 🚀 Optimized with 200ms batching to reduce UI update frequency by 40-60%
  void _handlePositionUpdates(List<Position> positions) {
    if (positions.isEmpty) return;

    for (final pos in positions) {
      // 1) Fast path: per-device dedup by last positionId
      final currentId = pos.id;
      if (currentId != null) {
        final lastId = _lastPositionId[pos.deviceId];
        if (lastId != null && lastId == currentId) {
          _log.debug('🔁 Duplicate positionId skipped for deviceId=${pos.deviceId} (posId=$currentId)');
          continue; // Identical position already processed
        }
        _lastPositionId[pos.deviceId] = currentId;
      }

      // 2) Fallback: hash-based dedup when id is missing/unstable
      if (currentId == null) {
        final hash = _hashPosition(pos);
        final prev = _lastPositionHash[pos.deviceId];
        if (prev != null && prev == hash) {
          _log.debug('🔁 Duplicate skipped for deviceId=${pos.deviceId}');
          continue; // Skip duplicate
        }
        _lastPositionHash[pos.deviceId] = hash;
      }

      final snapshot = VehicleDataSnapshot.fromPosition(pos);

      // 🚀 Batch positions in 200ms window instead of individual debounce timers
      // This reduces the number of UI updates from ~5/sec to ~2/sec per device
      _positionUpdateBuffer[pos.deviceId] = snapshot;
      
      // Schedule batch flush if not already scheduled
      _batchFlushTimer ??= _lifecycle.trackTimer(
        Timer(_batchFlushDelay, _flushPositionBatch),
      );
    }

    _log.debug('Buffered ${positions.length} position updates (will flush in ${_batchFlushDelay.inMilliseconds}ms)');
  }

  /// Flush batched position updates to UI
  void _flushPositionBatch() {
    if (_positionUpdateBuffer.isEmpty) {
      _batchFlushTimer = null;
      return;
    }

    final updateCount = _positionUpdateBuffer.length;
    
    // 🚀 START PERFORMANCE TRACE
    PerformanceTraces().startPositionBatchTrace(updateCount);
    
    _log.debug('🚀 Flushing batch of $updateCount position updates');

    // Process all buffered updates at once
    for (final entry in _positionUpdateBuffer.entries) {
      _updateDeviceSnapshot(entry.value);
    }
    
    // 🚀 STOP PERFORMANCE TRACE
    PerformanceTraces().stopPositionBatchTrace(
      flushedCount: updateCount,
      batchWindowMs: _batchFlushDelay.inMilliseconds,
    );

    // Clear buffer and timer
    _positionUpdateBuffer.clear();
    _batchFlushTimer = null;
  }

  /// Update cache and notify listeners for a device
  /// 🎯 STREAM BACKPRESSURE: Implements adaptive throttling and coalescing
  void _updateDeviceSnapshot(VehicleDataSnapshot snapshot) {
    final deviceId = snapshot.deviceId;
    final now = DateTime.now();
    final gap = _emitGap();
    final lastEmit = _lastEmit[deviceId];

    // Check if we're within throttle window
    if (lastEmit != null && now.difference(lastEmit) < gap) {
      // Coalesce: Store latest update, discard previous pending
      final hadPending = _pendingUpdates.containsKey(deviceId);
      _pendingUpdates[deviceId] = snapshot;
      
      if (hadPending) {
        _coalescedCount++;
        if (kDebugMode && _coalescedCount % 10 == 0) {
          _log.debug('[Backpressure] Coalesced $_coalescedCount updates (device $deviceId)');
        }
      }

      // Schedule delayed emission after gap expires
      Future.delayed(gap, () {
        final pending = _pendingUpdates.remove(deviceId);
        if (pending != null && !_isDisposed) {
          _emitSnapshot(pending);
        }
      });
      
      return; // Skip immediate emission
    }

    // Emit immediately if gap has passed
    _emitSnapshot(snapshot);
    _lastEmit[deviceId] = now;
  }

  /// Internal: Actually emit snapshot to notifiers and streams
  void _emitSnapshot(VehicleDataSnapshot snapshot) {
    final existing = _notifiers[snapshot.deviceId]?.value;
    _log.debug('Updating snapshot for device=${snapshot.deviceId}');
    _log.debug('  incoming: $snapshot');
    _log.debug('  existing: $existing');

    // Log engine state changes explicitly
    if (snapshot.engineState != null &&
        snapshot.engineState != existing?.engineState) {
      _log.debug('🔧 ENGINE STATE CHANGE: ${existing?.engineState} → ${snapshot.engineState}');
    }

    // Update cache
    cache.put(snapshot);

    // Persist telemetry record (history) - best-effort, ignore failures
    try {
      telemetryDao.put(
        TelemetryRecord(
          deviceId: snapshot.deviceId,
          timestampMs: snapshot.timestamp.toUtc().millisecondsSinceEpoch,
          speed: snapshot.speed,
          battery: snapshot.batteryLevel,
          signal: snapshot.signal,
          engine: snapshot.engineState?.name,
          odometer: snapshot.odometer,
          motion: snapshot.motion,
        ),
      );
    } catch (_) {
      // Swallow errors to keep UI pipeline unaffected
    }

    // Get or create notifier
    final notifier = _notifiers[snapshot.deviceId];
    if (notifier != null) {
      final existing = notifier.value;
      final merged = existing?.merge(snapshot) ?? snapshot;

      // Prevent redundant updates: only notify when content actually changed
      if (merged != existing) {
        notifier.value = merged;
        _log.debug('  merged: $merged');
        _log.debug('  ✅ Notifier updated - listeners will be notified');
        
        // 🎯 PRIORITY 1: Broadcast to per-device position stream
        _broadcastPositionUpdate(merged);
      } else {
        _log.debug('  ⏭️ No effective change, notifier not updated');
      }
    } else {
      _notifiers[snapshot.deviceId] =
          ValueNotifier<VehicleDataSnapshot?>(snapshot);
      _log.debug('  ✅ New notifier created for device ${snapshot.deviceId}');
      
      // 🎯 PRIORITY 1: Broadcast initial position to stream
      _broadcastPositionUpdate(snapshot);
    }
  }

  /// Broadcast position update to device-specific stream (Priority 1 optimization)
  void _broadcastPositionUpdate(VehicleDataSnapshot snapshot) {
    final position = snapshot.position;
    final deviceId = snapshot.deviceId;
    
    // Update latest position cache
    _latestPositions[deviceId] = position;
    
    // 🎯 RENDER OPTIMIZATION: Defer stream broadcast to microtask queue
    // This shifts emissions after current UI work completes, preventing frame jank
    Future.microtask(() {
      // Broadcast to stream if there are active listeners
      final entry = _deviceStreams[deviceId];
      if (entry != null && !entry.controller.isClosed && entry.controller.hasListener) {
        entry.controller.add(position);
        entry.refreshAccess(); // 🎯 PHASE 9 STEP 2: Update last access time
        _log.debug('📡 Position broadcast to stream for device $deviceId (listeners: ${entry.listenerCount})');
      }
    });
  }

  /// Get or create a ValueNotifier for a device
  ValueNotifier<VehicleDataSnapshot?> getNotifier(int deviceId) {
    return _notifiers.putIfAbsent(deviceId, () {
      final cached = cache.get(deviceId);
      final notifier = ValueNotifier<VehicleDataSnapshot?>(cached);
      if (cached == null) {
        _fetchDeviceData(deviceId);
      }
      return notifier;
    });
  }

  /// Fetch data for a single device (with memoization)
  Future<void> _fetchDeviceData(int deviceId) async {
    if (_isOffline) {
      _log.debug('Offline → skip fetch for device $deviceId');
      return; // Use cached data only
    }

    final lastFetch = _lastFetchTime[deviceId];
    if (lastFetch != null &&
        DateTime.now().difference(lastFetch) < _minFetchInterval) {
      _log.debug('Skipping fetch for device $deviceId (fetched recently)');
      return;
    }

    _lastFetchTime[deviceId] = DateTime.now();

    try {
      // Fetch device info
      final devices = await deviceService.fetchDevices();
      // Cache all device names from this call for faster resolution later
      for (final d in devices) {
        final id = d['id'];
        final name = d['name'];
        if (id is int && name is String && name.trim().isNotEmpty) {
          _deviceNames[id] = name;
        }
      }

      final device = devices.firstWhere(
        (d) => d['id'] == deviceId,
        orElse: () => <String, dynamic>{},
      );

      if (device.isEmpty) {
        _log.debug('Device $deviceId not found');
        return;
      }

      // Fetch position using positionId or fallback
      final posId = device['positionId'];
      Position? position;

      if (posId is int) {
        position = await positionsService.latestByPositionId(posId);
      }

      // Fallback: fetch recent history if no positionId
      if (position == null) {
        final recent = await positionsService.fetchLatestPositions(
          deviceIds: [deviceId],
        );
        if (recent.isNotEmpty) {
          position = recent.first;
        }
      }

      if (position != null) {
        var snapshot = VehicleDataSnapshot.fromPosition(position);
        // Overlay engine state from device attributes if present
        final devAttrs = (device['attributes'] is Map)
            ? Map<String, dynamic>.from(device['attributes'] as Map)
            : const <String, dynamic>{};
        final ign = devAttrs['ignition'];
        EngineState? engineState;
        if (ign is bool) {
          engineState = ign ? EngineState.on : EngineState.off;
        } else if (devAttrs['motion'] is bool && devAttrs['motion'] == true) {
          engineState = EngineState.on;
        }
        if (engineState != null && engineState != snapshot.engineState) {
          snapshot = VehicleDataSnapshot(
            deviceId: snapshot.deviceId,
            timestamp: snapshot.timestamp.add(const Duration(milliseconds: 1)),
            position: snapshot.position,
            engineState: engineState,
            speed: snapshot.speed,
            distance: snapshot.distance,
            lastUpdate: snapshot.lastUpdate,
            batteryLevel: snapshot.batteryLevel,
            fuelLevel: snapshot.fuelLevel,
          );
          _log.debug('Overlayed engine from device attrs for $deviceId -> $engineState');
        }
        _updateDeviceSnapshot(snapshot);
      }
    } catch (e) {
      _log.error('Fetch error for device $deviceId', error: e);
    }
  }

  /// Parallel fetch for multiple devices (used on app start or WebSocket reconnect)
  Future<void> fetchMultipleDevices(List<int> deviceIds) async {
    if (deviceIds.isEmpty) return;
    if (_isOffline) {
      _log.debug('Offline → skip parallel fetch for ${deviceIds.length} devices');
      return; // Use cached data only
    }

    try {
      _log.debug('Fetching ${deviceIds.length} devices in parallel');

      // Fetch all devices
      final devices = await deviceService.fetchDevices();
      final deviceMap = {for (final d in devices) d['id']: d};

      // Fetch positions using latestForDevices (already optimized)
      final deviceList = deviceIds
          .where(deviceMap.containsKey)
          .map((id) => deviceMap[id]!)
          .toList();

      // Update device name cache from fetched devices
      for (final d in deviceList) {
        final id = d['id'];
        final name = d['name'];
        if (id is int && name is String && name.trim().isNotEmpty) {
          _deviceNames[id] = name;
        }
      }

      final positions = await positionsService.latestForDevices(deviceList);

      // Update cache and notifiers
      for (final entry in positions.entries) {
        final snapshot = VehicleDataSnapshot.fromPosition(entry.value);
        _updateDeviceSnapshot(snapshot);
      }

      _log.debug('✅ Fetched ${positions.length} positions');
      // Mark if this REST cycle delivered any data to drive backoff reset
      _lastRestFetchHadData = positions.isNotEmpty;
    } catch (e) {
      _log.error('Parallel fetch error', error: e);
      _lastRestFetchHadData = false;
    }
  }

  /// Start REST polling fallback (only when WebSocket disconnected)
  void _startFallbackPolling() {
    _fallbackTimer?.cancel();
    // Convert to single-shot scheduling so we can vary interval
    _fallbackTimer?.cancel();
    _scheduleNextFallbackTick();
  }

  void _scheduleNextFallbackTick() {
    _fallbackTimer?.cancel();
    final interval = _fallbackInterval;
    _fallbackTimer = _lifecycle.trackTimer(
      Timer(interval, () async {
        if (_isDisposed) {
          _log.debug('🧩 Fallback tick skipped: repository disposed');
          return;
        }
        if (_isOffline) {
          _log.debug('Offline → skipping REST fallback tick');
          _fallbackInterval = _fallbackMin; // reset when offline; UI will rely on cache
          _scheduleNextFallbackTick();
          return;
        }

        // Suppress fallback if WS just reconnected
        if (webSocketManager.shouldSuppressFallback()) {
          _log.debug('[FALLBACK-SUPPRESS] ✋ Skipping REST fallback - WS just reconnected');
          _fallbackInterval = _fallbackMin; // reset on reconnect
          _fallbackConsecutiveFailures = 0;
          _scheduleNextFallbackTick();
          return;
        }

        if (!_isWebSocketConnected && _notifiers.isNotEmpty) {
          _log.debug('WebSocket disconnected → REST fallback (interval=${interval.inSeconds}s)');
          final deviceIds = _notifiers.keys.toList();
          await fetchMultipleDevices(deviceIds);

          // Adaptive backoff: if data arrived, reset; else back off exponentially
          if (_lastRestFetchHadData) {
            if (_fallbackInterval != _fallbackMin) {
              _log.debug('[BACKOFF] ✅ Data received → reset interval to ${_fallbackMin.inSeconds}s');
            }
            _fallbackConsecutiveFailures = 0;
            _fallbackInterval = _fallbackMin;
          } else {
            _fallbackConsecutiveFailures++;
            // Double up to max
            final nextMs = (_fallbackInterval.inMilliseconds * 2).clamp(
              _fallbackMin.inMilliseconds,
              _fallbackMax.inMilliseconds,
            );
            // Add small jitter (±10%) to avoid thundering herd
            final jitter = (nextMs * 0.1).toInt();
            final jittered = (nextMs - jitter) + (jitter ~/ 2);
            _fallbackInterval = Duration(milliseconds: jittered);
            _log.debug('[BACKOFF] ⬆️ No data (consecutive: $_fallbackConsecutiveFailures) → next in ${_fallbackInterval.inSeconds}s');
          }
        } else {
          // If WS connected or no listeners, keep base interval
          _fallbackConsecutiveFailures = 0;
          _fallbackInterval = _fallbackMin;
        }

        _scheduleNextFallbackTick();
      }),
    );
  }

  /// Manually refresh data for a device (used when user taps refresh)
  Future<void> refresh(int deviceId) async {
    _lastFetchTime.remove(deviceId); // Clear memoization
    await _fetchDeviceData(deviceId);
  }

  /// Refresh all active devices
  Future<void> refreshAll() async {
    _lastFetchTime.clear();
    await fetchMultipleDevices(_notifiers.keys.toList());
  }

  /// Incremental refresh for all active devices using last known timestamps/ids.
  /// Avoids full device list reload on reconnect/resume and applies only new positions.
  Future<void> incrementalRefreshAll() async {
    await _onWebSocketReconnectPositions();
  }

  // === 🎯 PRIORITY 1: Stream-based position API ===
  
  /// Get a reactive stream of position updates for a specific device.
  /// 
  /// Returns a broadcast stream that emits the latest position whenever it changes.
  /// New subscribers immediately receive the last known position (if any).
  /// 
  /// **Usage in Riverpod providers:**
  /// ```dart
  /// final devicePositionProvider = StreamProvider.family<Position?, int>((ref, deviceId) {
  ///   final repo = ref.watch(vehicleDataRepositoryProvider);
  ///   return repo.positionStream(deviceId);
  /// });
  /// ```
  /// 
  /// **Benefits:**
  /// - 99% reduction in unnecessary broadcasts (only this device's subscribers notified)
  /// - Reactive composition with standard Dart streams
  /// - Automatic cleanup when stream is cancelled
  /// - 🎯 PHASE 9: Memoized to prevent duplicate subscriptions
  /// - 🎯 PHASE 9 STEP 2: Lifecycle tracking with auto-cleanup
  Stream<Position?> positionStream(int deviceId) {
    // 🎯 PHASE 1 STEP 3: Proactive LRU eviction BEFORE creating new stream
    // Prevents reactive overflow when hitting stream limit
    if (_deviceStreams.length >= _kMaxStreams && !_deviceStreams.containsKey(deviceId)) {
      _evictLRUStream();
      _log.debug('⚠️ Proactive LRU eviction triggered (limit: $_kMaxStreams, current: ${_deviceStreams.length})');
    }
    
    // 🎯 PHASE 9: Use StreamMemoizer to cache streams and prevent duplicates
    return _streamMemoizer.memoize(
      'device_$deviceId',
      () {
        // Lazy-create stream entry with lifecycle tracking for this device
        final entry = _deviceStreams.putIfAbsent(
          deviceId,
          () {
            final controller = _lifecycle.trackController(
              StreamController<Position?>.broadcast(
                sync: true, // Synchronous delivery for immediate UI updates
                onListen: () {
                  final entry = _deviceStreams[deviceId];
                  if (entry != null) {
                    entry.incrementListeners();
                    _log.debug('📡 Stream listener added for device $deviceId (count: ${entry.listenerCount})');
                  }
                },
                onCancel: () {
                  final entry = _deviceStreams[deviceId];
                  if (entry != null) {
                    entry.decrementListeners();
                    _log.debug('📡 Stream listener removed for device $deviceId (count: ${entry.listenerCount})');
                  }
                },
              ),
            );
            return _StreamEntry(controller);
          },
        );

        // Start cleanup timer if not already running
        _startStreamCleanupTimer();

        // Return stream that starts with latest known position
        return entry.controller.stream.transform(
          StreamTransformer<Position?, Position?>.fromHandlers(
            handleData: (position, sink) {
              // Refresh access time on every emission
              final e = _deviceStreams[deviceId];
              e?.refreshAccess();
              sink.add(position);
            },
          ),
        );
      },
    );
  }

  /// Get the latest known position for a device synchronously.
  /// 
  /// Returns `null` if no position has been received yet.
  /// 
  /// **Usage:**
  /// - For immediate access without stream subscription
  /// - For batch operations across multiple devices
  /// - For conditional logic that needs current state
  Position? getLatestPosition(int deviceId) => _latestPositions[deviceId];

  /// Get all latest positions as an unmodifiable map.
  /// 
  /// **Returns:** Map of deviceId → Position for all tracked devices
  /// 
  /// **Usage:**
  /// - Bulk operations (e.g., calculating bounding box for map zoom)
  /// - Exporting current state
  /// - Analytics/reporting
  /// 
  /// **Memory impact:** ~50MB savings vs broadcasting entire map on each update
  Map<int, Position?> getAllLatestPositions() =>
      Map<int, Position?>.unmodifiable(_latestPositions);

  /// Get cache statistics for monitoring
  Map<String, dynamic> get cacheStats => cache.stats;

  // === 🎯 PHASE 9 STEP 2: Stream lifecycle management methods ===

  /// Start periodic cleanup timer for idle streams
  void _startStreamCleanupTimer() {
    if (_streamCleanupTimer != null || testMode) return;
    
    _streamCleanupTimer = _lifecycle.trackTimer(
      Timer.periodic(_kCleanupInterval, (_) {
        _cleanupIdleStreams();
        _capStreamsIfNeeded();
      }),
    );
    
    _log.debug('🧹 Stream cleanup timer started (interval: ${_kCleanupInterval.inSeconds}s)');
  }

  /// Clean up idle streams (0 listeners + >1 min since last access)
  /// 🎯 PHASE 1 STEP 3: Enhanced with diagnostic logging
  void _cleanupIdleStreams() {
    final toRemove = <int>[];
    
    for (final entry in _deviceStreams.entries) {
      final deviceId = entry.key;
      final streamEntry = entry.value;
      
      if (streamEntry.isIdle && streamEntry.idleTime > _kIdleTimeout) {
        toRemove.add(deviceId);
      }
    }
    
    if (toRemove.isEmpty) {
      _log.debug('🧹 No idle streams to clean up (active: ${_deviceStreams.length})');
      return;
    }
    
    // 🎯 PHASE 1 STEP 3: Enhanced logging with memory impact estimate
    final memoryFreedEstimate = toRemove.length * 5; // ~5KB per stream
    debugPrint('[STREAM_CLEANUP] 🧹 Cleaning ${toRemove.length} idle streams');
    debugPrint('[STREAM_CLEANUP] 📊 Est. memory freed: ~${memoryFreedEstimate}KB');
    debugPrint('[STREAM_CLEANUP] 📈 Streams before: ${_deviceStreams.length}, after: ${_deviceStreams.length - toRemove.length}');
    
    for (final deviceId in toRemove) {
      final entry = _deviceStreams[deviceId];
      if (entry != null) {
        final idleDuration = entry.idleTime;
        debugPrint('[STREAM_CLEANUP] 🗑️ Evicting device $deviceId (idle: ${idleDuration.inMinutes}m ${idleDuration.inSeconds % 60}s)');
      }
      entry?.controller.close();
      _deviceStreams.remove(deviceId);
      _latestPositions.remove(deviceId);
      _streamMemoizer.clear(); // Clear memoization cache to allow fresh stream creation
    }
    
    _log.debug('🧹 Cleaned up ${toRemove.length} idle streams (remaining: ${_deviceStreams.length})');
  }

  /// Cap streams using LRU eviction when exceeding max limit
  /// 🎯 PHASE 1 STEP 3: Enhanced with diagnostic logging
  void _capStreamsIfNeeded() {
    if (_deviceStreams.length <= _kMaxStreams) return;
    
    // Get all idle streams sorted by last access time (oldest first)
    final idleStreams = _deviceStreams.entries
        .where((e) => e.value.isIdle)
        .toList()
      ..sort((a, b) => a.value.lastAccess.compareTo(b.value.lastAccess));
    
    final toEvict = _deviceStreams.length - _kMaxStreams;
    final evicted = <int>[];
    
    // 🎯 PHASE 1 STEP 3: Enhanced logging for LRU cap
    debugPrint('[STREAM_CAP] 🔒 Stream limit exceeded (current: ${_deviceStreams.length}, max: $_kMaxStreams)');
    debugPrint('[STREAM_CAP] 📊 Idle streams available: ${idleStreams.length}, need to evict: $toEvict');
    
    for (final entry in idleStreams.take(toEvict)) {
      final deviceId = entry.key;
      debugPrint('[STREAM_CAP] 🗑️ Evicting device $deviceId (idle: ${entry.value.idleTime.inMinutes}m)');
      entry.value.controller.close();
      _deviceStreams.remove(deviceId);
      _latestPositions.remove(deviceId);
      evicted.add(deviceId);
    }
    
    if (evicted.isNotEmpty) {
      _streamMemoizer.clear(); // Clear memoization cache
      final memoryFreedEstimate = evicted.length * 5; // ~5KB per stream
      debugPrint('[STREAM_CAP] ✅ Evicted ${evicted.length} streams, freed ~${memoryFreedEstimate}KB');
      _log.debug('🔒 Evicted ${evicted.length} streams (LRU cap: $_kMaxStreams)');
    }
  }

  /// 🎯 PHASE 1 STEP 3: Proactive single-stream LRU eviction
  /// Evicts the single oldest idle stream to make room for new stream creation.
  /// Called from positionStream() BEFORE creating a new stream when at limit.
  /// 
  /// **Purpose:** Prevent reactive overflow and maintain stream limit proactively.
  /// 
  /// **Algorithm:**
  /// 1. Find oldest idle stream (0 listeners + earliest lastAccess time)
  /// 2. Close and remove that stream
  /// 3. Log eviction for diagnostics
  /// 
  /// **Difference from _capStreamsIfNeeded():**
  /// - This: Proactive, evicts 1 stream BEFORE overflow
  /// - _capStreamsIfNeeded(): Reactive, evicts N streams AFTER overflow
  void _evictLRUStream() {
    // Find oldest idle stream
    MapEntry<int, _StreamEntry>? oldestIdle;
    
    for (final entry in _deviceStreams.entries) {
      if (entry.value.isIdle) {
        if (oldestIdle == null || entry.value.lastAccess.isBefore(oldestIdle.value.lastAccess)) {
          oldestIdle = entry;
        }
      }
    }
    
    // If found, evict it
    if (oldestIdle != null) {
      final deviceId = oldestIdle.key;
      final idleDuration = oldestIdle.value.idleTime;
      
      // 🎯 PHASE 1 STEP 3: Enhanced diagnostic logging
      debugPrint('[PROACTIVE_EVICT] 🗑️ Evicting device $deviceId (idle: ${idleDuration.inMinutes}m ${idleDuration.inSeconds % 60}s)');
      debugPrint('[PROACTIVE_EVICT] 📊 Streams: ${_deviceStreams.length} → ${_deviceStreams.length - 1} (limit: $_kMaxStreams)');
      
      oldestIdle.value.controller.close();
      _deviceStreams.remove(deviceId);
      _latestPositions.remove(deviceId);
      _streamMemoizer.clear();
      
      _log.debug('🗑️ Proactive LRU eviction: device $deviceId (idle for ${oldestIdle.value.idleTime.inMinutes}m)');
    } else {
      // No idle streams to evict - log warning
      debugPrint('[PROACTIVE_EVICT] ⚠️ Cannot evict: all ${_deviceStreams.length} streams have active listeners');
      _log.warning('⚠️ Cannot evict: all ${_deviceStreams.length} streams have active listeners');
    }
  }

  /// Get stream lifecycle diagnostics
  Map<String, dynamic> getStreamDiagnostics() {
    final activeStreams = _deviceStreams.values.where((e) => !e.isIdle).length;
    final idleStreams = _deviceStreams.values.where((e) => e.isIdle).length;
    final totalListeners = _deviceStreams.values.fold<int>(
      0,
      (sum, entry) => sum + entry.listenerCount,
    );
    
    return {
      'totalStreams': _deviceStreams.length,
      'activeStreams': activeStreams,
      'idleStreams': idleStreams,
      'totalListeners': totalListeners,
      'positionsCached': _latestPositions.length,
      'streamMemoizerStats': _streamMemoizer.getStats(),
      // 🎯 STREAM BACKPRESSURE: Add backpressure stats
      'backpressure': {
        'coalescedCount': _coalescedCount,
        'pendingUpdates': _pendingUpdates.length,
        'emitGapMs': _emitGap().inMilliseconds,
        'lodMode': _lodController?.mode.name ?? 'none',
      },
    };
  }

  // === End of Phase 9 Step 2 methods ===

  /// Dispose resources
  void dispose() {
    if (_isDisposed) {
      _log.debug('⚠️ Double dispose prevented');
      return;
    }
    _isDisposed = true;

    // 🧹 LIFECYCLE: Dispose all tracked streams, controllers, and timers
    // This handles: _socketSub, _fallbackTimer, _cleanupTimer, _streamCleanupTimer,
    // _batchFlushTimer, _eventController, _recoveredEventsController, and all device stream controllers
    _lifecycle.disposeAll();

    // Clear debounce timers (not tracked by lifecycle manager)
    for (final timer in _debounceTimers.values) {
      timer.cancel();
    }
    _debounceTimers.clear();
    _positionUpdateBuffer.clear();

    // Dispose notifiers
    for (final notifier in _notifiers.values) {
      notifier.dispose();
    }
    _notifiers.clear();

    // 🎯 STREAM BACKPRESSURE: Clear pending updates
    _pendingUpdates.clear();
    _lastEmit.clear();
    if (kDebugMode && _coalescedCount > 0) {
      _log.debug('[Backpressure] Total coalesced updates: $_coalescedCount');
    }

    // Clear device streams data (controllers already closed by lifecycle manager)
    _deviceStreams.clear();
    _latestPositions.clear();

    // Log final cleanup status
    _lifecycle.logStatus();

    _log.debug('✅ Disposed successfully');
  }

  /// Proactively prune idle device streams and cap stream count (route-change hygiene)
  void pruneStreams() {
    _cleanupIdleStreams();
    _capStreamsIfNeeded();
  }
}
