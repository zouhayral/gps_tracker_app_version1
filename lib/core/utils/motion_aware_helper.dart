import 'package:flutter/foundation.dart';
import 'package:my_app_gps/core/data/vehicle_data_snapshot.dart';
import 'package:my_app_gps/core/sync/adaptive_sync_manager.dart';

/// Helper class for motion-aware sync interval adjustment
/// 
/// Analyzes vehicle data updates and notifies AdaptiveSyncManager when vehicles
/// transition between moving and idle states to optimize sync frequency.
/// 
/// **Motion Detection Logic:**
/// - Moving: `speed > threshold` (default 2 km/h) OR `ignition == true`
/// - Idle: `speed <= threshold` AND `ignition == false`
/// 
/// **Integration:**
/// Call `analyzeMotion()` when VehicleDataSnapshot is updated in the repository.
/// 
/// **Example:**
/// ```dart
/// // In VehicleDataRepository:
/// void _handleWebSocketUpdate(VehicleDataSnapshot snapshot) {
///   // ... update cache and notifiers ...
///   
///   // Notify motion changes to adaptive sync
///   MotionAwareHelper.analyzeMotion(
///     deviceId: snapshot.deviceId,
///     snapshot: snapshot,
///     syncManager: adaptiveSyncManager,
///   );
/// }
/// ```
class MotionAwareHelper {
  // Configuration
  static const double movingSpeedThreshold = 2.0; // km/h
  static const Duration stateChangeDebounce = Duration(seconds: 5);

  // State tracking
  static final Map<int, bool> _lastKnownMotionState = {}; // deviceId -> isMoving
  static final Map<int, DateTime> _lastStateChange = {}; // deviceId -> timestamp

  /// Analyze vehicle motion and notify sync manager if state changed
  /// 
  /// Returns true if motion state changed (moving ↔ idle)
  static bool analyzeMotion({
    required int deviceId,
    required VehicleDataSnapshot snapshot,
    required AdaptiveSyncManager syncManager,
  }) {
    // Determine current motion state
    final isMoving = _isVehicleMoving(snapshot);

    // Get previous state
    final wasMoving = _lastKnownMotionState[deviceId];

    // Check if state changed
    if (wasMoving == null || wasMoving != isMoving) {
      // Apply debounce to avoid rapid state changes
      final lastChange = _lastStateChange[deviceId];
      if (lastChange != null) {
        final timeSinceChange = DateTime.now().difference(lastChange);
        if (timeSinceChange < stateChangeDebounce) {
          // Too soon, skip update
          return false;
        }
      }

      // Update state
      _lastKnownMotionState[deviceId] = isMoving;
      _lastStateChange[deviceId] = DateTime.now();

      // Notify sync manager
      syncManager.notifyVehicleMotion(
        deviceId: deviceId,
        isMoving: isMoving,
      );

      if (kDebugMode) {
        debugPrint(
          '[MotionAware] Device $deviceId: ${wasMoving == null ? "INITIAL" : (wasMoving ? "MOVING" : "IDLE")} → '
          '${isMoving ? "MOVING" : "IDLE"} (speed: ${snapshot.speed?.toStringAsFixed(1) ?? "N/A"} km/h)',
        );
      }

      return true; // State changed
    }

    return false; // No change
  }

  /// Check if vehicle is currently moving
  /// 
  /// Logic:
  /// 1. If speed > threshold → moving
  /// 2. If ignition == true AND speed > 0 → moving
  /// 3. Otherwise → idle
  static bool _isVehicleMoving(VehicleDataSnapshot snapshot) {
    // Check speed
    final speed = snapshot.speed;
    if (speed != null && speed > movingSpeedThreshold) {
      return true;
    }

    // Check ignition + minimal speed via engine state
    if (snapshot.engineState == EngineState.on && speed != null && speed > 0) {
      return true;
    }

    // Default: idle
    return false;
  }

  /// Get current motion state for a device
  static bool? getMotionState(int deviceId) {
    return _lastKnownMotionState[deviceId];
  }

  /// Get all moving vehicles
  static List<int> getMovingVehicles() {
    return _lastKnownMotionState.entries
        .where((entry) => entry.value == true)
        .map((entry) => entry.key)
        .toList();
  }

  /// Get all idle vehicles
  static List<int> getIdleVehicles() {
    return _lastKnownMotionState.entries
        .where((entry) => entry.value == false)
        .map((entry) => entry.key)
        .toList();
  }

  /// Get statistics about motion states
  static Map<String, dynamic> getStatistics() {
    final moving = getMovingVehicles();
    final idle = getIdleVehicles();

    return {
      'totalTracked': _lastKnownMotionState.length,
      'moving': moving.length,
      'idle': idle.length,
      'movingDevices': moving,
      'idleDevices': idle,
    };
  }

  /// Clear all motion state (useful for testing)
  static void clearState() {
    _lastKnownMotionState.clear();
    _lastStateChange.clear();
  }

  /// Reset motion state for a specific device
  static void resetDevice(int deviceId) {
    _lastKnownMotionState.remove(deviceId);
    _lastStateChange.remove(deviceId);
  }
}

/// Enhanced motion detection with historical analysis
/// 
/// This class can be used for more sophisticated motion detection
/// by analyzing velocity trends, acceleration, and GPS accuracy.
class AdvancedMotionDetector {
  // Track position history for velocity calculation
  static final Map<int, List<_PositionRecord>> _positionHistory = {};
  static const int maxHistorySize = 10;
  static const Duration minTimeDelta = Duration(seconds: 3);

  /// Analyze motion with historical context
  static MotionAnalysis analyzeWithHistory({
    required int deviceId,
    required VehicleDataSnapshot snapshot,
  }) {
    // Get or create position history
    final history = _positionHistory.putIfAbsent(deviceId, () => []);

    // Extract position data from snapshot
    final position = snapshot.position;
    if (position == null) {
      // No position data available
      return MotionAnalysis(
        isMoving: false,
        averageSpeed: 0,
        isAccelerating: false,
        hasConsistentMovement: false,
        confidence: 0,
      );
    }

    // Add current position
    final record = _PositionRecord(
      timestamp: position.deviceTime,
      latitude: position.latitude,
      longitude: position.longitude,
      speed: snapshot.speed ?? 0,
    );

    history.add(record);
    if (history.length > maxHistorySize) {
      history.removeAt(0);
    }

    // Calculate metrics
    final averageSpeed = _calculateAverageSpeed(history);
    final isAccelerating = _isAccelerating(history);
    final hasConsistentMovement = _hasConsistentMovement(history);

    return MotionAnalysis(
      isMoving: averageSpeed > MotionAwareHelper.movingSpeedThreshold,
      averageSpeed: averageSpeed,
      isAccelerating: isAccelerating,
      hasConsistentMovement: hasConsistentMovement,
      confidence: _calculateConfidence(history),
    );
  }

  static double _calculateAverageSpeed(List<_PositionRecord> history) {
    if (history.isEmpty) return 0;
    final sum = history.fold<double>(0, (sum, record) => sum + record.speed);
    return sum / history.length;
  }

  static bool _isAccelerating(List<_PositionRecord> history) {
    if (history.length < 2) return false;
    final recent = history.last.speed;
    final previous = history[history.length - 2].speed;
    return recent > previous;
  }

  static bool _hasConsistentMovement(List<_PositionRecord> history) {
    if (history.length < 3) return false;

    // Check if last 3 readings show movement
    final recentSpeeds = history.skip(history.length - 3).map((r) => r.speed).toList();
    return recentSpeeds.every((speed) => speed > MotionAwareHelper.movingSpeedThreshold);
  }

  static double _calculateConfidence(List<_PositionRecord> history) {
    if (history.length < 3) return 0.5;

    // Higher confidence with more history and consistent readings
    final sizeConfidence = history.length / maxHistorySize;
    final consistencyConfidence = _hasConsistentMovement(history) ? 1.0 : 0.5;

    return (sizeConfidence + consistencyConfidence) / 2;
  }

  /// Clear history for a device
  static void clearHistory(int deviceId) {
    _positionHistory.remove(deviceId);
  }

  /// Clear all history
  static void clearAllHistory() {
    _positionHistory.clear();
  }
}

/// Position record for historical analysis
class _PositionRecord {
  _PositionRecord({
    required this.timestamp,
    required this.latitude,
    required this.longitude,
    required this.speed,
  });

  final DateTime timestamp;
  final double latitude;
  final double longitude;
  final double speed;
}

/// Motion analysis result
class MotionAnalysis {
  MotionAnalysis({
    required this.isMoving,
    required this.averageSpeed,
    required this.isAccelerating,
    required this.hasConsistentMovement,
    required this.confidence,
  });

  final bool isMoving;
  final double averageSpeed;
  final bool isAccelerating;
  final bool hasConsistentMovement;
  final double confidence; // 0.0 - 1.0

  @override
  String toString() {
    return 'MotionAnalysis('
        'isMoving: $isMoving, '
        'avgSpeed: ${averageSpeed.toStringAsFixed(1)} km/h, '
        'accelerating: $isAccelerating, '
        'consistent: $hasConsistentMovement, '
        'confidence: ${(confidence * 100).toStringAsFixed(0)}%'
        ')';
  }
}
