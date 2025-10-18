import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_app_gps/core/database/entities/telemetry_record.dart';
import 'package:my_app_gps/features/telemetry/telemetry_history_provider.dart';

class TelemetryHistoryPage extends ConsumerWidget {
  const TelemetryHistoryPage({required this.deviceId, super.key});

  final int deviceId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncHistory = ref.watch(telemetryHistoryProvider(deviceId));

    return Scaffold(
      appBar: AppBar(title: const Text('Telemetry History')),
      body: asyncHistory.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, st) => Center(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Text('Failed to load history: $e'),
          ),
        ),
        data: (records) {
          if (records.isEmpty) {
            return const Center(
              child: Text('No telemetry data in the last 24 hours.'),
            );
          }

          // Prepare chart spots
          final batterySpots = <FlSpot>[];
          final signalSpots = <FlSpot>[];
          if (records.isNotEmpty) {
            final firstTs = records.first.timestampMs.toDouble();
            for (final r in records) {
              final x = (r.timestampMs.toDouble() - firstTs) /
                  1000.0; // seconds since start
              if (r.battery != null) {
                batterySpots.add(FlSpot(x, r.battery!));
              }
              if (r.signal != null) {
                signalSpots.add(FlSpot(x, r.signal!));
              }
            }
          }

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              const _SectionTitle(title: 'Battery (%)'),
              SizedBox(
                height: 220,
                child: batterySpots.isEmpty
                    ? const Center(child: Text('No battery readings'))
                    : LineChart(
                        _lineChartData(
                          spots: batterySpots,
                          color: Colors.green,
                          yMin: 0,
                          yMax: 100,
                          title: 'Battery %',
                        ),
                      ),
              ),
              const SizedBox(height: 24),
              const _SectionTitle(title: 'Signal strength'),
              SizedBox(
                height: 220,
                child: signalSpots.isEmpty
                    ? const Center(child: Text('No signal readings'))
                    : LineChart(
                        _lineChartData(
                          spots: signalSpots,
                          color: Colors.blue,
                          yMin: 0,
                          yMax: 100,
                          title: 'Signal',
                        ),
                      ),
              ),
              const SizedBox(height: 24),
              _StatsSummary(records: records),
            ],
          );
        },
      ),
    );
  }

  LineChartData _lineChartData({
    required List<FlSpot> spots,
    required Color color,
    required double yMin,
    required double yMax,
    String? title,
  }) {
    return LineChartData(
      minY: yMin,
      maxY: yMax,
      borderData: FlBorderData(show: false),
      gridData: const FlGridData(drawVerticalLine: false),
      titlesData: const FlTitlesData(
        bottomTitles: AxisTitles(),
        rightTitles: AxisTitles(),
        topTitles: AxisTitles(),
      ),
      lineBarsData: [
        LineChartBarData(
          spots: spots,
          color: color,
          dotData: const FlDotData(show: false),
        ),
      ],
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title});
  final String title;
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        title,
        style: Theme.of(context).textTheme.titleMedium,
      ),
    );
  }
}

class _StatsSummary extends StatelessWidget {
  const _StatsSummary({required this.records});
  final List<TelemetryRecord> records;

  @override
  Widget build(BuildContext context) {
    final batteryValues =
        records.map((r) => r.battery).whereType<double>().toList();
    final signalValues =
        records.map((r) => r.signal).whereType<double>().toList();
    double? avgBattery;
    double? avgSignal;
    if (batteryValues.isNotEmpty) {
      avgBattery = batteryValues.reduce((a, b) => a + b) / batteryValues.length;
    }
    if (signalValues.isNotEmpty) {
      avgSignal = signalValues.reduce((a, b) => a + b) / signalValues.length;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [Text('Samples: ${records.length}'), if (avgBattery != null)
            Text('Avg battery: ${avgBattery.toStringAsFixed(1)}%'),
          if (avgSignal != null)
            Text('Avg signal: ${avgSignal.toStringAsFixed(1)}'),],
    );
  }
}
