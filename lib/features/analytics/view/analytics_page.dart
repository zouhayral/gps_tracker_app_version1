import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:my_app_gps/core/utils/app_logger.dart';
import 'package:my_app_gps/features/analytics/controller/analytics_notifier.dart';
import 'package:my_app_gps/features/analytics/controller/analytics_providers.dart';
import 'package:my_app_gps/features/analytics/models/analytics_report.dart';
import 'package:my_app_gps/features/analytics/utils/analytics_pdf_generator.dart';
import 'package:my_app_gps/features/analytics/widgets/speed_chart.dart';
import 'package:my_app_gps/features/analytics/widgets/stat_card.dart';
import 'package:my_app_gps/features/analytics/widgets/trip_bar_chart.dart';
import 'package:my_app_gps/features/dashboard/controller/devices_notifier.dart';
import 'package:my_app_gps/l10n/app_localizations.dart';
import 'package:share_plus/share_plus.dart';

/// Main analytics dashboard page showing comprehensive tracker statistics.
///
/// Displays distance, speed, trips, and charts with period filtering.
class AnalyticsPage extends ConsumerStatefulWidget {
  const AnalyticsPage({super.key});

  @override
  ConsumerState<AnalyticsPage> createState() => _AnalyticsPageState();
}

class _AnalyticsPageState extends ConsumerState<AnalyticsPage> {
  String? _lastPeriod;
  int? _lastDeviceId;
  DateTime? _lastSelectedDate;
  DateTimeRange? _lastDateRange;

  @override
  void initState() {
    super.initState();
    // Auto-select first device and load report on first load
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initializeDevice();
    });
  }

  /// Initialize device selection on page load.
  /// 
  /// If a device is already selected, uses it directly.
  /// Otherwise, selects the first available device automatically.
  Future<void> _initializeDevice() async {
    final selectedDevice = ref.read(selectedDeviceIdProvider);
    
    // If device already selected, load report directly
    if (selectedDevice != null) {
      AppLogger.debug('[AnalyticsPage] Device already selected: $selectedDevice');
      _loadReport();
      return;
    }

    // Get devices from provider
    final devicesAsync = ref.read(devicesNotifierProvider);
    
    // Handle different AsyncValue states
    devicesAsync.when(
      data: (devices) {
        if (devices.isNotEmpty) {
          final firstDevice = devices.first;
          final firstDeviceId = firstDevice['id'] as int?;
          
          if (firstDeviceId != null) {
            // Auto-select first device
            ref.read(selectedDeviceIdProvider.notifier).state = firstDeviceId;
            AppLogger.debug('[AnalyticsPage] Auto-selected device ID: $firstDeviceId');
            _loadReport();
          } else {
            AppLogger.warning('[AnalyticsPage] First device has no valid ID');
          }
        } else {
          AppLogger.debug('[AnalyticsPage] No devices available for selection');
        }
      },
      loading: () {
        AppLogger.debug('[AnalyticsPage] Devices still loading, waiting...');
        // Wait for devices to load, then retry
        Future.delayed(const Duration(milliseconds: 500), () {
          if (mounted) _initializeDevice();
        });
      },
      error: (error, stackTrace) {
        AppLogger.error('[AnalyticsPage] Error loading devices: $error');
      },
    );
  }

  void _loadReport() {
    final deviceId = ref.read(selectedDeviceIdProvider);
    if (deviceId == null) {
      AppLogger.warning('No device selected for analytics');
      return;
    }

    final period = ref.read(reportPeriodProvider);
    final selectedDate = ref.read(selectedDateProvider);
    final notifier = ref.read(analyticsNotifierProvider.notifier);

    AppLogger.debug('Loading $period report for device $deviceId with date: $selectedDate');

    switch (period) {
      case 'daily':
        notifier.loadDaily(deviceId, date: selectedDate);
      case 'weekly':
        notifier.loadWeekly(deviceId, endDate: selectedDate);
      case 'monthly':
        notifier.loadMonthly(deviceId, endDate: selectedDate);
      case 'custom':
        final dateRange = ref.read(dateRangeProvider);
        if (dateRange != null) {
          notifier.loadCustomRange(
            deviceId,
            dateRange.start,
            dateRange.end,
          );
        } else {
          // Fallback to daily if custom range not set
          notifier.loadDaily(deviceId, date: selectedDate);
        }
    }
  }

  Future<void> _handleRefresh() async {
    final deviceId = ref.read(selectedDeviceIdProvider);
    if (deviceId == null) return;

    await ref.read(analyticsNotifierProvider.notifier).refresh(deviceId);
  }

  Future<void> _handleExport() async {
    final t = AppLocalizations.of(context)!;
    final state = ref.read(analyticsNotifierProvider);
    final periodLabel = ref.read(periodLabelProvider);

    // Check if we have data to export
    final report = state.value;
    if (report == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(t.noDataToExport),
            backgroundColor: Colors.orange,
          ),
        );
      }
      return;
    }

    try {
      // Show loading indicator
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                  ),
                ),
                const SizedBox(width: 16),
                Text(t.generatingPdf),
              ],
            ),
            duration: const Duration(seconds: 10),
          ),
        );
      }

      // Generate PDF
      final pdfFile = await AnalyticsPdfGenerator.generate(report, periodLabel, t);

      // Hide loading
      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
      }

      // Share the PDF
      final result = await Share.shareXFiles(
        [XFile(pdfFile.path)],
        subject: 'GPS Report - $periodLabel',
        text: '$periodLabel report generated by GPS Tracker',
      );

      // Show feedback based on share result
      if (mounted) {
        if (result.status == ShareResultStatus.success) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(t.reportSharedSuccessfully),
              backgroundColor: Colors.green,
              duration: const Duration(seconds: 2),
            ),
          );
        } else if (result.status == ShareResultStatus.dismissed) {
          // User dismissed the share dialog - no need to show error
          AppLogger.debug('[Analytics] Share dialog dismissed by user');
        }
      }
      
      AppLogger.info('[Analytics] PDF generated and shared: ${pdfFile.path}');
    } catch (e, stackTrace) {
      AppLogger.error('[Analytics] PDF share failed', error: e, stackTrace: stackTrace);
      
      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${t.errorSharingReport}: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  Future<void> _selectCustomDateRange() async {
    final currentRange = ref.read(dateRangeProvider);
    final initialRange = currentRange ??
        DateTimeRange(
          start: DateTime.now().subtract(const Duration(days: 7)),
          end: DateTime.now(),
        );

    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now(),
      initialDateRange: initialRange,
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: Theme.of(context).colorScheme.copyWith(
                  primary: const Color(0xFFb4e15c),
                ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      ref.read(dateRangeProvider.notifier).state = picked;
      _loadReport();
    }
  }

  Future<void> _selectSingleDate() async {
    final currentDate = ref.read(selectedDateProvider) ?? DateTime.now();

    final picked = await showDatePicker(
      context: context,
      initialDate: currentDate,
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now(),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: Theme.of(context).colorScheme.copyWith(
                  primary: const Color(0xFFb4e15c),
                ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      ref.read(selectedDateProvider.notifier).state = picked;
      // No need to call _loadReport() as the listener will trigger it
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    final colorScheme = Theme.of(context).colorScheme;

    // Check if key values changed and reload
    final currentPeriod = ref.watch(reportPeriodProvider);
    final currentDeviceId = ref.watch(selectedDeviceIdProvider);
    final currentDate = ref.watch(selectedDateProvider);
    final currentDateRange = ref.watch(dateRangeProvider);

    // Trigger reload if values changed
    if (_lastPeriod != null && _lastPeriod != currentPeriod) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _loadReport());
    }
    if (_lastDeviceId != null && _lastDeviceId != currentDeviceId && currentDeviceId != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _loadReport());
    }
    if (_lastSelectedDate != currentDate) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _loadReport());
    }
    if (_lastDateRange != currentDateRange) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _loadReport());
    }

    // Update last values
    _lastPeriod = currentPeriod;
    _lastDeviceId = currentDeviceId;
    _lastSelectedDate = currentDate;
    _lastDateRange = currentDateRange;

    return Scaffold(
      appBar: AppBar(
        title: Text(t.reportsTitle),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: t.refresh,
            onPressed: _handleRefresh,
          ),
          IconButton(
            icon: const Icon(Icons.picture_as_pdf_outlined),
            tooltip: t.exportShareReport,
            onPressed: _handleExport,
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _handleRefresh,
        color: const Color(0xFFb4e15c),
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildFilters(colorScheme),
              const SizedBox(height: 16),
              _buildBody(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFilters(ColorScheme colorScheme) {
    final t = AppLocalizations.of(context)!;
    final period = ref.watch(reportPeriodProvider);
    final periodLabel = ref.watch(periodLabelProvider);
    final deviceId = ref.watch(selectedDeviceIdProvider);

    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Period Selector
            Text(
              t.period,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 12),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SegmentedButton<String>(
                segments: [
                  ButtonSegment(
                    value: 'daily',
                    label: Text(t.day, style: const TextStyle(fontSize: 13)),
                    icon: const Icon(Icons.today, size: 16),
                  ),
                  ButtonSegment(
                    value: 'weekly',
                    label: Text(t.week, style: const TextStyle(fontSize: 13)),
                    icon: const Icon(Icons.view_week, size: 16),
                  ),
                  ButtonSegment(
                    value: 'monthly',
                    label: Text(t.month, style: const TextStyle(fontSize: 13)),
                    icon: const Icon(Icons.calendar_month, size: 16),
                  ),
                  ButtonSegment(
                    value: 'custom',
                    label: Text(t.custom, style: const TextStyle(fontSize: 12)),
                    icon: const Icon(Icons.date_range, size: 16),
                  ),
                ],
                selected: {period},
                onSelectionChanged: (Set<String> selected) {
                  final newPeriod = selected.first;
                  ref.read(reportPeriodProvider.notifier).state = newPeriod;
                  
                  // Show date picker for custom period
                  if (newPeriod == 'custom') {
                    Future.microtask(_selectCustomDateRange);
                  }
                },
                style: ButtonStyle(
                  backgroundColor: WidgetStateProperty.resolveWith((states) {
                    if (states.contains(WidgetState.selected)) {
                      return const Color(0xFFb4e15c);
                    }
                    return null;
                  }),
                  foregroundColor: WidgetStateProperty.resolveWith((states) {
                    if (states.contains(WidgetState.selected)) {
                      return Colors.black87;
                    }
                    return null;
                  }),
                  padding: WidgetStateProperty.all(
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            
            // Period label with date range
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.calendar_today,
                    size: 16,
                    color: colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      periodLabel,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                    ),
                  ),
                  // Show edit button for all periods
                  IconButton(
                    icon: const Icon(Icons.edit_calendar, size: 16),
                    onPressed: period == 'custom' 
                      ? _selectCustomDateRange 
                      : _selectSingleDate,
                    tooltip: period == 'custom' ? t.editPeriod : 'Select date',
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ],
              ),
            ),

            // Device selector
            const SizedBox(height: 16),
            _buildDeviceSelector(context, deviceId),
          ],
        ),
      ),
    );
  }

  Widget _buildDeviceSelector(BuildContext context, int? currentDeviceId) {
    final t = AppLocalizations.of(context)!;
    final devicesAsync = ref.watch(devicesNotifierProvider);

    return devicesAsync.when(
      data: (devices) {
        if (devices.isEmpty) {
            return Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.orange.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.orange.withValues(alpha: 0.3)),
            ),
            child: Row(
              children: [
                Icon(Icons.warning_amber, color: Colors.orange[700]),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(t.noDevicesAvailable),
                ),
              ],
            ),
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              t.device,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<int>(
              initialValue: currentDeviceId,
              decoration: InputDecoration(
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 12,
                ),
                prefixIcon: const Icon(Icons.devices),
              ),
              hint: Text(t.selectDevice),
              items: devices.map((device) {
                final id = device['id'] as int?;
                final name = device['name'] as String? ?? 'Device $id';
                return DropdownMenuItem<int>(
                  value: id,
                  child: Text(name),
                );
              }).toList(),
              onChanged: (int? newDeviceId) {
                if (newDeviceId != null) {
                  ref.read(selectedDeviceIdProvider.notifier).state = newDeviceId;
                }
              },
            ),
          ],
        );
      },
      loading: () => const Center(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: CircularProgressIndicator(),
        ),
      ),
      error: (error, stack) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.red.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
        ),
        child: Row(
          children: [
            const Icon(Icons.error_outline, color: Colors.red),
            const SizedBox(width: 12),
            Expanded(
              child: Text('Loading error: $error'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody() {
    final t = AppLocalizations.of(context)!;
    final state = ref.watch(analyticsNotifierProvider);
    final deviceId = ref.watch(selectedDeviceIdProvider);

    // Handle no device selected
    if (deviceId == null) {
      return _buildEmptyState(
        icon: Icons.devices_other,
        message: t.pleaseSelectDevice,
        subtitle: t.noDeviceSelected,
      );
    }

    return state.when(
      loading: () => SizedBox(
        height: 400,
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const CircularProgressIndicator(
                color: Color(0xFFb4e15c),
              ),
              const SizedBox(height: 16),
              Text(t.loadingStatistics),
            ],
          ),
        ),
      ),
      error: (error, stackTrace) {
        AppLogger.error('Analytics error: $error', stackTrace: stackTrace);
        return _buildEmptyState(
          icon: Icons.error_outline,
          message: t.loadingError,
          subtitle: error.toString(),
          action: ElevatedButton.icon(
            onPressed: _loadReport,
            icon: const Icon(Icons.refresh),
            label: Text(t.retry),
          ),
        );
      },
      data: (report) {
        if (report == null) {
          return _buildEmptyState(
            icon: Icons.analytics_outlined,
            message: t.noData,
            subtitle: t.noTripsRecorded,
          );
        }
        return _buildReportContent(report);
      },
    );
  }

  Widget _buildEmptyState({
    required IconData icon,
    required String message,
    String? subtitle,
    Widget? action,
  }) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 80,
              color: Colors.grey[400],
            ),
            const SizedBox(height: 16),
            Text(
              message,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    color: Colors.grey[700],
                  ),
              textAlign: TextAlign.center,
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 8),
              Text(
                subtitle,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Colors.grey[600],
                    ),
                textAlign: TextAlign.center,
              ),
            ],
            if (action != null) ...[
              const SizedBox(height: 24),
              action,
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildReportContent(AnalyticsReport report) {
    final t = AppLocalizations.of(context)!;
    final period = ref.watch(reportPeriodProvider);
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Summary Stats Grid
        LayoutBuilder(
          builder: (context, constraints) {
            // Calculate responsive grid properties
            final screenWidth = constraints.maxWidth;
            final isTablet = screenWidth > 600;
            final crossAxisCount = isTablet ? 4 : 2;
            final aspectRatio = isTablet ? 1.1 : 1.05;
            
            return GridView.count(
              crossAxisCount: crossAxisCount,
              childAspectRatio: aspectRatio,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 16,
              crossAxisSpacing: 16,
              children: [
                StatCardVertical(
                  title: t.distance,
                  value: '${report.totalDistanceKm.toStringAsFixed(1)} km',
                  icon: Icons.route,
                  color: const Color(0xFFb4e15c),
                ),
                StatCardVertical(
                  title: t.avgSpeed,
                  value: '${report.avgSpeed.toStringAsFixed(1)} km/h',
                  icon: Icons.speed,
                  color: const Color(0xFF4A90E2),
                ),
                StatCardVertical(
                  title: t.maxSpeed,
                  value: '${report.maxSpeed.toStringAsFixed(1)} km/h',
                  icon: Icons.flash_on,
                  color: const Color(0xFFFF9F43),
                ),
                StatCardVertical(
                  title: t.trips,
                  value: report.tripCount.toString(),
                  icon: Icons.directions_car,
                  color: const Color(0xFF9B59B6),
                ),
              ],
            );
          },
        ),

        // Fuel card if available
        if (report.fuelUsed != null && report.fuelUsed! > 0) ...[
          const SizedBox(height: 16),
          StatCard(
            title: t.fuelUsed,
            value: '${report.fuelUsed!.toStringAsFixed(2)} L',
            icon: Icons.local_gas_station,
            color: const Color(0xFFE74C3C),
          ),
        ],

        const SizedBox(height: 28),
        Divider(color: Colors.grey[300], thickness: 1),
        const SizedBox(height: 28),

        // Speed Chart Section
        _buildChartSection(
          title: t.speedEvolution,
          icon: Icons.show_chart,
          child: SpeedChart(
            speedData: _generateSpeedData(period, report),
            timestamps: _generateTimestamps(period, report),
            lineColor: const Color(0xFFb4e15c),
            height: 220,
          ),
        ),

        const SizedBox(height: 24),

        // Trip Bar Chart Section
        _buildChartSection(
          title: t.tripDistribution,
          icon: Icons.bar_chart,
          child: TripBarChart(
            tripCounts: _generateTripCounts(period, report),
            labels: _generateTripLabels(period),
            barColor: const Color(0xFFb4e15c),
            height: 220,
          ),
        ),

        const SizedBox(height: 24),

        // Summary Info Card
        _buildSummaryCard(report),

        const SizedBox(height: 16),
      ],
    );
  }

  Widget _buildChartSection({
    required String title,
    required IconData icon,
    required Widget child,
  }) {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 20, color: const Color(0xFFb4e15c)),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            child,
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryCard(AnalyticsReport report) {
    final t = AppLocalizations.of(context)!;
    final dateFormat = DateFormat('dd/MM/yyyy HH:mm');
    
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.info_outline,
                  size: 20,
                  color: Color(0xFFb4e15c),
                ),
                const SizedBox(width: 8),
                Text(
                  t.periodSummary,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _buildInfoRow(
              t.start,
              dateFormat.format(report.startTime),
              Icons.play_arrow,
            ),
            const SizedBox(height: 8),
            _buildInfoRow(
              t.end,
              dateFormat.format(report.endTime),
              Icons.stop,
            ),
            const SizedBox(height: 8),
            _buildInfoRow(
              t.duration,
              _formatDuration(report.endTime.difference(report.startTime)),
              Icons.timer,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value, IconData icon) {
    return Row(
      children: [
        Icon(icon, size: 16, color: Colors.grey[600]),
        const SizedBox(width: 8),
        Text(
          '$label:',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Colors.grey[600],
              ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            value,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w500,
                ),
            textAlign: TextAlign.right,
          ),
        ),
      ],
    );
  }

  String _formatDuration(Duration duration) {
    if (duration.inDays > 0) {
      return '${duration.inDays}j ${duration.inHours % 24}h';
    } else if (duration.inHours > 0) {
      return '${duration.inHours}h ${duration.inMinutes % 60}min';
    } else {
      return '${duration.inMinutes}min';
    }
  }

  // Mock data generators (replace with real data from API in future)
  List<double> _generateSpeedData(String period, AnalyticsReport report) {
  // TODO(owner): Replace with actual speed data from positions API
    // For now, generate sample data based on avg/max speed
    final avgSpeed = report.avgSpeed;
    final maxSpeed = report.maxSpeed;
    
    int dataPoints;
    switch (period) {
      case 'daily':
        dataPoints = 24; // Hourly
      case 'weekly':
        dataPoints = 7; // Daily
      case 'monthly':
        dataPoints = 30; // Daily
      default:
        dataPoints = 10;
    }

    return List.generate(dataPoints, (i) {
      final variation = (i % 3) * 5.0;
      return (avgSpeed + variation).clamp(0.0, maxSpeed);
    });
  }

  List<DateTime> _generateTimestamps(String period, AnalyticsReport report) {
    final end = report.endTime;
    int dataPoints;
    Duration interval;

    switch (period) {
      case 'daily':
        dataPoints = 24;
        interval = const Duration(hours: 1);
      case 'weekly':
        dataPoints = 7;
        interval = const Duration(days: 1);
      case 'monthly':
        dataPoints = 30;
        interval = const Duration(days: 1);
      default:
        dataPoints = 10;
        interval = Duration(
          milliseconds: report.endTime
                  .difference(report.startTime)
                  .inMilliseconds ~/
              dataPoints,
        );
    }

    return List.generate(
      dataPoints,
      (i) => end.subtract(interval * (dataPoints - 1 - i)),
    );
  }

  List<int> _generateTripCounts(String period, AnalyticsReport report) {
  // TODO(owner): Replace with actual trip distribution data
    final totalTrips = report.tripCount;
    
    int bars;
    switch (period) {
      case 'daily':
        bars = 24; // Hourly
      case 'weekly':
        bars = 7; // Daily
      case 'monthly':
        bars = 4; // Weekly
      default:
        bars = 7;
    }

    if (totalTrips == 0) {
      return List.filled(bars, 0);
    }

    // Distribute trips across bars (mock distribution)
    final avgPerBar = totalTrips / bars;
    return List.generate(bars, (i) {
      final variation = i.isEven ? 1 : -1;
      return (avgPerBar + variation).round().clamp(0, totalTrips);
    });
  }

  List<String> _generateTripLabels(String period) {
    switch (period) {
      case 'daily':
        // Hourly labels (0h, 4h, 8h, ...)
        return List.generate(24, (i) => '${i}h');
      case 'weekly':
        return ['Lun', 'Mar', 'Mer', 'Jeu', 'Ven', 'Sam', 'Dim'];
      case 'monthly':
        return ['Sem 1', 'Sem 2', 'Sem 3', 'Sem 4'];
      default:
        return List.generate(7, (i) => 'J${i + 1}');
    }
  }
}
