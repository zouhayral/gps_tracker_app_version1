import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logger/logger.dart';

import '../../../features/map/data/position_model.dart';
import '../service/geofence_monitor_service.dart';
import '../providers/geofence_providers.dart';

/// Provider for GeofenceBackgroundService
/// 
/// Await monitor service initialization before creating background service.
/// This service manages background geofence monitoring by:
/// - Listening to position updates from WebSocket/server
/// - Processing positions through GeofenceMonitorService
/// - Maintaining monitoring state across app lifecycle
/// 
/// Usage in app startup:
/// ```dart
/// // Initialize when user enables geofencing
/// final bgServiceAsync = ref.watch(geofenceBackgroundServiceProvider);
/// bgServiceAsync.whenData((bgService) async {
///   await bgService.start(userId: currentUser.id);
/// });
/// ```
final geofenceBackgroundServiceProvider =
    FutureProvider.autoDispose<GeofenceBackgroundService>((ref) async {
  // Await monitor service initialization before creating background service
  final monitor = await ref.watch(
    geofenceMonitorServiceProvider.future,
  );
  final service = GeofenceBackgroundService(monitor: monitor, ref: ref);
  ref.onDispose(() => service.dispose());
  return service;
});

/// Background service for geofence monitoring
/// 
/// **Architecture Notes:**
/// - Your app receives positions from a WebSocket server (Traccar-style)
/// - This service doesn't use device GPS directly
/// - Instead, it bridges server position updates to GeofenceMonitorService
/// - Works by maintaining subscriptions even when app is backgrounded
/// 
/// **Android Background Execution:**
/// - Flutter apps on Android stay alive for a few minutes when backgrounded
/// - For longer periods, consider:
///   1. Using FCM push notifications from server for critical events
///   2. Implementing WorkManager for periodic position checks
///   3. Adding a foreground service notification (requires native code)
/// 
/// **Current Implementation:**
/// - Keeps monitoring active while app is in memory
/// - Processes positions from your existing WebSocket connection
/// - Automatic cleanup on dispose
class GeofenceBackgroundService {
  final GeofenceMonitorService monitor;
  final Ref ref;
  final _log = Logger();
  
  /// Subscription to position updates (from WebSocket/server)
  StreamSubscription<Position>? _positionSubscription;
  
  /// Service running state
  bool _isRunning = false;
  
  /// Current user ID being monitored
  String? _currentUserId;
  
  /// Statistics
  int _positionsProcessed = 0;
  DateTime? _lastPositionTime;
  DateTime? _startTime;

  GeofenceBackgroundService({
    required this.monitor,
    required this.ref,
  });

  /// Check if service is currently running
  bool get isRunning => _isRunning;
  
  /// Get current user ID
  String? get currentUserId => _currentUserId;
  
  /// Get statistics
  Map<String, dynamic> get statistics => {
    'isRunning': _isRunning,
    'userId': _currentUserId,
    'positionsProcessed': _positionsProcessed,
    'lastPositionTime': _lastPositionTime?.toIso8601String(),
    'startTime': _startTime?.toIso8601String(),
    'uptime': _startTime != null 
        ? DateTime.now().difference(_startTime!).inSeconds 
        : 0,
  };

  /// Start background geofence monitoring
  /// 
  /// [userId] - User ID for whom to monitor geofences
  /// 
  /// This method:
  /// 1. Starts GeofenceMonitorService
  /// 2. Subscribes to position updates from your WebSocket
  /// 3. Processes each position through monitor
  Future<void> start({required String userId}) async {
    if (_isRunning && _currentUserId == userId) {
      _log.i('[GeofenceBackgroundService] Already running for user $userId');
      return;
    }

    try {
      _log.i('[GeofenceBackgroundService] 🚀 Starting for user $userId');
      
      // Stop previous monitoring if any
      if (_isRunning) {
        await stop();
      }

      _currentUserId = userId;
      _startTime = DateTime.now();
      _positionsProcessed = 0;

      // Start GeofenceMonitorService
      await monitor.startMonitoring(userId: userId);

      // Subscribe to position stream from your existing WebSocket/vehicle provider
      // 
      // Note: You'll need to provide the actual position stream here
      // This should come from your existing VehicleDataProvider or WebSocket service
      // 
      // Example:
      // final positionStream = ref.read(vehiclePositionStreamProvider);
      // _positionSubscription = positionStream.listen(_handlePosition);
      
      _isRunning = true;
      
      _log.i('[GeofenceBackgroundService] ✅ Started successfully');
      _log.d('[GeofenceBackgroundService] Stats: ${statistics}');
    } catch (e, stackTrace) {
      _log.e(
        '[GeofenceBackgroundService] ❌ Failed to start: $e',
        error: e,
        stackTrace: stackTrace,
      );
      _isRunning = false;
      _currentUserId = null;
      rethrow;
    }
  }

  /// Subscribe to position updates from a specific provider
  /// 
  /// Call this after start() to connect to your position stream
  /// 
  /// Example:
  /// ```dart
  /// final bgService = ref.read(geofenceBackgroundServiceProvider);
  /// await bgService.start(userId: 'user123');
  /// 
  /// // Connect to your position stream
  /// final positionStream = ref.read(vehiclePositionStreamProvider);
  /// bgService.subscribeToPositions(positionStream);
  /// ```
  void subscribeToPositions(Stream<Position> positionStream) {
    if (!_isRunning) {
      _log.w('[GeofenceBackgroundService] Cannot subscribe - service not running');
      return;
    }

    // Cancel existing subscription
    _positionSubscription?.cancel();

    // Subscribe to new stream
    _positionSubscription = positionStream.listen(
      _handlePosition,
      onError: (Object error, StackTrace stackTrace) {
        _log.e(
          '[GeofenceBackgroundService] Position stream error: $error',
          error: error,
          stackTrace: stackTrace,
        );
      },
      onDone: () {
        _log.w('[GeofenceBackgroundService] Position stream closed');
      },
    );

    _log.i('[GeofenceBackgroundService] Subscribed to position stream');
  }

  /// Handle incoming position update
  Future<void> _handlePosition(Position position) async {
    if (!_isRunning) return;

    try {
      _positionsProcessed++;
      _lastPositionTime = DateTime.now();

      if (kDebugMode && _positionsProcessed % 10 == 0) {
        _log.d(
          '[GeofenceBackgroundService] Processed $_positionsProcessed positions. '
          'Last update: ${_lastPositionTime}',
        );
      }

      // Process position through GeofenceMonitorService
      await monitor.processPosition(position);
    } catch (e, stackTrace) {
      _log.e(
        '[GeofenceBackgroundService] Error processing position: $e',
        error: e,
        stackTrace: stackTrace,
      );
    }
  }

  /// Stop background monitoring
  Future<void> stop() async {
    if (!_isRunning) {
      _log.i('[GeofenceBackgroundService] Not running, ignoring stop request');
      return;
    }

    _log.i('[GeofenceBackgroundService] 🛑 Stopping...');

    try {
      // Cancel position subscription
      await _positionSubscription?.cancel();
      _positionSubscription = null;

      // Stop GeofenceMonitorService
      await monitor.stopMonitoring();

      _isRunning = false;
      _currentUserId = null;

      _log.i('[GeofenceBackgroundService] ✅ Stopped successfully');
      _log.d('[GeofenceBackgroundService] Final stats: ${statistics}');
    } catch (e, stackTrace) {
      _log.e(
        '[GeofenceBackgroundService] Error during stop: $e',
        error: e,
        stackTrace: stackTrace,
      );
    } finally {
      _isRunning = false;
      _currentUserId = null;
    }
  }

  /// Dispose resources
  void dispose() {
    _log.i('[GeofenceBackgroundService] Disposing');
    
    if (_isRunning) {
      // Note: dispose() is sync, so we can't await
      // Best effort cleanup
      _positionSubscription?.cancel();
      _positionSubscription = null;
      _isRunning = false;
      _currentUserId = null;
    }
  }

  /// Get current monitoring status summary
  String getStatusSummary() {
    if (!_isRunning) {
      return 'Geofence monitoring is stopped';
    }

    final uptime = _startTime != null 
        ? DateTime.now().difference(_startTime!) 
        : Duration.zero;
    
    final uptimeStr = uptime.inMinutes > 60
        ? '${uptime.inHours}h ${uptime.inMinutes % 60}m'
        : '${uptime.inMinutes}m';

    return 'Monitoring active for $_currentUserId\n'
           'Uptime: $uptimeStr\n'
           'Positions processed: $_positionsProcessed\n'
           'Last update: ${_lastPositionTime ?? "never"}';
  }
}

/// Extension methods for easier integration
/// 
/// Note: Since provider is now FutureProvider, access via:
/// ```dart
/// final serviceAsync = ref.watch(geofenceBackgroundServiceProvider);
/// serviceAsync.whenData((service) => service.start(...));
/// ```
extension GeofenceBackgroundServiceExtension on WidgetRef {
  /// Quick access to background service future
  Future<GeofenceBackgroundService> get geofenceBackgroundService =>
      read(geofenceBackgroundServiceProvider.future);
}
