import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:my_app_gps/features/map/data/position_model.dart';

/// Mock device stream generator for performance testing
/// 
/// Simulates 20-50 concurrent devices sending position updates
/// to stress-test the map performance optimizations.
/// 
/// Usage:
/// ```dart
/// final mockStream = MockDeviceStream(deviceCount: 30);
/// mockStream.start();
/// 
/// mockStream.positionStream.listen((positions) {
///   // Process position updates
///   updateService.addBatchUpdates(positions);
/// });
/// 
/// // Later...
/// mockStream.stop();
/// ```
class MockDeviceStream {
  MockDeviceStream({
    this.deviceCount = 20,
    this.updateIntervalMs = 5000,
    this.movementSpeed = 0.0001, // degrees per update (~10m)
    this.enableRandomMovement = true,
  });
  
  final int deviceCount;
  final int updateIntervalMs;
  final double movementSpeed;
  final bool enableRandomMovement;
  
  Timer? _timer;
  final _controller = StreamController<List<Position>>.broadcast();
  final List<_MockDevice> _devices = [];
  final _random = Random();
  int _updateCount = 0;
  
  /// Stream of position updates (batched)
  Stream<List<Position>> get positionStream => _controller.stream;
  
  /// Start generating mock position updates
  void start() {
    if (_timer != null) {
      debugPrint('[MockDeviceStream] Already running');
      return;
    }
    
    // Initialize mock devices with random start positions
    _devices.clear();
    for (int i = 0; i < deviceCount; i++) {
      _devices.add(_MockDevice(
        deviceId: 1000 + i,
        latitude: 48.8566 + (_random.nextDouble() - 0.5) * 0.1, // Paris area
        longitude: 2.3522 + (_random.nextDouble() - 0.5) * 0.1,
        speed: 20.0 + _random.nextDouble() * 40.0, // 20-60 km/h
        course: _random.nextDouble() * 360.0,
      ));
    }
    
    debugPrint('[MockDeviceStream] ✅ Started with $deviceCount devices');
    debugPrint('[MockDeviceStream] Update interval: ${updateIntervalMs}ms');
    debugPrint('[MockDeviceStream] Movement: ${enableRandomMovement ? "ENABLED" : "STATIC"}');
    
    // Start periodic updates
    _timer = Timer.periodic(
      Duration(milliseconds: updateIntervalMs),
      (_) => _generateUpdate(),
    );
    
    // Send initial positions immediately
    _generateUpdate();
  }
  
  /// Stop generating updates
  void stop() {
    _timer?.cancel();
    _timer = null;
    debugPrint('[MockDeviceStream] ⏹️  Stopped after $_updateCount updates');
  }
  
  /// Generate a batch of position updates
  void _generateUpdate() {
    _updateCount++;
    final now = DateTime.now();
    final positions = <Position>[];
    
    for (final device in _devices) {
      // Update position if movement enabled
      if (enableRandomMovement) {
        device.updatePosition(movementSpeed);
      }
      
      // Create position update
      positions.add(Position(
        id: 0, // Will be assigned by ObjectBox if needed
        deviceId: device.deviceId,
        latitude: device.latitude,
        longitude: device.longitude,
        altitude: 100.0 + _random.nextDouble() * 50.0,
        speed: device.speed,
        course: device.course,
        accuracy: 5.0 + _random.nextDouble() * 10.0,
        valid: true,
        deviceTime: now,
        serverTime: now,
        attributes: const {},
        address: null,
      ));
    }
    
    // Emit batch update
    _controller.add(positions);
    
    if (_updateCount % 10 == 0) {
      debugPrint('[MockDeviceStream] Update #$_updateCount: ${positions.length} positions sent');
    }
  }
  
  /// Dispose resources
  void dispose() {
    stop();
    _controller.close();
    debugPrint('[MockDeviceStream] Disposed');
  }
  
  /// Get current update count
  int get updateCount => _updateCount;
  
  /// Get device info for debugging
  List<Map<String, dynamic>> getDeviceInfo() {
    return _devices.map((d) => {
      'deviceId': d.deviceId,
      'latitude': d.latitude.toStringAsFixed(6),
      'longitude': d.longitude.toStringAsFixed(6),
      'speed': d.speed.toStringAsFixed(1),
      'course': d.course.toStringAsFixed(1),
    }).toList();
  }
}

/// Internal mock device representation
class _MockDevice {
  _MockDevice({
    required this.deviceId,
    required this.latitude,
    required this.longitude,
    required this.speed,
    required this.course,
  });
  
  final int deviceId;
  double latitude;
  double longitude;
  double speed;
  double course;
  
  final _random = Random();
  
  /// Update position with random movement
  void updatePosition(double movementSpeed) {
    // Random walk with slight tendency to continue in same direction
    final turnAngle = (_random.nextDouble() - 0.5) * 30.0; // ±15 degrees
    course = (course + turnAngle) % 360.0;
    
    // Move in current direction
    final radians = course * pi / 180.0;
    latitude += cos(radians) * movementSpeed;
    longitude += sin(radians) * movementSpeed;
    
    // Randomly vary speed
    speed += (_random.nextDouble() - 0.5) * 5.0;
    speed = speed.clamp(10.0, 80.0); // Keep realistic 10-80 km/h
    
    // Keep in reasonable bounds (prevent going too far)
    latitude = latitude.clamp(48.75, 48.95);
    longitude = longitude.clamp(2.25, 2.45);
  }
}

/// Pre-configured stress test scenarios
class MockDeviceScenarios {
  /// Light load: 10 devices, 10s intervals
  static MockDeviceStream light() => MockDeviceStream(
    deviceCount: 10,
    updateIntervalMs: 10000,
  );
  
  /// Normal load: 20 devices, 5s intervals (typical Traccar setup)
  static MockDeviceStream normal() => MockDeviceStream(
    deviceCount: 20,
    updateIntervalMs: 5000,
  );
  
  /// Heavy load: 50 devices, 5s intervals
  static MockDeviceStream heavy() => MockDeviceStream(
    deviceCount: 50,
    updateIntervalMs: 5000,
  );
  
  /// Extreme load: 100 devices, 3s intervals
  static MockDeviceStream extreme() => MockDeviceStream(
    deviceCount: 100,
    updateIntervalMs: 3000,
  );
  
  /// Burst load: 30 devices, 1s intervals (stress test)
  static MockDeviceStream burst() => MockDeviceStream(
    deviceCount: 30,
    updateIntervalMs: 1000,
  );
  
  /// Static: 50 devices, no movement (test rendering only)
  static MockDeviceStream staticDevices() => MockDeviceStream(
    deviceCount: 50,
    updateIntervalMs: 5000,
    enableRandomMovement: false,
  );
}
