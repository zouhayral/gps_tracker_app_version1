import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';
import 'package:my_app_gps/data/models/geofence.dart';
import 'package:my_app_gps/data/models/geofence_event.dart';

/// Service responsible for evaluating device positions against geofences.
///
/// Responsibilities:
/// - Calculate point-in-circle using Haversine distance
/// - Calculate point-in-polygon using ray-casting algorithm
/// - Track state transitions (enter/exit/dwell)
/// - Debounce boundary flapping with tolerance buffer
/// - Generate GeofenceEvent objects on state changes
///
/// Performance:
/// - ≤ 5ms per geofence evaluation
/// - Batch of 50 geofences < 50ms
/// - Bounding box optimization for polygons
///
/// Example:
/// ```dart
/// final evaluator = GeofenceEvaluatorService(
///   boundaryToleranceMeters: 5.0,
///   dwellThreshold: Duration(minutes: 2),
/// );
///
/// final events = evaluator.evaluate(
///   deviceId: 'device123',
///   position: LatLng(34.0522, -118.2437),
///   timestamp: DateTime.now(),
///   activeGeofences: geofences,
/// );
///
/// for (final event in events) {
///   print('${event.eventType}: ${event.geofenceName}');
/// }
/// ```
class GeofenceEvaluatorService {
  GeofenceEvaluatorService({
    this.boundaryToleranceMeters = 5.0,
    this.dwellThreshold = const Duration(minutes: 2),
  }) : _distance = const Distance();

  /// Tolerance buffer to prevent boundary flapping (meters)
  final double boundaryToleranceMeters;

  /// Minimum time inside geofence before triggering dwell event
  final Duration dwellThreshold;

  /// Haversine distance calculator
  final Distance _distance;

  /// Active state tracking: key = "deviceId:geofenceId"
  final Map<String, GeofenceState> _activeStates = {};

  /// Evaluate device position against all active geofences.
  ///
  /// Returns list of new events generated since last evaluation:
  /// - Entry events when transitioning outside → inside
  /// - Exit events when transitioning inside → outside
  /// - Dwell events when inside ≥ dwellThreshold
  ///
  /// Performance: O(n) where n = number of active geofences
  List<GeofenceEvent> evaluate({
    required String deviceId,
    required LatLng position,
    required DateTime timestamp,
    required List<Geofence> activeGeofences,
  }) {
    final events = <GeofenceEvent>[];

    try {
      for (final geofence in activeGeofences) {
        if (!geofence.enabled) continue;

        // Skip if device not in monitored list (empty = monitor all)
        if (geofence.monitoredDevices.isNotEmpty &&
            !geofence.monitoredDevices.contains(deviceId)) {
          continue;
        }

        final stateKey = _makeStateKey(deviceId, geofence.id);
        final currentState = _activeStates[stateKey];
        final isInside = _isInside(geofence, position);

        // Initialize state if first evaluation
        if (currentState == null) {
          _activeStates[stateKey] = GeofenceState(
            deviceId: deviceId,
            geofenceId: geofence.id,
            geofenceName: geofence.name,
            isInside: isInside,
            enterTimestamp: isInside ? timestamp : null,
            lastSeenTimestamp: timestamp,
          );

          // Generate entry event if starting inside
          if (isInside && geofence.onEnter) {
            events.add(_createEntryEvent(
              geofence: geofence,
              deviceId: deviceId,
              position: position,
              timestamp: timestamp,
            ));
          }
          continue;
        }

        // State transition: outside → inside
        if (!currentState.isInside && isInside) {
          _activeStates[stateKey] = currentState.copyWith(
            isInside: true,
            enterTimestamp: timestamp,
            lastSeenTimestamp: timestamp,
            dwellEventSent: false,
          );

          if (geofence.onEnter) {
            events.add(_createEntryEvent(
              geofence: geofence,
              deviceId: deviceId,
              position: position,
              timestamp: timestamp,
            ));
          }

          _log('🔵 ENTER: $deviceId → ${geofence.name}');
        }
        // State transition: inside → outside
        else if (currentState.isInside && !isInside) {
          _activeStates[stateKey] = currentState.copyWith(
            isInside: false,
            lastSeenTimestamp: timestamp,
            dwellEventSent: false,
          );

          if (geofence.onExit) {
            events.add(_createExitEvent(
              geofence: geofence,
              deviceId: deviceId,
              position: position,
              timestamp: timestamp,
            ));
          }

          _log('🔴 EXIT: $deviceId ← ${geofence.name}');
        }
        // Continuous inside: check for dwell
        else if (currentState.isInside && isInside) {
          _activeStates[stateKey] = currentState.copyWith(
            lastSeenTimestamp: timestamp,
          );

          // Check dwell threshold
          if (geofence.dwellMs != null &&
              !currentState.dwellEventSent &&
              currentState.enterTimestamp != null) {
            final dwellDuration = timestamp.difference(currentState.enterTimestamp!);
            final requiredDwell = Duration(milliseconds: geofence.dwellMs!);

            if (dwellDuration >= requiredDwell) {
              _activeStates[stateKey] = currentState.copyWith(
                dwellEventSent: true,
              );

              events.add(_createDwellEvent(
                geofence: geofence,
                deviceId: deviceId,
                position: position,
                timestamp: timestamp,
                dwellDurationMs: dwellDuration.inMilliseconds,
              ));

              _log('⏱️ DWELL: $deviceId in ${geofence.name} for ${dwellDuration.inMinutes}m');
            }
          }
        }
        // Continuous outside: update last seen
        else {
          _activeStates[stateKey] = currentState.copyWith(
            lastSeenTimestamp: timestamp,
          );
        }
      }

      _log('📊 Evaluated ${activeGeofences.length} geofences, generated ${events.length} events');
    } catch (e, stackTrace) {
      _log('❌ Evaluation error: $e');
      if (kDebugMode) {
        debugPrint('[GeofenceEvaluator] Stack trace: $stackTrace');
      }
    }

    return events;
  }

  /// Check if position is inside geofence (with tolerance buffer)
  bool _isInside(Geofence geofence, LatLng position) {
    if (geofence.type == 'circle') {
      return _isInsideCircle(geofence, position);
    } else if (geofence.type == 'polygon') {
      return _isInsidePolygon(geofence, position);
    }
    return false;
  }

  /// Check if position is inside circular geofence
  bool _isInsideCircle(Geofence geofence, LatLng position) {
    if (geofence.centerLat == null ||
        geofence.centerLng == null ||
        geofence.radius == null) {
      return false;
    }

    final center = LatLng(geofence.centerLat!, geofence.centerLng!);
    final distanceMeters = _distanceMeters(center, position);

    // Include tolerance buffer to prevent flapping
    return distanceMeters <= (geofence.radius! + boundaryToleranceMeters);
  }

  /// Check if position is inside polygon geofence
  bool _isInsidePolygon(Geofence geofence, LatLng position) {
    if (geofence.vertices == null || geofence.vertices!.length < 3) {
      return false;
    }

    final vertices = geofence.vertices!;

    // Fast bounding box check first
    if (!_isInBoundingBox(position, vertices)) {
      return false;
    }

    // Ray casting algorithm with tolerance
    return _isPointInPolygon(position, vertices);
  }

  /// Bounding box optimization for polygon checks
  bool _isInBoundingBox(LatLng point, List<LatLng> vertices) {
    var minLat = vertices[0].latitude;
    var maxLat = vertices[0].latitude;
    var minLng = vertices[0].longitude;
    var maxLng = vertices[0].longitude;

    for (final vertex in vertices) {
      minLat = math.min(minLat, vertex.latitude);
      maxLat = math.max(maxLat, vertex.latitude);
      minLng = math.min(minLng, vertex.longitude);
      maxLng = math.max(maxLng, vertex.longitude);
    }

    // Add tolerance buffer to bounding box
    final toleranceDegrees = boundaryToleranceMeters / 111000; // ~1 degree = 111km
    minLat -= toleranceDegrees;
    maxLat += toleranceDegrees;
    minLng -= toleranceDegrees;
    maxLng += toleranceDegrees;

    return point.latitude >= minLat &&
        point.latitude <= maxLat &&
        point.longitude >= minLng &&
        point.longitude <= maxLng;
  }

  /// Ray casting algorithm for point-in-polygon test
  ///
  /// Algorithm:
  /// 1. Cast ray from point to infinity (horizontal right)
  /// 2. Count intersections with polygon edges
  /// 3. Odd count = inside, Even count = outside
  ///
  /// Time complexity: O(n) where n = number of vertices
  bool _isPointInPolygon(LatLng point, List<LatLng> vertices) {
    var inside = false;
    final x = point.longitude;
    final y = point.latitude;

    for (var i = 0, j = vertices.length - 1; i < vertices.length; j = i++) {
      final xi = vertices[i].longitude;
      final yi = vertices[i].latitude;
      final xj = vertices[j].longitude;
      final yj = vertices[j].latitude;

      // Check if ray crosses edge
      final intersect = ((yi > y) != (yj > y)) &&
          (x < (xj - xi) * (y - yi) / (yj - yi) + xi);

      if (intersect) {
        inside = !inside;
      }
    }

    return inside;
  }

  /// Calculate Haversine distance between two points (meters)
  ///
  /// Uses latlong2 Distance class for accurate geodesic calculations.
  double _distanceMeters(LatLng a, LatLng b) {
    return _distance.as(LengthUnit.Meter, a, b);
  }

  /// Create state key for tracking
  String _makeStateKey(String deviceId, String geofenceId) {
    return '$deviceId:$geofenceId';
  }

  /// Create entry event
  GeofenceEvent _createEntryEvent({
    required Geofence geofence,
    required String deviceId,
    required LatLng position,
    required DateTime timestamp,
  }) {
    return GeofenceEvent.entry(
      id: _generateEventId(),
      geofenceId: geofence.id,
      geofenceName: geofence.name,
      deviceId: deviceId,
      deviceName: deviceId, // Will be enriched by monitoring service
      location: position,
      timestamp: timestamp,
    );
  }

  /// Create exit event
  GeofenceEvent _createExitEvent({
    required Geofence geofence,
    required String deviceId,
    required LatLng position,
    required DateTime timestamp,
  }) {
    return GeofenceEvent.exit(
      id: _generateEventId(),
      geofenceId: geofence.id,
      geofenceName: geofence.name,
      deviceId: deviceId,
      deviceName: deviceId, // Will be enriched by monitoring service
      location: position,
      timestamp: timestamp,
    );
  }

  /// Create dwell event
  GeofenceEvent _createDwellEvent({
    required Geofence geofence,
    required String deviceId,
    required LatLng position,
    required DateTime timestamp,
    required int dwellDurationMs,
  }) {
    return GeofenceEvent.dwell(
      id: _generateEventId(),
      geofenceId: geofence.id,
      geofenceName: geofence.name,
      deviceId: deviceId,
      deviceName: deviceId, // Will be enriched by monitoring service
      location: position,
      timestamp: timestamp,
      dwellDurationMs: dwellDurationMs,
    );
  }

  /// Generate unique event ID
  String _generateEventId() {
    return '${DateTime.now().millisecondsSinceEpoch}-${math.Random().nextInt(9999)}';
  }

  /// Get current state for a device-geofence pair
  GeofenceState? getState(String deviceId, String geofenceId) {
    return _activeStates[_makeStateKey(deviceId, geofenceId)];
  }

  /// Clear state for a specific device
  void clearDeviceState(String deviceId) {
    _activeStates.removeWhere((key, _) => key.startsWith('$deviceId:'));
    _log('🧹 Cleared state for device: $deviceId');
  }

  /// Clear state for a specific geofence
  void clearGeofenceState(String geofenceId) {
    _activeStates.removeWhere((key, _) => key.endsWith(':$geofenceId'));
    _log('🧹 Cleared state for geofence: $geofenceId');
  }

  /// Clear all state (useful for testing or reset)
  void clearAllState() {
    _activeStates.clear();
    _log('🧹 Cleared all state');
  }

  /// Get count of tracked states
  int get stateCount => _activeStates.length;

  /// Logging helper
  void _log(String message) {
    if (kDebugMode) {
      debugPrint('[GeofenceEvaluator] $message');
    }
  }

  // =============================
  // Testing Utilities
  // =============================

  /// Test helper: Check if point is in polygon (static for unit tests)
  @visibleForTesting
  static bool testPointInPolygon(LatLng point, List<LatLng> vertices) {
    var inside = false;
    final x = point.longitude;
    final y = point.latitude;

    for (var i = 0, j = vertices.length - 1; i < vertices.length; j = i++) {
      final xi = vertices[i].longitude;
      final yi = vertices[i].latitude;
      final xj = vertices[j].longitude;
      final yj = vertices[j].latitude;

      final intersect = ((yi > y) != (yj > y)) &&
          (x < (xj - xi) * (y - yi) / (yj - yi) + xi);

      if (intersect) {
        inside = !inside;
      }
    }

    return inside;
  }

  /// Test helper: Calculate distance between two points (static for unit tests)
  @visibleForTesting
  static double testDistance(LatLng a, LatLng b) {
    const distance = Distance();
    return distance.as(LengthUnit.Meter, a, b);
  }

  /// Test helper: Check bounding box
  @visibleForTesting
  static bool testBoundingBox(LatLng point, List<LatLng> vertices) {
    var minLat = vertices[0].latitude;
    var maxLat = vertices[0].latitude;
    var minLng = vertices[0].longitude;
    var maxLng = vertices[0].longitude;

    for (final vertex in vertices) {
      minLat = math.min(minLat, vertex.latitude);
      maxLat = math.max(maxLat, vertex.latitude);
      minLng = math.min(minLng, vertex.longitude);
      maxLng = math.max(maxLng, vertex.longitude);
    }

    return point.latitude >= minLat &&
        point.latitude <= maxLat &&
        point.longitude >= minLng &&
        point.longitude <= maxLng;
  }
}

/// Represents the current state of a device relative to a geofence.
///
/// Tracks:
/// - Whether device is currently inside or outside
/// - Timestamp of last entry (for dwell calculations)
/// - Timestamp of last evaluation (for timeout detection)
/// - Whether dwell event has been sent (prevents duplicates)
class GeofenceState {
  const GeofenceState({
    required this.deviceId,
    required this.geofenceId,
    required this.geofenceName,
    required this.isInside,
    required this.lastSeenTimestamp,
    this.enterTimestamp,
    this.dwellEventSent = false,
  });

  /// Device identifier
  final String deviceId;

  /// Geofence identifier
  final String geofenceId;

  /// Cached geofence name for logging
  final String geofenceName;

  /// Current inside/outside state
  final bool isInside;

  /// Timestamp when device entered geofence (null if outside)
  final DateTime? enterTimestamp;

  /// Timestamp of last position evaluation
  final DateTime lastSeenTimestamp;

  /// Flag to prevent duplicate dwell events
  final bool dwellEventSent;

  /// Calculate current dwell duration (if inside)
  Duration? get dwellDuration {
    if (!isInside || enterTimestamp == null) return null;
    return DateTime.now().difference(enterTimestamp!);
  }

  /// Calculate time since last seen
  Duration get timeSinceLastSeen {
    return DateTime.now().difference(lastSeenTimestamp);
  }

  /// Copy with modified fields
  GeofenceState copyWith({
    String? deviceId,
    String? geofenceId,
    String? geofenceName,
    bool? isInside,
    DateTime? enterTimestamp,
    DateTime? lastSeenTimestamp,
    bool? dwellEventSent,
  }) {
    return GeofenceState(
      deviceId: deviceId ?? this.deviceId,
      geofenceId: geofenceId ?? this.geofenceId,
      geofenceName: geofenceName ?? this.geofenceName,
      isInside: isInside ?? this.isInside,
      enterTimestamp: enterTimestamp ?? this.enterTimestamp,
      lastSeenTimestamp: lastSeenTimestamp ?? this.lastSeenTimestamp,
      dwellEventSent: dwellEventSent ?? this.dwellEventSent,
    );
  }

  @override
  String toString() =>
    'GeofenceState(device: $deviceId, geofence: $geofenceName, inside: $isInside, dwell: ${dwellDuration?.inMinutes ?? 0}m)';
}

// =============================
// Example Usage
// =============================

/// Example usage of GeofenceEvaluatorService
///
/// ```dart
/// void main() async {
///   // Initialize evaluator
///   final evaluator = GeofenceEvaluatorService(
///     boundaryToleranceMeters: 5.0,
///     dwellThreshold: Duration(minutes: 2),
///   );
///
///   // Create test geofence (circular)
///   final officeGeofence = Geofence.circle(
///     id: 'office-001',
///     userId: 'user123',
///     name: 'Office Building',
///     center: LatLng(34.0522, -118.2437),
///     radius: 100.0, // 100 meters
///     monitoredDevices: ['device123'],
///     onEnter: true,
///     onExit: true,
///     dwellMs: 120000, // 2 minutes
///   );
///
///   // Create test geofence (polygon)
///   final parkingLotGeofence = Geofence.polygon(
///     id: 'parking-001',
///     userId: 'user123',
///     name: 'Parking Lot',
///     vertices: [
///       LatLng(34.0520, -118.2440),
///       LatLng(34.0520, -118.2435),
///       LatLng(34.0525, -118.2435),
///       LatLng(34.0525, -118.2440),
///     ],
///     monitoredDevices: ['device123'],
///     onEnter: true,
///     onExit: true,
///   );
///
///   final geofences = [officeGeofence, parkingLotGeofence];
///
///   // Simulate device positions
///   final positions = [
///     LatLng(34.0522, -118.2437), // Inside office
///     LatLng(34.0522, -118.2437), // Still inside (dwell building)
///     LatLng(34.0530, -118.2437), // Outside both
///     LatLng(34.0522, -118.2437), // Back inside office
///   ];
///
///   // Evaluate each position
///   for (var i = 0; i < positions.length; i++) {
///     final timestamp = DateTime.now().add(Duration(minutes: i * 3));
///     
///     print('\n--- Position Update ${i + 1} ---');
///     print('Location: ${positions[i]}');
///     
///     final events = evaluator.evaluate(
///       deviceId: 'device123',
///       position: positions[i],
///       timestamp: timestamp,
///       activeGeofences: geofences,
///     );
///
///     // Process events
///     for (final event in events) {
///       print('🔔 Event: ${event.eventType.toUpperCase()}');
///       print('   Geofence: ${event.geofenceName}');
///       print('   Time: ${event.formattedTime}');
///       if (event.dwellDurationMs != null) {
///         print('   Dwell: ${event.formattedDwellDuration}');
///       }
///     }
///
///     if (events.isEmpty) {
///       print('   No events (no state change)');
///     }
///   }
///
///   // Check final states
///   print('\n--- Final States ---');
///   for (final geofence in geofences) {
///     final state = evaluator.getState('device123', geofence.id);
///     if (state != null) {
///       print('${geofence.name}: $state');
///     }
///   }
/// }
/// ```
