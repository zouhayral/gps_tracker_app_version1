import 'package:flutter/foundation.dart';

/// Represents the current state of the geofence optimizer
@immutable
class GeofenceOptimizerState {
  /// Whether the optimizer is currently active
  final bool isActive;
  
  /// Whether the device is currently stationary
  final bool isStationary;
  
  /// Whether the battery is low (< 20% and not charging)
  final bool isLowBattery;
  
  /// Current battery level (0-100)
  final int batteryLevel;
  
  /// Whether the device is charging
  final bool isCharging;
  
  /// Current evaluation interval in seconds
  final int currentIntervalSeconds;
  
  /// Active mode interval in seconds
  final int activeModeInterval;
  
  /// Idle mode interval in seconds (when stationary or low battery)
  final int idleModeInterval;
  
  /// Last motion magnitude detected
  final double lastMotionMagnitude;
  
  /// Timestamp of last motion detection
  final DateTime? lastMotionTimestamp;
  
  /// Timestamp of last battery check
  final DateTime? lastBatteryCheckTimestamp;
  
  /// Number of battery saves performed
  final int batterySaveCount;
  
  /// Number of idle throttles performed
  final int idleThrottleCount;
  
  /// Total evaluation count
  final int totalEvaluations;

  const GeofenceOptimizerState({
    this.isActive = false,
    this.isStationary = false,
    this.isLowBattery = false,
    this.batteryLevel = 100,
    this.isCharging = false,
    this.currentIntervalSeconds = 30,
    this.activeModeInterval = 30,
    this.idleModeInterval = 180,
    this.lastMotionMagnitude = 0.0,
    this.lastMotionTimestamp,
    this.lastBatteryCheckTimestamp,
    this.batterySaveCount = 0,
    this.idleThrottleCount = 0,
    this.totalEvaluations = 0,
  });

  GeofenceOptimizerState copyWith({
    bool? isActive,
    bool? isStationary,
    bool? isLowBattery,
    int? batteryLevel,
    bool? isCharging,
    int? currentIntervalSeconds,
    int? activeModeInterval,
    int? idleModeInterval,
    double? lastMotionMagnitude,
    DateTime? lastMotionTimestamp,
    DateTime? lastBatteryCheckTimestamp,
    int? batterySaveCount,
    int? idleThrottleCount,
    int? totalEvaluations,
  }) {
    return GeofenceOptimizerState(
      isActive: isActive ?? this.isActive,
      isStationary: isStationary ?? this.isStationary,
      isLowBattery: isLowBattery ?? this.isLowBattery,
      batteryLevel: batteryLevel ?? this.batteryLevel,
      isCharging: isCharging ?? this.isCharging,
      currentIntervalSeconds: currentIntervalSeconds ?? this.currentIntervalSeconds,
      activeModeInterval: activeModeInterval ?? this.activeModeInterval,
      idleModeInterval: idleModeInterval ?? this.idleModeInterval,
      lastMotionMagnitude: lastMotionMagnitude ?? this.lastMotionMagnitude,
      lastMotionTimestamp: lastMotionTimestamp ?? this.lastMotionTimestamp,
      lastBatteryCheckTimestamp: lastBatteryCheckTimestamp ?? this.lastBatteryCheckTimestamp,
      batterySaveCount: batterySaveCount ?? this.batterySaveCount,
      idleThrottleCount: idleThrottleCount ?? this.idleThrottleCount,
      totalEvaluations: totalEvaluations ?? this.totalEvaluations,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is GeofenceOptimizerState &&
        other.isActive == isActive &&
        other.isStationary == isStationary &&
        other.isLowBattery == isLowBattery &&
        other.batteryLevel == batteryLevel &&
        other.isCharging == isCharging &&
        other.currentIntervalSeconds == currentIntervalSeconds &&
        other.activeModeInterval == activeModeInterval &&
        other.idleModeInterval == idleModeInterval &&
        other.lastMotionMagnitude == lastMotionMagnitude &&
        other.lastMotionTimestamp == lastMotionTimestamp &&
        other.lastBatteryCheckTimestamp == lastBatteryCheckTimestamp &&
        other.batterySaveCount == batterySaveCount &&
        other.idleThrottleCount == idleThrottleCount &&
        other.totalEvaluations == totalEvaluations;
  }

  @override
  int get hashCode {
    return Object.hash(
      isActive,
      isStationary,
      isLowBattery,
      batteryLevel,
      isCharging,
      currentIntervalSeconds,
      activeModeInterval,
      idleModeInterval,
      lastMotionMagnitude,
      lastMotionTimestamp,
      lastBatteryCheckTimestamp,
      batterySaveCount,
      idleThrottleCount,
      totalEvaluations,
    );
  }

  @override
  String toString() {
    return 'GeofenceOptimizerState(isActive: $isActive, isStationary: $isStationary, '
        'isLowBattery: $isLowBattery, batteryLevel: $batteryLevel, '
        'isCharging: $isCharging, currentIntervalSeconds: $currentIntervalSeconds, '
        'activeModeInterval: $activeModeInterval, idleModeInterval: $idleModeInterval, '
        'lastMotionMagnitude: $lastMotionMagnitude, lastMotionTimestamp: $lastMotionTimestamp, '
        'lastBatteryCheckTimestamp: $lastBatteryCheckTimestamp, batterySaveCount: $batterySaveCount, '
        'idleThrottleCount: $idleThrottleCount, totalEvaluations: $totalEvaluations)';
  }
}

extension GeofenceOptimizerStateX on GeofenceOptimizerState {
  /// Whether the optimizer is currently throttling (idle or battery save mode)
  bool get isThrottling => isStationary || isLowBattery;
  
  /// Current optimization mode
  OptimizationMode get mode {
    if (!isActive) return OptimizationMode.disabled;
    if (isLowBattery) return OptimizationMode.batterySaver;
    if (isStationary) return OptimizationMode.idle;
    return OptimizationMode.active;
  }
  
  /// User-friendly description of current state
  String get description {
    switch (mode) {
      case OptimizationMode.disabled:
        return 'Optimization disabled';
      case OptimizationMode.active:
        return 'Active mode ($currentIntervalSeconds s interval)';
      case OptimizationMode.idle:
        return 'Idle mode ($currentIntervalSeconds s interval)';
      case OptimizationMode.batterySaver:
        return 'Battery saver ($currentIntervalSeconds s interval)';
    }
  }
  
  /// Battery status description
  String get batteryStatus {
    if (isCharging) {
      return 'Charging ($batteryLevel%)';
    } else if (isLowBattery) {
      return 'Low battery ($batteryLevel%)';
    } else {
      return 'Battery: $batteryLevel%';
    }
  }
  
  /// Motion status description
  String get motionStatus {
    if (isStationary) {
      final timeSinceMotion = lastMotionTimestamp != null
          ? DateTime.now().difference(lastMotionTimestamp!)
          : null;
      
      if (timeSinceMotion != null) {
        final minutes = timeSinceMotion.inMinutes;
        return 'Stationary ($minutes min)';
      }
      return 'Stationary';
    } else {
      return 'Moving';
    }
  }
  
  /// Calculate battery savings percentage
  double get batterySavingsPercent {
    if (totalEvaluations == 0) return 0;
    final throttledCount = batterySaveCount + idleThrottleCount;
    return (throttledCount / totalEvaluations) * 100.0;
  }
  
  /// Diagnostics map for logging and debugging
  Map<String, dynamic> get diagnostics => {
        'mode': mode.name,
        'isActive': isActive,
        'isStationary': isStationary,
        'isLowBattery': isLowBattery,
        'batteryLevel': batteryLevel,
        'isCharging': isCharging,
        'currentInterval': currentIntervalSeconds,
        'motionMagnitude': lastMotionMagnitude.toStringAsFixed(3),
        'batterySaves': batterySaveCount,
        'idleThrottles': idleThrottleCount,
        'totalEvaluations': totalEvaluations,
        'savingsPercent': batterySavingsPercent.toStringAsFixed(1),
      };
}

/// Optimization modes
enum OptimizationMode {
  /// Optimization disabled
  disabled,
  
  /// Active mode - normal evaluation frequency
  active,
  
  /// Idle mode - device stationary, reduced frequency
  idle,
  
  /// Battery saver mode - low battery, reduced frequency
  batterySaver,
}
