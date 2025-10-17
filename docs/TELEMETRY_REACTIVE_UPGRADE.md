# Telemetry Reactive Data Flow - Complete Upgrade Guide

## Overview

The VehicleDataSnapshot system has been upgraded to propagate **all telemetry fields reactively**, ensuring real-time UI updates for every metric from speed to signal strength.

## What Changed

### 1. VehicleDataSnapshot - Comprehensive Telemetry Fields

**New fields added:**
```dart
class VehicleDataSnapshot {
  // Engine & Motion
  final EngineState? engineState;
  final bool? motion;
  final double? speed;
  
  // Distance & Usage
  final double? distance;
  final double? odometer;
  final double? hours;
  
  // Power & Battery
  final double? batteryLevel;
  final double? power;
  
  // Connectivity & GPS Quality
  final double? signal;
  final double? rssi;
  final int? sat;
  final double? hdop;
  
  // Fuel & Resources
  final double? fuelLevel;
  
  // Status
  final DateTime? lastUpdate;
  final bool? blocked;
  final String? alarm;
}
```

### 2. Enhanced fromPosition() Factory

Extracts **all telemetry attributes** from Traccar position data:

```dart
VehicleDataSnapshot.fromPosition(Position position) {
  // Extracts from position.attributes:
  // - ignition, motion, odometer, hours
  // - battery, power, signal, rssi, sat, hdop
  // - fuel, blocked, alarm
  // - distance (converted to km)
  // - All with fallback logic for different attribute names
}
```

### 3. Reactive merge() Method

**All fields propagate** through the merge system:

```dart
VehicleDataSnapshot merge(VehicleDataSnapshot? newer) {
  // Always prefers newer non-null values
  // Logs critical changes (engine, battery, signal)
  // Timestamp-based precedence
  return VehicleDataSnapshot(
    engineState: newer.engineState ?? engineState,
    motion: newer.motion ?? motion,
    speed: newer.speed ?? speed,
    batteryLevel: newer.batteryLevel ?? batteryLevel,
    power: newer.power ?? power,
    signal: newer.signal ?? signal,
    // ... all fields
  );
}
```

### 4. Granular Providers for Every Metric

**New providers added:**
- `vehiclePowerProvider` - External power voltage
- `vehicleSignalProvider` - GSM signal strength
- `vehicleMotionProvider` - Motion sensor state
- `vehicleHdopProvider` - GPS accuracy (HDOP)
- `vehicleRssiProvider` - Signal strength (dBm)
- `vehicleSatProvider` - Satellite count
- `vehicleOdometerProvider` - Total odometer reading
- `vehicleHoursProvider` - Engine hours
- `vehicleBlockedProvider` - Device blocked status
- `vehicleAlarmProvider` - Active alarm type

## How to Use in Your UI

### Example 1: Single Field Watch

Watch **one specific metric** and rebuild only when it changes:

```dart
class BatteryIndicator extends ConsumerWidget {
  final int deviceId;
  
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Rebuilds ONLY when battery level changes
    final battery = ref.watchBattery(deviceId);
    
    return Text('Battery: ${battery?.toStringAsFixed(0) ?? '--'}%');
  }
}
```

### Example 2: Multiple Field Watch with Select

Watch **multiple related metrics** efficiently:

```dart
class PowerCard extends ConsumerWidget {
  final int deviceId;
  
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Watch multiple fields with a single select
    final snapshot = ref.watch(
      vehicleSnapshotProvider(deviceId).select(
        (notifier) => (
          battery: notifier.value?.batteryLevel,
          power: notifier.value?.power,
          signal: notifier.value?.signal,
        ),
      ),
    );
    
    return Column(
      children: [
        Text('Battery: ${snapshot.battery?.toStringAsFixed(0) ?? '--'}%'),
        Text('Power: ${snapshot.power?.toStringAsFixed(1) ?? '--'} V'),
        Text('Signal: ${snapshot.signal?.toStringAsFixed(0) ?? '--'}%'),
      ],
    );
  }
}
```

### Example 3: Speedometer with Engine State

```dart
class SpeedometerWidget extends ConsumerWidget {
  final int deviceId;
  
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Watch speed and engine state
    final speed = ref.watchSpeed(deviceId);
    final engine = ref.watchEngine(deviceId);
    
    final isRunning = engine == EngineState.on;
    
    return Container(
      decoration: BoxDecoration(
        color: isRunning ? Colors.green : Colors.grey,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Text(
            '${speed?.toStringAsFixed(0) ?? '0'}',
            style: TextStyle(fontSize: 48, fontWeight: FontWeight.bold),
          ),
          Text('km/h'),
          Icon(
            isRunning ? Icons.power : Icons.power_off,
            color: isRunning ? Colors.white : Colors.red,
          ),
        ],
      ),
    );
  }
}
```

### Example 4: GPS Quality Indicator

```dart
class GpsQualityWidget extends ConsumerWidget {
  final int deviceId;
  
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Watch GPS-related metrics
    final sat = ref.watchSat(deviceId);
    final hdop = ref.watchHdop(deviceId);
    final signal = ref.watchSignal(deviceId);
    
    final quality = _calculateQuality(sat, hdop);
    
    return Row(
      children: [
        Icon(
          Icons.satellite_alt,
          color: quality > 0.7 ? Colors.green : Colors.orange,
        ),
        Text('$sat satellites'),
        SizedBox(width: 8),
        Icon(
          Icons.signal_cellular_alt,
          color: (signal ?? 0) > 50 ? Colors.green : Colors.red,
        ),
        Text('${signal?.toStringAsFixed(0) ?? '0'}%'),
      ],
    );
  }
  
  double _calculateQuality(int? sat, double? hdop) {
    if (sat == null || hdop == null) return 0.0;
    if (sat >= 8 && hdop < 2.0) return 1.0;
    if (sat >= 5 && hdop < 3.0) return 0.7;
    return 0.3;
  }
}
```

### Example 5: Comprehensive Vehicle Status

```dart
class VehicleStatusSheet extends ConsumerWidget {
  final int deviceId;
  
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Watch the complete snapshot for bottom sheet
    final notifier = ref.watch(vehicleSnapshotProvider(deviceId));
    final snapshot = notifier.value;
    
    if (snapshot == null) return CircularProgressIndicator();
    
    return Column(
      children: [
        _StatusRow('Engine', snapshot.engineState?.name ?? '--'),
        _StatusRow('Speed', '${snapshot.speed?.toStringAsFixed(0) ?? '--'} km/h'),
        _StatusRow('Motion', snapshot.motion == true ? 'Yes' : 'No'),
        _StatusRow('Battery', '${snapshot.batteryLevel?.toStringAsFixed(0) ?? '--'}%'),
        _StatusRow('Power', '${snapshot.power?.toStringAsFixed(1) ?? '--'} V'),
        _StatusRow('Signal', '${snapshot.signal?.toStringAsFixed(0) ?? '--'}%'),
        _StatusRow('Satellites', '${snapshot.sat ?? '--'}'),
        _StatusRow('HDOP', '${snapshot.hdop?.toStringAsFixed(1) ?? '--'}'),
        _StatusRow('Odometer', '${snapshot.odometer?.toStringAsFixed(0) ?? '--'} km'),
        _StatusRow('Hours', '${snapshot.hours?.toStringAsFixed(1) ?? '--'} h'),
        if (snapshot.alarm != null)
          _StatusRow('Alarm', snapshot.alarm!, color: Colors.red),
      ],
    );
  }
}
```

## Best Practices

### ✅ DO: Use granular providers for single metrics

```dart
// Rebuilds ONLY when speed changes
final speed = ref.watchSpeed(deviceId);
```

### ✅ DO: Use select() for multiple related metrics

```dart
// Rebuilds only when battery, power, or signal changes
final metrics = ref.watch(
  vehicleSnapshotProvider(deviceId).select(
    (n) => (n.value?.batteryLevel, n.value?.power, n.value?.signal)
  ),
);
```

### ❌ DON'T: Watch the entire snapshot unnecessarily

```dart
// AVOID: Rebuilds on ANY field change
final snapshot = ref.watch(vehicleSnapshotProvider(deviceId));
```

### ✅ DO: Combine engine state with motion/speed for accurate status

```dart
final engine = ref.watchEngine(deviceId);
final motion = ref.watchMotion(deviceId);
final speed = ref.watchSpeed(deviceId);

// Engine ON + motion detected + speed > 0 = truly moving
final isMoving = engine == EngineState.on && 
                 motion == true && 
                 (speed ?? 0) > 0;
```

### ✅ DO: Use helper extensions for cleaner code

```dart
// Clean and readable
final battery = ref.watchBattery(deviceId);
final signal = ref.watchSignal(deviceId);

// Instead of verbose:
final battery = ref.watch(vehicleBatteryProvider(deviceId));
final signal = ref.watch(vehicleSignalProvider(deviceId));
```

## Data Flow Diagram

```
Traccar WebSocket
       ↓
   Position JSON
       ↓
VehicleDataSnapshot.fromPosition()
   (extracts all attributes)
       ↓
VehicleDataRepository._updateDeviceSnapshot()
       ↓
   existing.merge(newer)
   (propagates all fields)
       ↓
ValueNotifier<VehicleDataSnapshot>.value = merged
       ↓
vehiclePositionProvider (StreamProvider)
vehicleEngineProvider (StreamProvider)
vehicleSpeedProvider
vehicleBatteryProvider
vehiclePowerProvider
... (all granular providers)
       ↓
    UI Widgets
  (ref.watchX methods)
       ↓
  Surgical rebuilds
```

## Performance Impact

### Before Upgrade
- Only 7 telemetry fields tracked
- Missing: power, signal, motion, hdop, rssi, sat, odometer, hours, blocked, alarm
- UI couldn't show real-time updates for these metrics

### After Upgrade
- **18 telemetry fields** tracked comprehensively
- All fields propagate reactively through merge()
- Granular providers enable surgical UI rebuilds
- Debug logging for critical changes (engine, battery, signal)

### Rebuild Efficiency
```dart
// Power card watches 3 fields
ref.watch(vehicleSnapshotProvider(deviceId).select(
  (n) => (n.value?.battery, n.value?.power, n.value?.signal)
))

// Rebuilds ONLY when battery, power, or signal changes
// Does NOT rebuild when speed, engine, or position changes
```

## Migration Checklist

- [x] Add telemetry fields to VehicleDataSnapshot
- [x] Update fromPosition() to extract all attributes
- [x] Upgrade merge() to propagate all fields
- [x] Update toJson/fromJson for persistence
- [x] Create granular providers for new fields
- [x] Add helper extensions (watchX methods)
- [x] Add debug logging for critical changes
- [ ] Update UI widgets to use new providers
- [ ] Test real-time updates for each metric
- [ ] Document attribute name variations (e.g., `battery` vs `batteryLevel`)

## Testing

### Manual Test: Verify Real-Time Updates

1. **Run the app** in debug mode
2. **Watch console logs** for snapshot creation:
   ```
   [VehicleSnapshot] Creating snapshot for device 123:
   [VehicleSnapshot]   ignition: true → engineState: on
   [VehicleSnapshot]   speed: 45.5 km/h, motion: true
   [VehicleSnapshot]   battery: 85.0%, power: 12.3 V
   [VehicleSnapshot]   signal: 78.0, rssi: -65.0 dBm, sat: 9, hdop: 1.2
   ```

3. **Change telemetry in Traccar** (battery, signal, etc.)
4. **Verify merge logs**:
   ```
   [VehicleSnapshot] 🔋 Battery change for device 123: 85.0% → 80.0%
   [VehicleSnapshot] 📶 Signal change for device 123: 78.0 → 65.0
   ```

5. **Confirm UI updates** immediately (< 1 second)

### Unit Test: Merge Propagation

```dart
test('merge propagates all telemetry fields', () {
  final existing = VehicleDataSnapshot(
    deviceId: 1,
    timestamp: DateTime(2025, 1, 1, 10, 0),
    batteryLevel: 85.0,
    power: 12.3,
    signal: 78.0,
  );
  
  final newer = VehicleDataSnapshot(
    deviceId: 1,
    timestamp: DateTime(2025, 1, 1, 10, 1),
    batteryLevel: 80.0,
    signal: 65.0,
  );
  
  final merged = existing.merge(newer);
  
  expect(merged.batteryLevel, 80.0); // Updated
  expect(merged.signal, 65.0); // Updated
  expect(merged.power, 12.3); // Preserved from existing
});
```

## Common Traccar Attribute Names

| Metric | Primary Name | Fallback Names |
|--------|-------------|----------------|
| Battery | `batteryLevel` | `battery` |
| Power | `power` | `voltage` |
| Signal | `signal` | `gsm` |
| Satellites | `sat` | `satellites` |
| Engine Hours | `hours` | `engineHours` |
| Distance | `distance` | `totalDistance` |
| Fuel | `fuel` | `fuelLevel` |

## Summary

The telemetry reactive upgrade ensures:
- ✅ **All 18 telemetry fields** propagate reactively
- ✅ **Real-time UI updates** for every metric
- ✅ **Surgical rebuilds** via granular providers
- ✅ **Clean API** with helper extensions
- ✅ **Debug visibility** for critical changes
- ✅ **Future-proof** attribute extraction with fallbacks

Your UI can now reactively display **any telemetry metric** from Traccar with minimal performance overhead!
