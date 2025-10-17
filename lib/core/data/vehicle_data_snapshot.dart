import 'package:flutter/foundation.dart';
import 'package:my_app_gps/features/map/data/position_model.dart';

/// Complete snapshot of a vehicle's dynamic state at a point in time.
/// Used for caching and reducing redundant API calls.
/// All telemetry fields propagate reactively through the snapshot system.
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
    this.power,
    this.signal,
    this.motion,
    this.hdop,
    this.rssi,
    this.sat,
    this.odometer,
    this.hours,
    this.blocked,
    this.alarm,
  });

  final int deviceId;
  final DateTime timestamp;

  // Position data
  final Position? position;

  // Engine & Motion
  final EngineState? engineState;
  final bool? motion; // Motion sensor state
  final double? speed; // km/h

  // Distance & Usage
  final double? distance; // km (totalDistance or distance attribute)
  final double? odometer; // Total odometer reading in km
  final double? hours; // Engine hours

  // Power & Battery
  final double? batteryLevel; // percentage (0-100)
  final double? power; // External power voltage

  // Connectivity & GPS Quality
  final double? signal; // GSM signal strength (0-100)
  final double? rssi; // Received signal strength indicator (dBm)
  final int? sat; // Number of satellites
  final double? hdop; // Horizontal dilution of precision

  // Fuel & Resources
  final double? fuelLevel; // percentage or liters

  // Status
  final DateTime? lastUpdate;
  final bool? blocked; // Device blocked status
  final String? alarm; // Active alarm type

  /// Create from Position object by extracting all telemetry attributes
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

    // Extract motion sensor
    final motion = attrs['motion'] is bool ? attrs['motion'] as bool : null;

    // Extract distance metrics
    final distanceAttr = attrs['distance'] ?? attrs['totalDistance'];
    final distance =
        distanceAttr is num ? distanceAttr.toDouble() / 1000 : null;

    final odometerAttr = attrs['odometer'];
    final odometer =
        odometerAttr is num ? odometerAttr.toDouble() / 1000 : null;

    final hoursAttr = attrs['hours'] ?? attrs['engineHours'];
    final hours = hoursAttr is num ? hoursAttr.toDouble() : null;

    // Extract battery and power
    final batteryAttr = attrs['batteryLevel'] ?? attrs['battery'];
    final batteryLevel = batteryAttr is num ? batteryAttr.toDouble() : null;

    final powerAttr = attrs['power'] ?? attrs['voltage'];
    final power = powerAttr is num ? powerAttr.toDouble() : null;

    // Extract connectivity metrics
    final signalAttr = attrs['signal'] ?? attrs['gsm'];
    final signal = signalAttr is num ? signalAttr.toDouble() : null;

    final rssiAttr = attrs['rssi'];
    final rssi = rssiAttr is num ? rssiAttr.toDouble() : null;

    final satAttr = attrs['sat'] ?? attrs['satellites'];
    final sat =
        satAttr is int ? satAttr : (satAttr is num ? satAttr.toInt() : null);

    final hdopAttr = attrs['hdop'];
    final hdop = hdopAttr is num ? hdopAttr.toDouble() : null;

    // Extract fuel
    final fuelAttr = attrs['fuel'] ?? attrs['fuelLevel'];
    final fuelLevel = fuelAttr is num ? fuelAttr.toDouble() : null;

    // Extract status
    final blocked = attrs['blocked'] is bool ? attrs['blocked'] as bool : null;
    final alarm = attrs['alarm']?.toString();

    // Debug log for attribute extraction
    if (kDebugMode) {
      debugPrint(
          '[VehicleSnapshot] Creating snapshot for device ${position.deviceId}:',);
      debugPrint(
          '[VehicleSnapshot]   ignition: $ignition → engineState: $engineState',);
      debugPrint(
          '[VehicleSnapshot]   speed: ${position.speed} km/h, motion: $motion',);
      debugPrint(
          '[VehicleSnapshot]   battery: $batteryLevel%, power: $power V',);
      debugPrint(
          '[VehicleSnapshot]   signal: $signal, rssi: $rssi dBm, sat: $sat, hdop: $hdop',);
      debugPrint(
          '[VehicleSnapshot]   all attributes: ${attrs.keys.join(', ')}',);
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
      power: power,
      signal: signal,
      motion: motion,
      hdop: hdop,
      rssi: rssi,
      sat: sat,
      odometer: odometer,
      hours: hours,
      blocked: blocked,
      alarm: alarm,
    );
  }

  /// Merge with newer data, always preferring newer non-null values
  /// All telemetry fields propagate reactively to trigger UI updates
  /// CRITICAL: Always take newer engineState even if it's EngineState.off (not null!)
  VehicleDataSnapshot merge(VehicleDataSnapshot? newer) {
    if (newer == null) return this;
    if (newer.timestamp.isBefore(timestamp)) return this;

    // Detect engine state changes for debugging
    if (kDebugMode &&
        newer.engineState != null &&
        newer.engineState != engineState) {
      debugPrint(
          '[VehicleSnapshot] 🔧 Engine state change detected for device $deviceId: '
          '$engineState → ${newer.engineState}');
    }

    // Detect other critical telemetry changes
    if (kDebugMode) {
      if (newer.batteryLevel != null && newer.batteryLevel != batteryLevel) {
        debugPrint(
            '[VehicleSnapshot] 🔋 Battery change for device $deviceId: $batteryLevel% → ${newer.batteryLevel}%',);
      }
      if (newer.signal != null && newer.signal != signal) {
        debugPrint(
            '[VehicleSnapshot] 📶 Signal change for device $deviceId: $signal → ${newer.signal}',);
      }
    }

    return VehicleDataSnapshot(
      deviceId: deviceId,
      timestamp: newer.timestamp,
      position: newer.position ?? position,
      // Engine & Motion - CRITICAL: Always prefer newer values
      engineState: newer.engineState ?? engineState,
      motion: newer.motion ?? motion,
      speed: newer.speed ?? speed,
      // Distance & Usage
      distance: newer.distance ?? distance,
      odometer: newer.odometer ?? odometer,
      hours: newer.hours ?? hours,
      // Power & Battery
      batteryLevel: newer.batteryLevel ?? batteryLevel,
      power: newer.power ?? power,
      // Connectivity & GPS Quality
      signal: newer.signal ?? signal,
      rssi: newer.rssi ?? rssi,
      sat: newer.sat ?? sat,
      hdop: newer.hdop ?? hdop,
      // Fuel & Resources
      fuelLevel: newer.fuelLevel ?? fuelLevel,
      // Status
      lastUpdate: newer.lastUpdate ?? lastUpdate,
      blocked: newer.blocked ?? blocked,
      alarm: newer.alarm ?? alarm,
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
      'power': power,
      'signal': signal,
      'motion': motion,
      'hdop': hdop,
      'rssi': rssi,
      'sat': sat,
      'odometer': odometer,
      'hours': hours,
      'blocked': blocked,
      'alarm': alarm,
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
      power: (json['power'] as num?)?.toDouble(),
      signal: (json['signal'] as num?)?.toDouble(),
      motion: json['motion'] as bool?,
      hdop: (json['hdop'] as num?)?.toDouble(),
      rssi: (json['rssi'] as num?)?.toDouble(),
      sat: json['sat'] as int?,
      odometer: (json['odometer'] as num?)?.toDouble(),
      hours: (json['hours'] as num?)?.toDouble(),
      blocked: json['blocked'] as bool?,
      alarm: json['alarm'] as String?,
    );
  }

  @override
  String toString() {
    return 'VehicleDataSnapshot(deviceId: $deviceId, timestamp: $timestamp, '
        'engine: $engineState, speed: $speed km/h, distance: $distance km, '
        'battery: $batteryLevel%, power: $power V, signal: $signal, sat: $sat)';
  }
}

enum EngineState {
  on,
  off,
  unknown,
}
