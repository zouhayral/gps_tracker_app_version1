import 'package:flutter/foundation.dart';
import 'package:my_app_gps/features/map/data/position_model.dart';

/// Complete snapshot of a vehicle's dynamic state at a point in time.
/// Used for caching and reducing redundant API calls.
class VehicleDataSnapshot {
  const VehicleDataSnapshot({
    required this.deviceId,
    required this.timestamp,
    this.position,
    this.engineState,
    this.speed,
    this.distance,
    this.lastUpdate,
    this.batteryLevel,
    this.fuelLevel,
  });

  final int deviceId;
  final DateTime timestamp;
  
  // Position data
  final Position? position;
  
  // Extracted metrics
  final EngineState? engineState;
  final double? speed; // km/h
  final double? distance; // km (totalDistance or distance attribute)
  final DateTime? lastUpdate;
  final double? batteryLevel; // percentage
  final double? fuelLevel; // percentage or liters
  
  /// Create from Position object by extracting common attributes
  factory VehicleDataSnapshot.fromPosition(Position position) {
    final attrs = position.attributes;
    
    // Extract engine state
    EngineState? engineState;
    final ignition = attrs['ignition'];
    if (ignition is bool) {
      engineState = ignition ? EngineState.on : EngineState.off;
    } else if (attrs['motion'] is bool && attrs['motion'] == true) {
      engineState = EngineState.on;
    }
    
    // Extract distance (km)
    final distanceAttr = attrs['distance'] ?? attrs['totalDistance'];
    final distance = distanceAttr is num ? distanceAttr.toDouble() / 1000 : null;
    
    // Extract battery
    final batteryAttr = attrs['batteryLevel'] ?? attrs['battery'];
    final batteryLevel = batteryAttr is num ? batteryAttr.toDouble() : null;
    
    // Extract fuel
    final fuelAttr = attrs['fuel'] ?? attrs['fuelLevel'];
    final fuelLevel = fuelAttr is num ? fuelAttr.toDouble() : null;
    
    // Debug log for attribute extraction
    if (kDebugMode) {
      debugPrint('[VehicleSnapshot] Creating snapshot for device ${position.deviceId}:');
      debugPrint('[VehicleSnapshot]   ignition attr: $ignition (type: ${ignition.runtimeType})');
      debugPrint('[VehicleSnapshot]   extracted engineState: $engineState');
      debugPrint('[VehicleSnapshot]   speed: ${position.speed} km/h');
      debugPrint('[VehicleSnapshot]   all attributes: ${attrs.keys.join(', ')}');
    }
    
    return VehicleDataSnapshot(
      deviceId: position.deviceId,
      timestamp: position.serverTime,
      position: position,
      engineState: engineState,
      speed: position.speed,
      distance: distance,
      lastUpdate: position.deviceTime,
      batteryLevel: batteryLevel,
      fuelLevel: fuelLevel,
    );
  }
  
  /// Merge with newer data, always preferring newer non-null values
  /// CRITICAL: Always take newer engineState even if it's EngineState.off (not null!)
  VehicleDataSnapshot merge(VehicleDataSnapshot? newer) {
    if (newer == null) return this;
    if (newer.timestamp.isBefore(timestamp)) return this;
    
    // Detect engine state changes for debugging
    if (kDebugMode && newer.engineState != null && newer.engineState != engineState) {
      debugPrint('[VehicleSnapshot] 🔧 Engine state change detected for device $deviceId: '
          '$engineState → ${newer.engineState}');
    }
    
    return VehicleDataSnapshot(
      deviceId: deviceId,
      timestamp: newer.timestamp,
      position: newer.position ?? position,
      // CRITICAL FIX: Always take newer engineState if present (even EngineState.off)
      // The ?? operator only checks for null, so EngineState.off IS used correctly
      // But we add explicit logging to verify updates are received
      engineState: newer.engineState ?? engineState,
      speed: newer.speed ?? speed,
      distance: newer.distance ?? distance,
      lastUpdate: newer.lastUpdate ?? lastUpdate,
      batteryLevel: newer.batteryLevel ?? batteryLevel,
      fuelLevel: newer.fuelLevel ?? fuelLevel,
    );
  }
  
  /// Check if snapshot is stale (older than given duration)
  bool isStale(Duration maxAge) {
    return DateTime.now().difference(timestamp) > maxAge;
  }
  
  /// Convert to JSON for persistence
  Map<String, dynamic> toJson() {
    return {
      'deviceId': deviceId,
      'timestamp': timestamp.toIso8601String(),
      'position': position?.toJson(),
      'engineState': engineState?.name,
      'speed': speed,
      'distance': distance,
      'lastUpdate': lastUpdate?.toIso8601String(),
      'batteryLevel': batteryLevel,
      'fuelLevel': fuelLevel,
    };
  }
  
  /// Create from JSON
  factory VehicleDataSnapshot.fromJson(Map<String, dynamic> json) {
    return VehicleDataSnapshot(
      deviceId: json['deviceId'] as int,
      timestamp: DateTime.parse(json['timestamp'] as String),
      position: json['position'] != null 
          ? Position.fromJson(json['position'] as Map<String, dynamic>)
          : null,
      engineState: json['engineState'] != null
          ? EngineState.values.firstWhere((e) => e.name == json['engineState'])
          : null,
      speed: (json['speed'] as num?)?.toDouble(),
      distance: (json['distance'] as num?)?.toDouble(),
      lastUpdate: json['lastUpdate'] != null
          ? DateTime.parse(json['lastUpdate'] as String)
          : null,
      batteryLevel: (json['batteryLevel'] as num?)?.toDouble(),
      fuelLevel: (json['fuelLevel'] as num?)?.toDouble(),
    );
  }
  
  @override
  String toString() {
    return 'VehicleDataSnapshot(deviceId: $deviceId, timestamp: $timestamp, '
        'engine: $engineState, speed: $speed km/h, distance: $distance km)';
  }
}

enum EngineState {
  on,
  off,
  unknown,
}
