import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_app_gps/core/data/vehicle_data_cache.dart';
import 'package:my_app_gps/core/data/vehicle_data_snapshot.dart';
import 'package:my_app_gps/core/database/dao/telemetry_dao.dart';
import 'package:my_app_gps/core/database/entities/telemetry_record.dart';
import 'package:my_app_gps/core/diagnostics/dev_diagnostics.dart';
import 'package:my_app_gps/core/utils/shared_prefs_holder.dart';
import 'package:my_app_gps/data/models/event.dart';
import 'package:my_app_gps/features/map/data/position_model.dart';
import 'package:my_app_gps/providers/connectivity_provider.dart';
import 'package:my_app_gps/services/device_service.dart';
import 'package:my_app_gps/services/event_service.dart';
import 'package:my_app_gps/services/positions_service.dart';
import 'package:my_app_gps/services/traccar_socket_service.dart';
import 'package:my_app_gps/services/websocket_manager_enhanced.dart';
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

  final repo = VehicleDataRepository(
    cache: cache,
    deviceService: devSvc,
    positionsService: posSvc,
    socketService: socketSvc,
    telemetryDao: telemetryDao,
    eventService: eventService,
    webSocketManager: wsManager,
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
      // Kick a refresh on reconnect (best-effort)
      repo.refreshAll();
    }
  });

  ref.onDispose(repo.dispose);
  return repo;
});

/// Centralized repository for vehicle data.
///
/// Architecture:
/// - Merges REST API + WebSocket updates
/// - Maintains in-memory + disk cache
/// - Exposes per-device ValueNotifiers
/// - Implements parallel fetch and fallback strategies
/// - Debounces/throttles updates to prevent UI flooding
class VehicleDataRepository {
  VehicleDataRepository({
    required this.cache,
    required this.deviceService,
    required this.positionsService,
    required this.socketService,
    required this.telemetryDao,
    required this.eventService,
    required this.webSocketManager,
  }) {
    _init();
  }

  final VehicleDataCache cache;
  final DeviceService deviceService;
  final PositionsService positionsService;
  final TraccarSocketService socketService;
  final TelemetryDaoBase telemetryDao;
  final EventService eventService;
  final WebSocketManagerEnhanced webSocketManager; // 🎯 PHASE 2: For fallback suppression
  // Throttle backfill to prevent duplicate runs on rapid reconnects
  DateTime? _lastBackfillRun;

  // Per-device notifiers
  final Map<int, ValueNotifier<VehicleDataSnapshot?>> _notifiers = {};

  // Debounce timers for each device
  final Map<int, Timer> _debounceTimers = {};

  // Memoization: Track last fetch time to prevent redundant calls
  final Map<int, DateTime> _lastFetchTime = {};

  // WebSocket subscription
  StreamSubscription<TraccarSocketMessage>? _socketSub;
  // Event broadcast stream (raw event maps from WebSocket)
  final StreamController<Map<String, dynamic>> _eventController =
      StreamController<Map<String, dynamic>>.broadcast();
  // Recovered (backfilled) events count stream after reconnect
  final StreamController<int> _recoveredEventsController =
      StreamController<int>.broadcast();

  // REST fallback timer
  Timer? _fallbackTimer;

  // Memory cleanup timer (runs every hour)
  Timer? _cleanupTimer;

  // Connection state flags
  bool _isWebSocketConnected = false;
  bool _isOffline = false; // unified offline flag (network or backend)
  bool _isDisposed = false; // Safety guard for async operations
  bool _everConnected = false; // Track initial connect vs reconnect

  static const _debounceDelay = Duration(milliseconds: 300);
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
      if (kDebugMode) {
        debugPrint('[VehicleRepo] ❌ Failed to fetch device $id: $e');
      }
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
      // Subscribe to WebSocket updates (connect returns a stream)
      _socketSub = socketService.connect().listen(_handleSocketMessage);

      // Start REST fallback timer (disabled in tests)
      if (!VehicleDataRepository.testMode) {
        _startFallbackPolling();
      } else if (kDebugMode) {
        debugPrint('[VehicleRepo][TEST] Skipping REST fallback timer');
      }

      // Start periodic cleanup timer to prevent memory leaks
      _startCleanupTimer();

      if (kDebugMode) {
        debugPrint(
            '[VehicleRepo] Initialized with deferred WebSocket connection',);
      }
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
    if (kDebugMode) {
      debugPrint('[VehicleRepo] Connectivity changed → offline=$_isOffline');
    }
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
      if (kDebugMode) {
        debugPrint(
            '[VehicleRepo] Telemetry retention applied. Cutoff: $cutoff',);
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[VehicleRepo] Telemetry retention failed: $e');
      }
    }
  }

  /// Start periodic cleanup timer (runs every hour)
  void _startCleanupTimer() {
    _cleanupTimer?.cancel();
    if (!VehicleDataRepository.testMode) {
      _cleanupTimer = Timer.periodic(
        const Duration(hours: 1),
        (_) => _cleanupStaleDevices(),
      );
      if (kDebugMode) {
        debugPrint('[VehicleRepo] 🧹 Cleanup timer started (every 1 hour)');
      }
    }
  }

  /// Remove and dispose stale device notifiers (older than 7 days)
  void _cleanupStaleDevices() {
    if (_isDisposed) {
      if (kDebugMode) {
        debugPrint('[CONCURRENCY] 🧩 Cleanup skipped: repository disposed');
      }
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

    if (kDebugMode) {
      debugPrint('[VehicleRepo] 🧹 Cleaned up $removed stale devices at $now');
    }
  }

  /// Test-only method to invoke cleanup (exposed for unit tests)
  @visibleForTesting
  void invokeTestCleanup() => _cleanupStaleDevices();

  /// Pre-warm cache by loading all cached snapshots into notifiers
  void _prewarmCache() {
    try {
      final allCached = cache.loadAll();
      if (allCached.isEmpty) {
        if (kDebugMode) {
          debugPrint('[VehicleRepo] No cached data to prewarm');
        }
        return;
      }
      for (final entry in allCached.entries) {
        final deviceId = entry.key;
        final snapshot = entry.value;
        _notifiers[deviceId] = ValueNotifier<VehicleDataSnapshot?>(snapshot);
      }
      if (kDebugMode) {
        debugPrint(
            '[VehicleRepo] ✅ Pre-warmed cache with ${allCached.length} devices',);
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[VehicleRepo] Cache pre-warm error: $e');
      }
    }
  }

  /// Handle incoming WebSocket messages
  Future<void> _handleSocketMessage(TraccarSocketMessage msg) async {
    if (_isDisposed) {
      if (kDebugMode) {
        debugPrint(
            '[CONCURRENCY] 🧩 Socket message dropped: repository disposed',);
      }
      return;
    }

    if (msg.type == 'connected') {
      _isWebSocketConnected = true;
      if (kDebugMode) {
        debugPrint('[VehicleRepo] WebSocket connected');
      }
      // If this is a reconnect (not the very first connection), backfill missed events.
      if (_everConnected) {
        unawaited(_onWebSocketReconnect());
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
        if (kDebugMode) {
          debugPrint('[VehicleRepo][WS] events payload: ${msg.payload}');
        }
        final payload = msg.payload;
        final events =
            payload is List ? List<dynamic>.from(payload) : <dynamic>[payload];
        for (final e in events) {
          if (e is Map<String, dynamic>) {
            // Broadcast raw event to listeners (Notifications pipeline)
            if (!_eventController.isClosed) {
              _eventController.add(e);
              if (kDebugMode) {
                debugPrint(
                    '[VehicleRepo] Broadcasting event ${e['type'] ?? ''}',);
              }
            }
            final posId = e['positionId'] as int?;
            final deviceId = e['deviceId'] as int?;
            if (kDebugMode) {
              debugPrint(
                  '[VehicleRepo][WS] event for deviceId=$deviceId posId=$posId',);
            }
            // If event contains a positionId, fetch that position (likely contains attributes)
            if (posId != null) {
              try {
                final p = await positionsService.latestByPositionId(posId);
                if (p != null) {
                  if (kDebugMode) {
                    debugPrint(
                        '[VehicleRepo][WS] fetched Position for posId=$posId -> device=${p.deviceId}',);
                  }
                  _handlePositionUpdates([p]);
                }
              } catch (e) {
                if (kDebugMode) {
                  debugPrint(
                      '[VehicleRepo] Failed to fetch position for positionId=$posId: $e',);
                }
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
                  if (kDebugMode) {
                    debugPrint(
                        '[VehicleRepo][WS] applying event-based engine update for device=$deviceId -> $engineState at $ts',);
                  }
                  _updateDeviceSnapshot(partial);
                }
              }

              // Also refresh device data if no positionId to keep other fields fresh
              if (posId == null) {
                _lastFetchTime.remove(deviceId);
                if (kDebugMode) {
                  debugPrint(
                      '[VehicleRepo][WS] refreshing device data for deviceId=$deviceId (event)',);
                }
                unawaited(_fetchDeviceData(deviceId));
              }
            }
          }
        }
      } catch (e) {
        if (kDebugMode) debugPrint('[VehicleRepo] Event handling error: $e');
      }
      return;
    }

    // Devices payload: updated device metadata or positionId may be present
    if (msg.type == 'devices' && msg.payload != null) {
      try {
        if (kDebugMode) {
          debugPrint('[VehicleRepo][WS] devices payload: ${msg.payload}');
        }
        final payload = msg.payload;
        final devices =
            payload is List ? List<dynamic>.from(payload) : <dynamic>[payload];
        for (final d in devices) {
          if (d is Map<String, dynamic>) {
            final posId = d['positionId'] as int?;
            final deviceId = d['id'] as int?;
            if (kDebugMode) {
              debugPrint(
                  '[VehicleRepo][WS] device update for deviceId=$deviceId posId=$posId',);
            }

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
                if (kDebugMode) {
                  debugPrint(
                      '[WS] 🔁 Duplicate skipped for deviceId=$deviceId',);
                }
                continue; // Skip processing identical payload
              }
              _lastDevicePayloadHash[deviceId] = hash;
            }
            if (posId != null) {
              try {
                final p = await positionsService.latestByPositionId(posId);
                if (p != null) {
                  if (kDebugMode) {
                    debugPrint(
                        '[VehicleRepo][WS] fetched Position for device posId=$posId -> device=${p.deviceId}',);
                  }
                  _handlePositionUpdates([p]);
                }
              } catch (e) {
                if (kDebugMode) {
                  debugPrint(
                      '[VehicleRepo] Failed to fetch position for device update posId=$posId: $e',);
                }
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
                  if (kDebugMode) {
                    debugPrint(
                        '[VehicleRepo][WS] applying device-based engine update for device=$deviceId -> $engineState at $ts',);
                  }
                  _updateDeviceSnapshot(partial);
                }
              }

              // Refresh device data if no positionId to keep other fields fresh
              if (posId == null) {
                if (kDebugMode) {
                  debugPrint(
                      '[VehicleRepo][WS] refreshing device data for deviceId=$deviceId (device update)',);
                }
                _lastFetchTime.remove(deviceId);
                unawaited(_fetchDeviceData(deviceId));
              }
            }
          }
        }
      } catch (e) {
        if (kDebugMode) debugPrint('[VehicleRepo] Devices handling error: $e');
      }
      return;
    }
  }

  /// On WebSocket reconnect, fetch and replay missed events to downstream consumers
  Future<void> _onWebSocketReconnect() async {
    // Throttle: avoid duplicate runs in quick succession
    final now = DateTime.now();
    if (_lastBackfillRun != null &&
        now.difference(_lastBackfillRun!) < const Duration(seconds: 5)) {
      if (kDebugMode) {
        debugPrint('[VehicleRepo] ⏳ Skipping backfill (throttled)');
      }
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

    if (kDebugMode) {
      debugPrint(
          '[VehicleRepo] 🔄 Reconnected — backfilling events from $from to $to',);
      if (replayAnchor != null) {
        debugPrint(
            '[VehicleRepo] ⏱️ Using replay anchor from last processed event',);
      } else if (cachedTs != null) {
        debugPrint('[VehicleRepo] 📦 Using latest cached event timestamp');
      }
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
          if (kDebugMode) {
            debugPrint(
                '[VehicleRepo] ⚠️ Failed to load devices for backfill: $e',);
          }
        }
      }

      if (deviceIds.isEmpty) {
        if (kDebugMode) {
          debugPrint('[VehicleRepo] ⚠️ No deviceIds available for backfill');
        }
        return;
      }

      // Add a safety margin to the from time to avoid off-by-one gaps
      final safeFrom = from.subtract(const Duration(minutes: 5));

      if (kDebugMode) {
        debugPrint('[VehicleRepo] 📆 Backfill window (safe): $safeFrom → $to');
        debugPrint(
            '[VehicleRepo] 🧭 Backfilling per-device for ${deviceIds.length} device(s): $deviceIds',);
      }

      // Mark a backfill request in diagnostics (counting once per reconnect)
      if (kDebugMode) {
        DevDiagnostics.instance.onBackfillRequested(deviceIds.length);
      }
      final allMissed = <Event>[];
      for (final id in deviceIds) {
        try {
          if (kDebugMode) {
            debugPrint('[VehicleRepo] 🔎 Fetching events for device $id');
          }
          final list = await eventService.fetchEvents(
            deviceId: id,
            from: safeFrom,
            to: to,
          );
          if (list.isNotEmpty) allMissed.addAll(list);
        } catch (e) {
          if (kDebugMode) {
            debugPrint(
                '[VehicleRepo] ⚠️ Backfill fetch failed for device $id: $e',);
          }
        }
      }

      if (allMissed.isEmpty) {
        if (kDebugMode) debugPrint('[VehicleRepo] ✅ No missed events');
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
      if (kDebugMode) {
        debugPrint(
            '[VehicleRepo] ✅ Replayed ${allMissed.length} missed events',);
      }
      // Diagnostics: applied backfilled events
      if (kDebugMode) {
        try {
          // Avoid a hard dependency in release builds
          // ignore: unnecessary_statements
          DevDiagnostics.instance.onBackfillApplied(allMissed.length);
        } catch (_) {}
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[VehicleRepo] ⚠️ Missed-event fetch failed: $e');
      }
    }
  }

  /// Process position updates (from WebSocket or REST)
  void _handlePositionUpdates(List<Position> positions) {
    if (positions.isEmpty) return;

    for (final pos in positions) {
      // 1) Fast path: per-device dedup by last positionId
      final currentId = pos.id;
      if (currentId != null) {
        final lastId = _lastPositionId[pos.deviceId];
        if (lastId != null && lastId == currentId) {
          if (kDebugMode) {
            debugPrint(
                '[WS] 🔁 Duplicate positionId skipped for deviceId=${pos.deviceId} (posId=$currentId)',);
          }
          continue; // Identical position already processed
        }
        _lastPositionId[pos.deviceId] = currentId;
      }

      // 2) Fallback: hash-based dedup when id is missing/unstable
      if (currentId == null) {
        final hash = _hashPosition(pos);
        final prev = _lastPositionHash[pos.deviceId];
        if (prev != null && prev == hash) {
          if (kDebugMode) {
            debugPrint(
                '[WS] 🔁 Duplicate skipped for deviceId=${pos.deviceId}',);
          }
          continue; // Skip duplicate
        }
        _lastPositionHash[pos.deviceId] = hash;
      }

      final snapshot = VehicleDataSnapshot.fromPosition(pos);

      // Debounce: Delay emitting to notifier to avoid flooding
      _debounceTimers[pos.deviceId]?.cancel();
      _debounceTimers[pos.deviceId] = Timer(_debounceDelay, () {
        _updateDeviceSnapshot(snapshot);
      });
    }

    if (kDebugMode) {
      debugPrint(
          '[VehicleRepo] Processed ${positions.length} position updates',);
    }
  }

  /// Update cache and notify listeners for a device
  void _updateDeviceSnapshot(VehicleDataSnapshot snapshot) {
    if (kDebugMode) {
      final existing = _notifiers[snapshot.deviceId]?.value;
      debugPrint(
          '[VehicleRepo] Updating snapshot for device=${snapshot.deviceId}',);
      debugPrint('[VehicleRepo]   incoming: $snapshot');
      debugPrint('[VehicleRepo]   existing: $existing');

      // Log engine state changes explicitly
      if (snapshot.engineState != null &&
          snapshot.engineState != existing?.engineState) {
        debugPrint(
            '[VehicleRepo] 🔧 ENGINE STATE CHANGE: ${existing?.engineState} → ${snapshot.engineState}',);
      }
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
        if (kDebugMode) {
          debugPrint('[VehicleRepo]   merged: $merged');
          debugPrint(
              '[VehicleRepo]   ✅ Notifier updated - listeners will be notified',);
        }
      } else if (kDebugMode) {
        debugPrint(
            '[VehicleRepo]   ⏭️ No effective change, notifier not updated',);
      }
    } else {
      _notifiers[snapshot.deviceId] =
          ValueNotifier<VehicleDataSnapshot?>(snapshot);
      if (kDebugMode) {
        debugPrint(
            '[VehicleRepo]   ✅ New notifier created for device ${snapshot.deviceId}',);
      }
    }
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
      if (kDebugMode) {
        debugPrint('[VehicleRepo] Offline → skip fetch for device $deviceId');
      }
      return; // Use cached data only
    }

    final lastFetch = _lastFetchTime[deviceId];
    if (lastFetch != null &&
        DateTime.now().difference(lastFetch) < _minFetchInterval) {
      if (kDebugMode) {
        debugPrint(
            '[VehicleRepo] Skipping fetch for device $deviceId (fetched recently)',);
      }
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
        if (kDebugMode) {
          debugPrint('[VehicleRepo] Device $deviceId not found');
        }
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
          if (kDebugMode) {
            debugPrint(
                '[VehicleRepo] Overlayed engine from device attrs for $deviceId -> $engineState',);
          }
        }
        _updateDeviceSnapshot(snapshot);
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[VehicleRepo] Fetch error for device $deviceId: $e');
      }
    }
  }

  /// Parallel fetch for multiple devices (used on app start or WebSocket reconnect)
  Future<void> fetchMultipleDevices(List<int> deviceIds) async {
    if (deviceIds.isEmpty) return;
    if (_isOffline) {
      if (kDebugMode) {
        debugPrint(
            '[VehicleRepo] Offline → skip parallel fetch for ${deviceIds.length} devices',);
      }
      return; // Use cached data only
    }

    try {
      if (kDebugMode) {
        debugPrint(
            '[VehicleRepo] Fetching ${deviceIds.length} devices in parallel',);
      }

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

      if (kDebugMode) {
        debugPrint('[VehicleRepo] ✅ Fetched ${positions.length} positions');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[VehicleRepo] Parallel fetch error: $e');
      }
    }
  }

  /// Start REST polling fallback (only when WebSocket disconnected)
  void _startFallbackPolling() {
    _fallbackTimer?.cancel();
    _fallbackTimer = Timer.periodic(_restFallbackInterval, (_) {
      if (_isDisposed) {
        if (kDebugMode) {
          debugPrint(
              '[CONCURRENCY] 🧩 Fallback tick skipped: repository disposed',);
        }
        return;
      }
      if (_isOffline) {
        if (kDebugMode) {
          debugPrint('[VehicleRepo] Offline → skipping REST fallback tick');
        }
        return; // No network activity while offline
      }
      
      // 🎯 PHASE 2: Suppress fallback if WebSocket just reconnected
      if (webSocketManager.shouldSuppressFallback()) {
        if (kDebugMode) {
          debugPrint('[VehicleRepo][FALLBACK-SUPPRESS] ✋ Skipping REST fallback - WS just reconnected');
        }
        return;
      }
      
      if (!_isWebSocketConnected && _notifiers.isNotEmpty) {
        if (kDebugMode) {
          debugPrint(
              '[VehicleRepo] WebSocket disconnected, using REST fallback',);
        }
        final deviceIds = _notifiers.keys.toList();
        fetchMultipleDevices(deviceIds);
      }
    });
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

  /// Get cache statistics for monitoring
  Map<String, dynamic> get cacheStats => cache.stats;

  /// Dispose resources
  void dispose() {
    if (_isDisposed) {
      if (kDebugMode) {
        debugPrint('[CONCURRENCY] ⚠️ Double dispose prevented');
      }
      return;
    }
    _isDisposed = true;

    _socketSub?.cancel();
    _fallbackTimer?.cancel();
    _cleanupTimer?.cancel();
    _eventController.close();
    _recoveredEventsController.close();

    for (final timer in _debounceTimers.values) {
      timer.cancel();
    }
    _debounceTimers.clear();

    for (final notifier in _notifiers.values) {
      notifier.dispose();
    }
    _notifiers.clear();

    if (kDebugMode) {
      debugPrint('[VehicleRepo] Disposed');
    }
  }
}
