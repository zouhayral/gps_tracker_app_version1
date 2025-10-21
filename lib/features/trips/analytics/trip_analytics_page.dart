import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_app_gps/data/models/trip_aggregate.dart';
import 'package:my_app_gps/providers/trip_providers.dart';

class TripAnalyticsPage extends ConsumerWidget {
  const TripAnalyticsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final range = DateTimeRange(
      start: DateTime.now().subtract(const Duration(days: 30)),
      end: DateTime.now(),
    );
    final analyticsAsync = ref.watch(tripAnalyticsProvider(range));

    return Scaffold(
      appBar: AppBar(title: const Text('Trip Analytics')),
      body: analyticsAsync.when(
        data: (data) => _AnalyticsView(data: data),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error loading analytics: $e')),
      ),
    );
  }
}

class _AnalyticsView extends StatelessWidget {
  const _AnalyticsView({required this.data});
  final Map<String, TripAggregate> data;

  @override
  Widget build(BuildContext context) {
    final sortedKeys = data.keys.toList()..sort();
    final totals = data.values.fold<TripAggregate>(
      const TripAggregate(
        totalDistanceKm: 0,
        totalDurationHrs: 0,
        avgSpeedKph: 0,
        tripCount: 0,
      ),
      (a, b) => TripAggregate(
        totalDistanceKm: a.totalDistanceKm + b.totalDistanceKm,
        totalDurationHrs: a.totalDurationHrs + b.totalDurationHrs,
        avgSpeedKph: (a.avgSpeedKph + b.avgSpeedKph) / 2,
        tripCount: a.tripCount + b.tripCount,
      ),
    );

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('Last 30 Days Summary', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 12),
        Wrap(
          spacing: 16,
          runSpacing: 8,
          children: [
            _StatTile(label: 'Total Trips', value: totals.tripCount.toString()),
            _StatTile(label: 'Total Distance', value: '${totals.totalDistanceKm.toStringAsFixed(1)} km'),
            _StatTile(label: 'Total Duration', value: '${totals.totalDurationHrs.toStringAsFixed(1)} h'),
            _StatTile(label: 'Avg Speed', value: '${totals.avgSpeedKph.toStringAsFixed(1)} km/h'),
          ],
        ),
        const SizedBox(height: 16),
        const Divider(),
        const SizedBox(height: 16),
        Text('Distance per day', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        if (sortedKeys.isEmpty)
          const Text('No data for the selected period')
        else
          SizedBox(
            height: 220,
            child: BarChart(
              BarChartData(
                alignment: BarChartAlignment.spaceBetween,
                gridData: FlGridData(show: false),
                borderData: FlBorderData(show: false),
                titlesData: FlTitlesData(
                  leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 36)),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      getTitlesWidget: (v, _) {
                        final idx = v.toInt();
                        if (idx < 0 || idx >= sortedKeys.length) return const SizedBox.shrink();
                        final key = sortedKeys[idx];
                        // Show MM-dd
                        final parts = key.split('-');
                        final label = parts.length == 3 ? '${parts[1]}-${parts[2]}' : key;
                        return Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(label, style: const TextStyle(fontSize: 10)),
                        );
                      },
                    ),
                  ),
                ),
                barGroups: [
                  for (int i = 0; i < sortedKeys.length; i++)
                    BarChartGroupData(
                      x: i,
                      barRods: [
                        BarChartRodData(
                          toY: data[sortedKeys[i]]!.totalDistanceKm,
                          width: 10,
                          gradient: const LinearGradient(colors: [Color(0xFF42A5F5), Color(0xFF1E88E5)]),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ],
                    ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceVariant,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 4),
          Text(value, style: Theme.of(context).textTheme.titleMedium),
        ],
      ),
    );
  }
}
