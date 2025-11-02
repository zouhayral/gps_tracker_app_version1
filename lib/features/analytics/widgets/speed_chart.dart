import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:my_app_gps/l10n/app_localizations.dart';

/// A line chart widget for visualizing speed variations over time.
///
/// Displays speed data as a smooth curved line with gradient fill,
/// interactive tooltips, and responsive axis scaling.
class SpeedChart extends StatefulWidget {
  /// Creates a [SpeedChart] widget.
  ///
  /// The [speedData] and [timestamps] lists must have the same length.
  const SpeedChart({
    required this.speedData,
    required this.timestamps,
    this.lineColor,
    this.height = 200,
    super.key,
  });

  /// List of speed values in km/h.
  final List<double> speedData;

  /// List of timestamps corresponding to each speed value.
  final List<DateTime> timestamps;

  /// Color for the line and gradient. Defaults to theme primary color.
  final Color? lineColor;

  /// Height of the chart. Defaults to 200.
  final double height;

  @override
  State<SpeedChart> createState() => _SpeedChartState();
}

class _SpeedChartState extends State<SpeedChart> {
  int? touchedIndex;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    final colorScheme = Theme.of(context).colorScheme;
    final effectiveLineColor = widget.lineColor ?? colorScheme.primary;

    // Handle empty data
    if (widget.speedData.isEmpty || widget.timestamps.isEmpty) {
      return SizedBox(
        height: widget.height,
        child: Center(
          child: Text(
            t.noData,
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: Colors.grey[600],
                ),
          ),
        ),
      );
    }

    // Validate data length
    if (widget.speedData.length != widget.timestamps.length) {
      return SizedBox(
        height: widget.height,
        child: Center(
          child: Text(
            'Error: invalid data',
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: Colors.red,
                ),
          ),
        ),
      );
    }

    return SizedBox(
      height: widget.height,
      child: Padding(
        padding: const EdgeInsets.only(right: 16, top: 16, bottom: 8),
        child: LineChart(
          _buildChartData(effectiveLineColor, t),
          duration: const Duration(milliseconds: 800),
          curve: Curves.easeInOut,
        ),
      ),
    );
  }

  LineChartData _buildChartData(Color lineColor, AppLocalizations t) {
    // Calculate min/max for Y axis
    final maxSpeed = widget.speedData.reduce((a, b) => a > b ? a : b);
    final minSpeed = widget.speedData.reduce((a, b) => a < b ? a : b);
    final speedRange = maxSpeed - minSpeed;
    
    // Add padding to Y axis range (10% on each side)
    final yMin = (minSpeed - speedRange * 0.1).clamp(0.0, double.infinity);
    final yMax = maxSpeed + speedRange * 0.1;

    return LineChartData(
      lineTouchData: _buildTouchData(lineColor),
      gridData: _buildGridData(),
      titlesData: _buildTitlesData(t),
      borderData: FlBorderData(
        show: true,
        border: Border(
          bottom: BorderSide(color: Colors.grey[300]!),
          left: BorderSide(color: Colors.grey[300]!),
        ),
      ),
      minX: 0,
      maxX: (widget.speedData.length - 1).toDouble(),
      minY: yMin,
      maxY: yMax,
      lineBarsData: [
        LineChartBarData(
          spots: _buildSpots(),
          isCurved: true,
          color: lineColor,
          barWidth: 3,
          isStrokeCapRound: true,
          dotData: FlDotData(
            getDotPainter: (spot, percent, barData, index) {
              return FlDotCirclePainter(
                radius: index == touchedIndex ? 6 : 3,
                color: Colors.white,
                strokeWidth: 2,
                strokeColor: lineColor,
              );
            },
          ),
          belowBarData: BarAreaData(
            show: true,
            gradient: LinearGradient(
              colors: [
                lineColor.withOpacity(0.3),
                lineColor.withOpacity(0),
              ],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
          ),
        ),
      ],
    );
  }

  List<FlSpot> _buildSpots() {
    return List.generate(
      widget.speedData.length,
      (index) => FlSpot(index.toDouble(), widget.speedData[index]),
    );
  }

  LineTouchData _buildTouchData(Color lineColor) {
    return LineTouchData(
      touchCallback: (FlTouchEvent event, LineTouchResponse? touchResponse) {
        setState(() {
          if (touchResponse?.lineBarSpots != null &&
              touchResponse!.lineBarSpots!.isNotEmpty) {
            touchedIndex = touchResponse.lineBarSpots!.first.spotIndex;
          } else {
            touchedIndex = null;
          }
        });
      },
      touchTooltipData: LineTouchTooltipData(
        getTooltipColor: (touchedSpot) => lineColor.withOpacity(0.9),
        tooltipRoundedRadius: 8,
        tooltipPadding: const EdgeInsets.all(8),
        tooltipMargin: 8,
        getTooltipItems: (List<LineBarSpot> touchedSpots) {
          return touchedSpots.map((LineBarSpot touchedSpot) {
            final index = touchedSpot.spotIndex;
            if (index >= widget.timestamps.length) return null;

            final timestamp = widget.timestamps[index];
            final speed = touchedSpot.y;
            final timeStr = _formatTooltipTime(timestamp);

            return LineTooltipItem(
              '$timeStr\n${speed.toStringAsFixed(1)} km/h',
              const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 12,
              ),
            );
          }).toList();
        },
      ),
    );
  }

  FlGridData _buildGridData() {
    return FlGridData(
      horizontalInterval: _calculateHorizontalInterval(),
      verticalInterval: _calculateVerticalInterval(),
      getDrawingHorizontalLine: (value) {
        return FlLine(
          color: Colors.grey[300],
          strokeWidth: 1,
          dashArray: [5, 5],
        );
      },
      getDrawingVerticalLine: (value) {
        return FlLine(
          color: Colors.grey[300],
          strokeWidth: 1,
          dashArray: [5, 5],
        );
      },
    );
  }

  FlTitlesData _buildTitlesData(AppLocalizations t) {
    return FlTitlesData(
      bottomTitles: AxisTitles(
        axisNameWidget: Text(
          t.time,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w500,
              ),
        ),
        axisNameSize: 24,
        sideTitles: SideTitles(
          showTitles: true,
          reservedSize: 32,
          interval: _calculateBottomTitleInterval(),
          getTitlesWidget: (value, meta) {
            final index = value.toInt();
            if (index < 0 || index >= widget.timestamps.length) {
              return const SizedBox.shrink();
            }
            return Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                _formatBottomAxisLabel(widget.timestamps[index]),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      fontSize: 10,
                    ),
                textAlign: TextAlign.center,
              ),
            );
          },
        ),
      ),
      leftTitles: AxisTitles(
        axisNameWidget: Text(
          t.speed,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w500,
              ),
        ),
        axisNameSize: 60,
        sideTitles: SideTitles(
          showTitles: true,
          reservedSize: 44,
          interval: _calculateHorizontalInterval(),
          getTitlesWidget: (value, meta) {
            return Text(
              value.toStringAsFixed(0),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    fontSize: 10,
                  ),
              textAlign: TextAlign.right,
            );
          },
        ),
      ),
      topTitles: const AxisTitles(
        
      ),
      rightTitles: const AxisTitles(
        
      ),
    );
  }

  String _formatBottomAxisLabel(DateTime timestamp) {
    final dataRange = widget.timestamps.last.difference(widget.timestamps.first);

    if (dataRange.inDays < 2) {
      // Daily view: show hours
      return DateFormat('HH:mm').format(timestamp);
    } else if (dataRange.inDays <= 7) {
      // Weekly view: show day/month
      return DateFormat('dd/MM').format(timestamp);
    } else {
      // Monthly view: show day/month
      return DateFormat('dd/MM').format(timestamp);
    }
  }

  String _formatTooltipTime(DateTime timestamp) {
    final dataRange = widget.timestamps.last.difference(widget.timestamps.first);

    if (dataRange.inDays < 2) {
      // Daily view: show full time
      return DateFormat('HH:mm:ss').format(timestamp);
    } else {
      // Weekly/Monthly view: show date and time
      return DateFormat('dd/MM HH:mm').format(timestamp);
    }
  }

  double _calculateHorizontalInterval() {
    final maxSpeed = widget.speedData.reduce((a, b) => a > b ? a : b);
    final minSpeed = widget.speedData.reduce((a, b) => a < b ? a : b);
    final range = maxSpeed - minSpeed;

    // Aim for about 5 horizontal lines
    if (range <= 20) return 5;
    if (range <= 50) return 10;
    if (range <= 100) return 20;
    return 50;
  }

  double _calculateVerticalInterval() {
    final dataCount = widget.speedData.length;

    // Show fewer labels if we have many data points
    if (dataCount <= 10) return 1;
    if (dataCount <= 20) return 2;
    if (dataCount <= 50) return 5;
    return 10;
  }

  double _calculateBottomTitleInterval() {
    final dataCount = widget.speedData.length;

    // Show fewer labels if we have many data points
    if (dataCount <= 10) return 1;
    if (dataCount <= 20) return 2;
    if (dataCount <= 50) return 5;
    if (dataCount <= 100) return 10;
    return 20;
  }
}
