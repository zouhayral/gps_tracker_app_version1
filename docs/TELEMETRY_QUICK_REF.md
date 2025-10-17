# Telemetry Provider Quick Reference

## Available Telemetry Providers

### Engine & Motion
```dart
ref.watchEngine(deviceId)     // EngineState? (on, off, unknown)
ref.watchMotion(deviceId)     // bool? (motion sensor)
ref.watchSpeed(deviceId)      // double? (km/h)
```

### Distance & Usage
```dart
ref.watchDistance(deviceId)   // double? (trip distance in km)
ref.watchOdometer(deviceId)   // double? (total odometer in km)
ref.watchHours(deviceId)      // double? (engine hours)
```

### Power & Battery
```dart
ref.watchBattery(deviceId)    // double? (battery percentage 0-100)
ref.watchPower(deviceId)      // double? (external power voltage)
```

### Connectivity & GPS
```dart
ref.watchSignal(deviceId)     // double? (GSM signal 0-100)
ref.watchRssi(deviceId)       // double? (signal strength in dBm)
ref.watchSat(deviceId)        // int? (satellite count)
ref.watchHdop(deviceId)       // double? (GPS accuracy, lower is better)
```

### Fuel & Resources
```dart
ref.watchFuel(deviceId)       // double? (fuel level)
```

### Status & Alerts
```dart
ref.watchLastUpdate(deviceId) // DateTime? (last data timestamp)
ref.watchBlocked(deviceId)    // bool? (device blocked status)
ref.watchAlarm(deviceId)      // String? (active alarm type)
```

### Position Data
```dart
ref.watchPosition(deviceId)   // Position? (full position object)
```

## Usage Patterns

### Single Field Watch (Recommended)
Rebuilds **only when that specific field changes**:

```dart
class BatteryWidget extends ConsumerWidget {
  final int deviceId;
  
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final battery = ref.watchBattery(deviceId);
    return Text('Battery: ${battery?.toStringAsFixed(0) ?? '--'}%');
  }
}
```

### Multiple Fields with Select (Efficient)
Rebuilds **only when selected fields change**:

```dart
class PowerCard extends ConsumerWidget {
  final int deviceId;
  
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(
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
        Text('Battery: ${data.battery?.toStringAsFixed(0) ?? '--'}%'),
        Text('Power: ${data.power?.toStringAsFixed(1) ?? '--'} V'),
        Text('Signal: ${data.signal?.toStringAsFixed(0) ?? '--'}%'),
      ],
    );
  }
}
```

### Direct Snapshot Watch (Use Sparingly)
Rebuilds **on ANY field change** - only use when you need most/all fields:

```dart
class VehicleDetailsSheet extends ConsumerWidget {
  final int deviceId;
  
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.watch(vehicleSnapshotProvider(deviceId));
    final snapshot = notifier.value;
    
    if (snapshot == null) return CircularProgressIndicator();
    
    return Column(
      children: [
        Text('Engine: ${snapshot.engineState?.name ?? '--'}'),
        Text('Speed: ${snapshot.speed?.toStringAsFixed(0) ?? '--'} km/h'),
        Text('Battery: ${snapshot.batteryLevel?.toStringAsFixed(0) ?? '--'}%'),
        // ... many more fields
      ],
    );
  }
}
```

## Common Combinations

### Moving Vehicle Detection
```dart
final engine = ref.watchEngine(deviceId);
final motion = ref.watchMotion(deviceId);
final speed = ref.watchSpeed(deviceId);

final isActuallyMoving = 
  engine == EngineState.on && 
  motion == true && 
  (speed ?? 0) > 0;
```

### GPS Quality Assessment
```dart
final sat = ref.watchSat(deviceId);
final hdop = ref.watchHdop(deviceId);

final gpsQuality = (sat ?? 0) >= 5 && (hdop ?? 99) < 3.0
  ? 'Good' 
  : 'Poor';
```

### Power Status
```dart
final battery = ref.watchBattery(deviceId);
final power = ref.watchPower(deviceId);

final powerStatus = (power ?? 0) > 11.0
  ? 'External Power'
  : battery != null && battery < 20
    ? 'Low Battery'
    : 'Battery';
```

### Connectivity Health
```dart
final signal = ref.watchSignal(deviceId);
final rssi = ref.watchRssi(deviceId);

final connectivity = (signal ?? 0) > 50
  ? 'Strong'
  : (signal ?? 0) > 20
    ? 'Moderate'
    : 'Weak';
```

## Performance Tips

1. **Use specific providers** instead of watching the whole snapshot
2. **Combine with `.select()`** when watching multiple related fields
3. **Avoid unnecessary watches** - only watch what your widget displays
4. **Use `const` constructors** when possible to reduce rebuilds

## Debug Logging

Watch the console for reactive updates:

```
[VehicleSnapshot] 🔧 Engine state change detected for device 123: off → on
[VehicleSnapshot] 🔋 Battery change for device 123: 85.0% → 80.0%
[VehicleSnapshot] 📶 Signal change for device 123: 78.0 → 65.0
[VehicleProvider] 🔄 Position updated for device 123: lat=35.73898, lon=-5.88946, ignition=true, speed=45.5
[VehicleProvider] 🔄 Engine state updated for device 123: EngineState.on
```

## Null Handling

All providers return **nullable values**. Always provide fallbacks:

```dart
// Good
final speed = ref.watchSpeed(deviceId);
Text('Speed: ${speed?.toStringAsFixed(0) ?? '--'} km/h')

// Also good with default
final speed = ref.watchSpeed(deviceId) ?? 0.0;
Text('Speed: ${speed.toStringAsFixed(0)} km/h')
```

## Advanced: Computed Metrics

```dart
class FuelEfficiencyWidget extends ConsumerWidget {
  final int deviceId;
  
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final distance = ref.watchDistance(deviceId);
    final fuel = ref.watchFuel(deviceId);
    
    final efficiency = distance != null && fuel != null && fuel > 0
      ? distance / fuel
      : null;
    
    return Text(
      'Efficiency: ${efficiency?.toStringAsFixed(2) ?? '--'} km/L'
    );
  }
}
```

## Migration from Old Code

### Before (Manual Attribute Parsing)
```dart
final position = ref.watch(positionProvider(deviceId));
final batteryAttr = position?.attributes['batteryLevel'];
final battery = batteryAttr is num ? batteryAttr.toDouble() : null;
```

### After (Reactive Provider)
```dart
final battery = ref.watchBattery(deviceId);
```

**Benefits:**
- ✅ Cleaner code
- ✅ Automatic type conversion
- ✅ Surgical rebuilds
- ✅ Centralized extraction logic
- ✅ Fallback handling for different attribute names
