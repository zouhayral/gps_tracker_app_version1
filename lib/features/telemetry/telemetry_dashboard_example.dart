import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_app_gps/core/data/vehicle_data_snapshot.dart';
import 'package:my_app_gps/core/providers/vehicle_providers.dart';

/// Example widget demonstrating comprehensive telemetry display
/// Shows how to use all new reactive telemetry providers
class TelemetryDashboard extends ConsumerWidget {
  const TelemetryDashboard({
    required this.deviceId,
    super.key,
  });

  final int deviceId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Engine & Motion Section
          _SectionHeader('Engine & Motion'),
          _EngineMotionCard(deviceId: deviceId),
          const SizedBox(height: 16),

          // Power & Battery Section
          _SectionHeader('Power & Battery'),
          _PowerBatteryCard(deviceId: deviceId),
          const SizedBox(height: 16),

          // GPS & Connectivity Section
          _SectionHeader('GPS & Connectivity'),
          _GpsConnectivityCard(deviceId: deviceId),
          const SizedBox(height: 16),

          // Usage & Distance Section
          _SectionHeader('Usage & Distance'),
          _UsageCard(deviceId: deviceId),
          const SizedBox(height: 16),

          // Status & Alerts Section
          _SectionHeader('Status & Alerts'),
          _StatusCard(deviceId: deviceId),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.title);
  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        title,
        style: Theme.of(context).textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.bold,
            ),
      ),
    );
  }
}

/// Engine & Motion Card - Uses 3 specific providers
class _EngineMotionCard extends ConsumerWidget {
  const _EngineMotionCard({required this.deviceId});
  final int deviceId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Watch only the specific fields needed - surgical rebuilds!
    final engine = ref.watchEngine(deviceId);
    final motion = ref.watchMotion(deviceId);
    final speed = ref.watchSpeed(deviceId);

    final isRunning = engine == EngineState.on;
    final isMoving = motion == true && (speed ?? 0) > 0;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            _MetricRow(
              icon: Icons.power_settings_new,
              label: 'Engine',
              value: engine?.name.toUpperCase() ?? '--',
              color: isRunning ? Colors.green : Colors.grey,
            ),
            const Divider(),
            _MetricRow(
              icon: Icons.directions_walk,
              label: 'Motion Sensor',
              value: motion == true
                  ? 'DETECTED'
                  : motion == false
                      ? 'IDLE'
                      : '--',
              color: motion == true ? Colors.blue : Colors.grey,
            ),
            const Divider(),
            _MetricRow(
              icon: Icons.speed,
              label: 'Speed',
              value: '${speed?.toStringAsFixed(0) ?? '--'} km/h',
              color: isMoving ? Colors.green : Colors.grey,
            ),
          ],
        ),
      ),
    );
  }
}

/// Power & Battery Card - Uses select() for multiple fields
class _PowerBatteryCard extends ConsumerWidget {
  const _PowerBatteryCard({required this.deviceId});
  final int deviceId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Watch multiple related fields with select() - efficient!
    final data = ref.watch(
      vehicleSnapshotProvider(deviceId).select(
        (notifier) => (
          battery: notifier.value?.batteryLevel,
          power: notifier.value?.power,
          fuel: notifier.value?.fuelLevel,
        ),
      ),
    );

    final hasExternalPower = (data.power ?? 0) > 11.0;
    final lowBattery = (data.battery ?? 100) < 20;

    return Card(
      color: lowBattery && !hasExternalPower ? Colors.red.shade50 : null,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            _MetricRow(
              icon: Icons.battery_charging_full,
              label: 'Battery',
              value: '${data.battery?.toStringAsFixed(0) ?? '--'}%',
              color: lowBattery ? Colors.red : Colors.green,
            ),
            const Divider(),
            _MetricRow(
              icon: Icons.power,
              label: 'External Power',
              value: '${data.power?.toStringAsFixed(1) ?? '--'} V',
              color: hasExternalPower ? Colors.green : Colors.orange,
            ),
            const Divider(),
            _MetricRow(
              icon: Icons.local_gas_station,
              label: 'Fuel',
              value: '${data.fuel?.toStringAsFixed(0) ?? '--'}%',
              color: (data.fuel ?? 100) < 20 ? Colors.red : Colors.blue,
            ),
          ],
        ),
      ),
    );
  }
}

/// GPS & Connectivity Card - Shows GPS quality and signal
class _GpsConnectivityCard extends ConsumerWidget {
  const _GpsConnectivityCard({required this.deviceId});
  final int deviceId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sat = ref.watchSat(deviceId);
    final hdop = ref.watchHdop(deviceId);
    final signal = ref.watchSignal(deviceId);
    final rssi = ref.watchRssi(deviceId);

    final gpsQuality = _calculateGpsQuality(sat, hdop);
    final signalQuality = _calculateSignalQuality(signal);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            _MetricRow(
              icon: Icons.satellite_alt,
              label: 'Satellites',
              value: '${sat ?? '--'}',
              color: gpsQuality == 'Excellent'
                  ? Colors.green
                  : gpsQuality == 'Good'
                      ? Colors.blue
                      : Colors.orange,
            ),
            const Divider(),
            _MetricRow(
              icon: Icons.gps_fixed,
              label: 'HDOP (Accuracy)',
              value: hdop != null ? hdop.toStringAsFixed(1) : '--',
              color: (hdop ?? 99) < 2.0 ? Colors.green : Colors.orange,
            ),
            const Divider(),
            _MetricRow(
              icon: Icons.signal_cellular_alt,
              label: 'GSM Signal',
              value: '${signal?.toStringAsFixed(0) ?? '--'}%',
              color: signalQuality == 'Strong'
                  ? Colors.green
                  : signalQuality == 'Moderate'
                      ? Colors.orange
                      : Colors.red,
            ),
            const Divider(),
            _MetricRow(
              icon: Icons.network_cell,
              label: 'RSSI',
              value: rssi != null ? '${rssi.toStringAsFixed(0)} dBm' : '--',
              color: (rssi ?? -999) > -80 ? Colors.green : Colors.orange,
            ),
          ],
        ),
      ),
    );
  }

  String _calculateGpsQuality(int? sat, double? hdop) {
    if (sat == null || hdop == null) return 'Unknown';
    if (sat >= 8 && hdop < 2.0) return 'Excellent';
    if (sat >= 5 && hdop < 3.0) return 'Good';
    return 'Poor';
  }

  String _calculateSignalQuality(double? signal) {
    if (signal == null) return 'Unknown';
    if (signal > 70) return 'Strong';
    if (signal > 40) return 'Moderate';
    return 'Weak';
  }
}

/// Usage Card - Distance and engine hours
class _UsageCard extends ConsumerWidget {
  const _UsageCard({required this.deviceId});
  final int deviceId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final distance = ref.watchDistance(deviceId);
    final odometer = ref.watchOdometer(deviceId);
    final hours = ref.watchHours(deviceId);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            _MetricRow(
              icon: Icons.route,
              label: 'Trip Distance',
              value: '${distance?.toStringAsFixed(1) ?? '--'} km',
              color: Colors.blue,
            ),
            const Divider(),
            _MetricRow(
              icon: Icons.av_timer,
              label: 'Total Odometer',
              value: '${odometer?.toStringAsFixed(0) ?? '--'} km',
              color: Colors.purple,
            ),
            const Divider(),
            _MetricRow(
              icon: Icons.timer,
              label: 'Engine Hours',
              value: '${hours?.toStringAsFixed(1) ?? '--'} h',
              color: Colors.teal,
            ),
          ],
        ),
      ),
    );
  }
}

/// Status Card - Blocked status and alarms
class _StatusCard extends ConsumerWidget {
  const _StatusCard({required this.deviceId});
  final int deviceId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final blocked = ref.watchBlocked(deviceId);
    final alarm = ref.watchAlarm(deviceId);
    final lastUpdate = ref.watchLastUpdate(deviceId);

    final hasAlert = blocked == true || alarm != null;

    return Card(
      color: hasAlert ? Colors.orange.shade50 : null,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            _MetricRow(
              icon: Icons.block,
              label: 'Blocked',
              value: blocked == true
                  ? 'YES'
                  : blocked == false
                      ? 'NO'
                      : '--',
              color: blocked == true ? Colors.red : Colors.green,
            ),
            if (alarm != null) ...[
              const Divider(),
              _MetricRow(
                icon: Icons.warning,
                label: 'Alarm',
                value: alarm,
                color: Colors.red,
              ),
            ],
            const Divider(),
            _MetricRow(
              icon: Icons.update,
              label: 'Last Update',
              value:
                  lastUpdate != null ? _formatRelativeTime(lastUpdate) : '--',
              color: Colors.grey,
            ),
          ],
        ),
      ),
    );
  }

  String _formatRelativeTime(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inSeconds < 60) return '${diff.inSeconds}s ago';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }
}

class _MetricRow extends StatelessWidget {
  const _MetricRow({
    required this.icon,
    required this.label,
    required this.value,
    this.color,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: color ?? Colors.grey, size: 24),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            label,
            style: Theme.of(context).textTheme.bodyLarge,
          ),
        ),
        Text(
          value,
          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                fontWeight: FontWeight.bold,
                color: color,
              ),
        ),
      ],
    );
  }
}
