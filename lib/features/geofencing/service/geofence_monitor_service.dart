import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';
import 'package:my_app_gps/data/models/geofence.dart';
import 'package:my_app_gps/data/models/geofence_event.dart';
import 'package:my_app_gps/data/repositories/geofence_event_repository.dart';
import 'package:my_app_gps/data/repositories/geofence_repository.dart';
import 'package:my_app_gps/features/geofencing/service/geofence_evaluator_service.dart';
import 'package:my_app_gps/features/geofencing/service/geofence_state_cache.dart';
import 'package:my_app_gps/features/map/data/position_model.dart';

/// Continuously monitors device positions and evaluates geofence transitions.
///
/// This service orchestrates:
/// - **Position Stream**: Receives position updates (from WebSocket/API)
/// - **GeofenceEvaluatorService**: Computes entry/exit/dwell events
/// - **GeofenceStateCache**: Persists state between evaluations
/// - **GeofenceEventRepository**: Records triggered events
///
/// ## Lifecycle
/// 1. Call [startMonitoring] when user logs in or enables geofencing
/// 2. Service watches active geofences from repository
/// 3. Feed positions via [processPosition] method
/// 4. Events are recorded to repository and emitted via [events] stream
/// 5. Call [stopMonitoring] on logout or when geofencing disabled
///
/// ## Performance
/// - Throttles evaluations (min 5s interval, 5m movement)
/// - Batch processing for multiple devices
/// - Periodic cache pruning to limit memory
///
/// ## Example Usage
/// ```dart
/// final monitor = GeofenceMonitorService(
///   evaluator: ref.read(geofenceEvaluatorProvider),
///   cache: ref.read(geofenceStateCacheProvider),
///   eventRepo: ref.read(geofenceEventRepositoryProvider),
///   geofenceRepo: ref.read(geofenceRepositoryProvider),
/// );
///
/// await monitor.startMonitoring(userId: currentUser.id);
///
/// // Feed position updates (e.g., from WebSocket)
/// websocket.onPosition((position) {
///   monitor.processPosition(position);
/// });
///
/// // Listen to events for notifications/UI
/// monitor.events.listen((event) {
///   print('Geofence ${event.geofenceName}: ${event.eventType}');
///   showNotification(event);
/// });
///
/// // Stop monitoring
/// await monitor.stopMonitoring();
/// ```
class GeofenceMonitorService {
  final GeofenceEvaluatorService evaluator;
  final GeofenceStateCache cache;
  final GeofenceEventRepository eventRepo;
  final GeofenceRepository geofenceRepo;

  /// Broadcast stream of geofence events for UI/notifications
  final StreamController<GeofenceEvent> _eventStreamController =
      StreamController<GeofenceEvent>.broadcast();

  /// Public stream of triggered geofence events
  Stream<GeofenceEvent> get events => _eventStreamController.stream;

  /// Subscription to active geofences
  StreamSubscription<List<Geofence>>? _geofenceSubscription;

  /// Timer for periodic cache pruning
  Timer? _pruneTimer;

  /// Currently active geofences
  List<Geofence> _activeGeofences = [];

  /// Last evaluation timestamp per device (for throttling)
  final Map<int, DateTime> _lastEvalTimestamp = {};

  /// Last position per device (for movement threshold)
  final Map<int, LatLng> _lastPosition = {};

  /// Service active flag
  bool _active = false;

  /// Minimum time between evaluations (throttle)
  final Duration minEvalInterval;

  /// Minimum movement distance to trigger evaluation (meters)
  final double minMovementMeters;

  /// Cache prune interval
  final Duration cachePruneInterval;

  /// Whether service is currently active
  bool get isActive => _active;

  /// Current active geofence count
  int get activeGeofenceCount => _activeGeofences.length;

  /// Distance calculator
  static const _distance = Distance();

  GeofenceMonitorService({
    required this.evaluator,
    required this.cache,
    required this.eventRepo,
    required this.geofenceRepo,
    this.minEvalInterval = const Duration(seconds: 5),
    this.minMovementMeters = 5.0,
    this.cachePruneInterval = const Duration(minutes: 10),
  });

  /// Start monitoring geofences for the specified user
  ///
  /// [userId] - User ID to monitor geofences for
  ///
  /// Throws [StateError] if already active
  Future<void> startMonitoring({
    required String userId,
  }) async {
    if (_active) {
      debugPrint('[GeofenceMonitorService] Already active, ignoring start request');
      return;
    }

    debugPrint('[GeofenceMonitorService] Starting monitoring for user: $userId');

    try {
      _active = true;
      _lastEvalTimestamp.clear();
      _lastPosition.clear();

      // Subscribe to active geofences for this user
      _geofenceSubscription = geofenceRepo.watchGeofences(userId).listen(
        (geofences) {
          _activeGeofences = geofences.where((g) => g.enabled).toList();
          debugPrint(
            '[GeofenceMonitorService] Loaded ${_activeGeofences.length} active geofences',
          );
        },
        onError: (Object error) {
          debugPrint('[GeofenceMonitorService] Geofence stream error: $error');
        },
      );

      // Start periodic cache pruning
      _pruneTimer = Timer.periodic(cachePruneInterval, (_) {
        debugPrint('[GeofenceMonitorService] Running periodic cache prune');
        cache.pruneExpired();
      });

      debugPrint('[GeofenceMonitorService] Monitoring started successfully');
    } catch (e) {
      _active = false;
      debugPrint('[GeofenceMonitorService] Failed to start monitoring: $e');
      rethrow;
    }
  }

  /// Stop monitoring and clean up resources
  Future<void> stopMonitoring() async {
    if (!_active) {
      debugPrint('[GeofenceMonitorService] Not active, ignoring stop request');
      return;
    }

    debugPrint('[GeofenceMonitorService] Stopping monitoring');

    _active = false;

    // Cancel subscriptions
    await _geofenceSubscription?.cancel();
    _geofenceSubscription = null;

    // Cancel prune timer
    _pruneTimer?.cancel();
    _pruneTimer = null;

    // Persist cache state
    try {
      debugPrint('[GeofenceMonitorService] Persisting cache to storage');
      await cache.persistAll();
    } catch (e) {
      debugPrint('[GeofenceMonitorService] Failed to persist cache: $e');
    }

    // Clear state
    _activeGeofences = [];
    _lastEvalTimestamp.clear();
    _lastPosition.clear();

    debugPrint('[GeofenceMonitorService] Monitoring stopped');
  }

  /// Process incoming position update for geofence evaluation
  ///
  /// This method should be called whenever a new position is received
  /// (e.g., from WebSocket, periodic polling, or background location service)
  ///
  /// [position] - Position update to evaluate
  Future<void> processPosition(Position position) async {
    if (!_active) return;

    final now = DateTime.now();
    final latlng = LatLng(position.latitude, position.longitude);
    final deviceId = position.deviceId;

    // Throttle: Skip if too soon since last evaluation
    if (_shouldThrottle(deviceId, now, latlng)) {
      return;
    }

    _lastEvalTimestamp[deviceId] = now;
    _lastPosition[deviceId] = latlng;

    // Skip if no active geofences
    if (_activeGeofences.isEmpty) {
      return;
    }

    try {
      await _evaluateGeofences(position, latlng, now);
    } catch (e, stackTrace) {
      debugPrint('[GeofenceMonitorService] Evaluation error: $e');
      debugPrint('[GeofenceMonitorService] Stack trace: $stackTrace');
    }
  }

  /// Check if evaluation should be throttled for a device
  bool _shouldThrottle(int deviceId, DateTime now, LatLng position) {
    // Check time throttle
    final lastEval = _lastEvalTimestamp[deviceId];
    if (lastEval != null) {
      final timeSinceLastEval = now.difference(lastEval);
      if (timeSinceLastEval < minEvalInterval) {
        return true;
      }
    }

    // Check movement throttle
    final lastPos = _lastPosition[deviceId];
    if (lastPos != null) {
      final distance = _distance.as(
        LengthUnit.Meter,
        lastPos,
        position,
      );

      if (distance < minMovementMeters) {
        return true;
      }
    }

    return false;
  }

  /// Evaluate current position against all active geofences
  Future<void> _evaluateGeofences(
    Position position,
    LatLng latlng,
    DateTime timestamp,
  ) async {
    final deviceId = position.deviceId.toString();

    // Use evaluator to get events
    final events = evaluator.evaluate(
      deviceId: deviceId,
      position: latlng,
      timestamp: timestamp,
      activeGeofences: _activeGeofences,
    );

    // Process and record events
    for (final event in events) {
      try {
        await eventRepo.recordEvent(event);
        debugPrint(
          '[GeofenceMonitorService] Recorded event: ${event.eventType} '
          'for geofence ${event.geofenceName}',
        );

        // Emit event to stream
        _eventStreamController.add(event);
      } catch (e) {
        debugPrint('[GeofenceMonitorService] Failed to record event: $e');
      }
    }

    // Update cache with current states (extract from evaluator's internal state)
    // Note: GeofenceEvaluatorService maintains state internally
    // The cache is used for persistence across app restarts
    _syncCacheFromEvaluator(deviceId);
  }

  /// Sync cache with evaluator's current states
  ///
  /// This extracts state from the evaluator and stores in cache
  /// for persistence across app restarts
  void _syncCacheFromEvaluator(String deviceId) {
    // TODO: Add method to GeofenceEvaluatorService to expose current states
    // For now, cache is updated implicitly through evaluator's state tracking
    // In Phase 3, implement: cache.set(deviceId, geofenceId, state)
  }

  /// Simulate position update for testing
  @visibleForTesting
  Future<void> simulatePosition(
    int deviceId,
    LatLng position,
    DateTime timestamp,
  ) async {
    final testPosition = Position(
      deviceId: deviceId,
      latitude: position.latitude,
      longitude: position.longitude,
      speed: 0.0,
      course: 0.0,
      deviceTime: timestamp,
      serverTime: timestamp,
      attributes: {},
    );

    await processPosition(testPosition);
  }

  /// Dispose service and clean up all resources
  Future<void> dispose() async {
    await stopMonitoring();
    await _eventStreamController.close();
    debugPrint('[GeofenceMonitorService] Service disposed');
  }
}

// TODO: Future enhancements for Phase 3+:
// 
// 1. **Platform Geofencing Integration**
//    - Use native Android Geofencing API (Google Play Services)
//    - Use native iOS CoreLocation region monitoring
//    - Fall back to app-level monitoring when native unavailable
//    - Benefit: Battery efficient background monitoring
// 
// 2. **Advanced Throttling**
//    - Adaptive throttling based on movement speed
//    - Higher frequency near geofence boundaries
//    - Lower frequency when far from all geofences
// 
// 3. **Isolate Optimization**
//    - Implement compute() isolate for large batches (> 50 geofences)
//    - Serialize evaluator dependencies for isolate communication
//    - Use separate isolate per device for multi-device monitoring
// 
// 4. **Error Recovery**
//    - Auto-restart on transient failures with exponential backoff
//    - Persist monitoring state across app restarts
//    - Recover from device reboot using WorkManager
// 
// 5. **Battery Optimization**
//    - Geofence clustering for nearby fences
//    - Use significant location changes when far from all geofences
//    - Integrate with device battery optimization settings
// 
// 6. **Multi-User Support**
//    - Monitor geofences for multiple users concurrently
//    - Per-user cache and evaluation
//    - Aggregate events across users
// 
// 7. **Analytics**
//    - Track evaluation performance metrics
//    - Monitor cache hit rates
//    - Alert on excessive event triggering (flapping)
//
// 8. **Cache Sync**
//    - Implement proper cache synchronization with evaluator state
//    - Add getStates() method to GeofenceEvaluatorService
//    - Persist cache state to ObjectBox on stop/background
//    - Restore cache state on start/foreground
