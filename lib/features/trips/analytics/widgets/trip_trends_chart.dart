import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:my_app_gps/data/models/trip_snapshot.dart';

enum MetricType { distance, duration, trips, speed }

class TripTrendsChart extends StatelessWidget {
  const TripTrendsChart(
      {required this.snapshots, required this.metric, super.key});

  final List<TripSnapshot> snapshots;
  final MetricType metric;

  @override
  Widget build(BuildContext context) {
    if (snapshots.isEmpty) {
      return const Center(child: Text('No monthly data available.'));
    }

    final labels = snapshots
        .map((s) =>
            s.monthKey.length >= 7 ? s.monthKey.substring(5) : s.monthKey)
        .toList();
    final values = snapshots.map((s) {
      switch (metric) {
        case MetricType.distance:
          return s.totalDistanceKm;
        case MetricType.duration:
          return s.totalDurationHrs;
        case MetricType.trips:
          return s.tripCount.toDouble();
        case MetricType.speed:
          return s.avgSpeedKph;
      }
    }).toList();

    final color = Theme.of(context).colorScheme.primary;

    return SizedBox(
      height: 220,
      child: BarChart(
        BarChartData(
          alignment: BarChartAlignment.spaceAround,
          barGroups: [
            for (int i = 0; i < values.length; i++)
              BarChartGroupData(
                x: i,
                barRods: [
                  BarChartRodData(
                    toY: values[i],
                    width: 14,
                    borderRadius: BorderRadius.circular(4),
                    color: color,
                  ),
                ],
              ),
          ],
          titlesData: FlTitlesData(
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                getTitlesWidget: (value, _) => Text(
                  value.toInt() >= 0 && value.toInt() < labels.length
                      ? labels[value.toInt()]
                      : '',
                  style: const TextStyle(fontSize: 10),
                ),
              ),
            ),
            leftTitles: const AxisTitles(
                sideTitles: SideTitles(showTitles: true, reservedSize: 35)),
            rightTitles: const AxisTitles(),
            topTitles: const AxisTitles(),
          ),
          gridData: const FlGridData(),
          borderData: FlBorderData(show: false),
        ),
        duration: const Duration(milliseconds: 500),
      ),
    );
  }
}
