import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:my_app_gps/l10n/app_localizations.dart';

/// A bar chart widget for visualizing trip counts over time periods.
///
/// Displays trip data as vertical bars with gradient fill,
/// interactive tooltips, and responsive axis scaling.
class TripBarChart extends StatefulWidget {
  /// Creates a [TripBarChart] widget.
  ///
  /// The [tripCounts] and [labels] lists must have the same length.
  const TripBarChart({
    required this.tripCounts,
    required this.labels,
    this.barColor,
    this.height = 200,
    super.key,
  });

  /// List of trip counts for each period.
  final List<int> tripCounts;

  /// Labels for each bar (e.g., ["Lun", "Mar", "Mer"] or dates).
  final List<String> labels;

  /// Color for the bars. Defaults to theme primary color.
  final Color? barColor;

  /// Height of the chart. Defaults to 200.
  final double height;

  @override
  State<TripBarChart> createState() => _TripBarChartState();
}

class _TripBarChartState extends State<TripBarChart> {
  int? touchedIndex;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    final colorScheme = Theme.of(context).colorScheme;
    final effectiveBarColor = widget.barColor ?? colorScheme.primary;

    // Handle empty data
    if (widget.tripCounts.isEmpty || widget.labels.isEmpty) {
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
    if (widget.tripCounts.length != widget.labels.length) {
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
        child: BarChart(
          _buildChartData(effectiveBarColor, t),
          swapAnimationDuration: const Duration(milliseconds: 800),
          swapAnimationCurve: Curves.easeOut,
        ),
      ),
    );
  }

  BarChartData _buildChartData(Color barColor, AppLocalizations t) {
    // Calculate max value for Y axis
    final maxCount = widget.tripCounts.reduce((a, b) => a > b ? a : b);
    final yMax = (maxCount * 1.2).ceilToDouble(); // Add 20% padding

    return BarChartData(
      maxY: yMax,
      minY: 0,
      barTouchData: _buildTouchData(barColor, t),
      titlesData: _buildTitlesData(t),
      borderData: FlBorderData(
        show: true,
        border: Border(
          bottom: BorderSide(color: Colors.grey[300]!),
          left: BorderSide(color: Colors.grey[300]!),
        ),
      ),
      gridData: FlGridData(
        drawVerticalLine: false,
        horizontalInterval: _calculateHorizontalInterval(maxCount),
        getDrawingHorizontalLine: (value) {
          return FlLine(
            color: Colors.grey[300],
            strokeWidth: 1,
            dashArray: [5, 5],
          );
        },
      ),
      barGroups: _buildBarGroups(barColor),
      alignment: BarChartAlignment.spaceAround,
    );
  }

  List<BarChartGroupData> _buildBarGroups(Color barColor) {
    return List.generate(
      widget.tripCounts.length,
      (index) {
        final isTouched = index == touchedIndex;
        final count = widget.tripCounts[index];

        return BarChartGroupData(
          x: index,
          barRods: [
            BarChartRodData(
              toY: count.toDouble(),
              width: isTouched ? 20 : 16,
              borderRadius: BorderRadius.circular(8),
              gradient: LinearGradient(
                colors: [
                  barColor,
                  barColor.withOpacity(0.5),
                ],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
              backDrawRodData: BackgroundBarChartRodData(
                show: true,
                toY: _calculateMaxYForBackground(),
                color: Colors.grey[200],
              ),
            ),
          ],
          showingTooltipIndicators: isTouched ? [0] : [],
        );
      },
    );
  }

  BarTouchData _buildTouchData(Color barColor, AppLocalizations t) {
    return BarTouchData(
      enabled: true,
      touchCallback: (FlTouchEvent event, BarTouchResponse? response) {
        setState(() {
          if (response?.spot != null &&
              event is! FlPanEndEvent &&
              event is! FlPointerExitEvent) {
            touchedIndex = response!.spot!.touchedBarGroupIndex;
          } else {
            touchedIndex = null;
          }
        });
      },
      touchTooltipData: BarTouchTooltipData(
        getTooltipColor: (group) => barColor.withOpacity(0.9),
        tooltipRoundedRadius: 8,
        tooltipPadding: const EdgeInsets.all(8),
        tooltipMargin: 8,
        getTooltipItem: (group, groupIndex, rod, rodIndex) {
          final count = widget.tripCounts[groupIndex];
          final label = widget.labels[groupIndex];

          return BarTooltipItem(
            '$label\n',
            const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 12,
            ),
            children: [
              TextSpan(
                text: t.tripCount(count),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.normal,
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  FlTitlesData _buildTitlesData(AppLocalizations t) {
    // Determine if we should skip labels (for daily with 24 hours)
    final shouldSkipLabels = widget.labels.length > 12;
    final skipInterval = shouldSkipLabels ? 3 : 1; // Show every 3rd label if too many
    
    return FlTitlesData(
      bottomTitles: AxisTitles(
        axisNameWidget: Text(
          t.period,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w500,
              ),
        ),
        axisNameSize: 24,
        sideTitles: SideTitles(
          showTitles: true,
          reservedSize: 40,
          getTitlesWidget: (value, meta) {
            final index = value.toInt();
            if (index < 0 || index >= widget.labels.length) {
              return const SizedBox.shrink();
            }

            // Skip labels if there are too many
            if (shouldSkipLabels && index % skipInterval != 0) {
              return const SizedBox.shrink();
            }

            return Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                widget.labels[index],
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      fontSize: 10,
                      fontWeight: FontWeight.w500,
                    ),
                textAlign: TextAlign.center,
              ),
            );
          },
        ),
      ),
      leftTitles: AxisTitles(
        axisNameWidget: Text(
          t.numberOfTrips,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w500,
                fontSize: 11,
              ),
        ),
        axisNameSize: 40,
        sideTitles: SideTitles(
          showTitles: true,
          reservedSize: 40,
          interval: _calculateHorizontalInterval(
            widget.tripCounts.reduce((a, b) => a > b ? a : b),
          ),
          getTitlesWidget: (value, meta) {
            // Only show integer values
            if (value % 1 != 0) return const SizedBox.shrink();

            return Text(
              value.toInt().toString(),
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

  double _calculateHorizontalInterval(int maxCount) {
    // Aim for about 5-6 horizontal lines
    if (maxCount <= 5) return 1;
    if (maxCount <= 10) return 2;
    if (maxCount <= 25) return 5;
    if (maxCount <= 50) return 10;
    if (maxCount <= 100) return 20;
    return 50;
  }

  double _calculateMaxYForBackground() {
    final maxCount = widget.tripCounts.reduce((a, b) => a > b ? a : b);
    return (maxCount * 1.2).ceilToDouble();
  }
}

/// A compact variant of [TripBarChart] with simplified styling.
///
/// Useful for smaller widgets or overview sections.
class TripBarChartCompact extends StatelessWidget {
  /// Creates a compact [TripBarChart] widget.
  const TripBarChartCompact({
    required this.tripCounts,
    required this.labels,
    this.barColor,
    this.height = 120,
    super.key,
  });

  /// List of trip counts for each period.
  final List<int> tripCounts;

  /// Labels for each bar.
  final List<String> labels;

  /// Color for the bars. Defaults to theme primary color.
  final Color? barColor;

  /// Height of the chart. Defaults to 120.
  final double height;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    final colorScheme = Theme.of(context).colorScheme;
    final effectiveBarColor = barColor ?? colorScheme.primary;

    // Handle empty data
    if (tripCounts.isEmpty || labels.isEmpty) {
      return SizedBox(
        height: height,
        child: Center(
          child: Text(
            t.noData,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Colors.grey[600],
                ),
          ),
        ),
      );
    }

    final maxCount = tripCounts.reduce((a, b) => a > b ? a : b);
    final yMax = (maxCount * 1.2).ceilToDouble();

    return SizedBox(
      height: height,
      child: BarChart(
        BarChartData(
          maxY: yMax,
          minY: 0,
          barTouchData: BarTouchData(enabled: false),
          titlesData: FlTitlesData(
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 24,
                getTitlesWidget: (value, meta) {
                  final index = value.toInt();
                  if (index < 0 || index >= labels.length) {
                    return const SizedBox.shrink();
                  }
                  return Text(
                    labels[index],
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          fontSize: 10,
                        ),
                  );
                },
              ),
            ),
            leftTitles: const AxisTitles(
              
            ),
            topTitles: const AxisTitles(
              
            ),
            rightTitles: const AxisTitles(
              
            ),
          ),
          borderData: FlBorderData(show: false),
          gridData: const FlGridData(show: false),
          barGroups: List.generate(
            tripCounts.length,
            (index) => BarChartGroupData(
              x: index,
              barRods: [
                BarChartRodData(
                  toY: tripCounts[index].toDouble(),
                  width: 12,
                  borderRadius: BorderRadius.circular(6),
                  gradient: LinearGradient(
                    colors: [
                      effectiveBarColor,
                      effectiveBarColor.withOpacity(0.5),
                    ],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  ),
                ),
              ],
            ),
          ),
          alignment: BarChartAlignment.spaceAround,
        ),
        swapAnimationDuration: const Duration(milliseconds: 600),
        swapAnimationCurve: Curves.easeOut,
      ),
    );
  }
}
