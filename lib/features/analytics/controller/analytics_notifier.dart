import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_app_gps/core/utils/app_logger.dart';
import 'package:my_app_gps/features/analytics/data/analytics_repository.dart';
import 'package:my_app_gps/features/analytics/models/analytics_report.dart';

/// Provider for the analytics notifier.
///
/// Manages the state of analytics reports and provides methods to load
/// daily, weekly, and monthly reports for a specific device.
final analyticsNotifierProvider =
    StateNotifierProvider<AnalyticsNotifier, AsyncValue<AnalyticsReport?>>(
  (ref) => AnalyticsNotifier(ref.read(analyticsRepositoryProvider)),
);

/// Notifier for managing analytics report state.
///
/// Handles fetching and updating analytics data for different time periods
/// (daily, weekly, monthly) and manages loading/error states for the UI.
class AnalyticsNotifier extends StateNotifier<AsyncValue<AnalyticsReport?>> {
  static final _log = 'AnalyticsNotifier'.logger;

  AnalyticsNotifier(this._repository) : super(const AsyncValue.data(null));

  final AnalyticsRepository _repository;

  /// Loads daily analytics report for the specified device.
  ///
  /// Fetches data for the specified date (midnight to 23:59:59).
  /// If no date is specified, uses the current day.
  ///
  /// Parameters:
  /// - [deviceId]: The ID of the device to fetch analytics for
  /// - [date]: Optional specific date to fetch. Defaults to today.
  ///
  /// Updates state with loading, data, or error status.
  Future<void> loadDaily(int deviceId, {DateTime? date}) async {
    final targetDate = date ?? DateTime.now();
    _log.debug('Loading daily report for device $deviceId on ${_formatDate(targetDate)}');

    // Set loading state
    state = const AsyncValue.loading();

    try {
      final report = await _repository.fetchDailyReport(targetDate, deviceId);

      // Check if still mounted before updating state
      if (!mounted) {
        _log.debug('loadDaily cancelled: notifier disposed');
        return;
      }

      state = AsyncValue.data(report);
      
      _log.debug(
        'Daily report loaded: ${report.totalDistanceKm} km, '
        '${report.tripCount} trips',
      );
    } catch (e, st) {
      _log.error(
        'Failed to load daily report for device $deviceId',
        error: e,
        stackTrace: st,
      );

      if (!mounted) {
        _log.debug('loadDaily error handling cancelled: notifier disposed');
        return;
      }

      state = AsyncValue.error(e, st);
    }
  }

  /// Loads weekly analytics report for the specified device.
  ///
  /// Fetches data for 7 days ending on the specified date.
  /// If no date is specified, uses the current date.
  ///
  /// Parameters:
  /// - [deviceId]: The ID of the device to fetch analytics for
  /// - [endDate]: Optional end date for the week. Defaults to today.
  ///
  /// Updates state with loading, data, or error status.
  Future<void> loadWeekly(int deviceId, {DateTime? endDate}) async {
    final targetDate = endDate ?? DateTime.now();
    _log.debug('Loading weekly report for device $deviceId ending ${_formatDate(targetDate)}');

    // Set loading state
    state = const AsyncValue.loading();

    try {
      final startDate = targetDate.subtract(const Duration(days: 7));
      final report = await _repository.fetchWeeklyReport(startDate, deviceId);

      // Check if still mounted before updating state
      if (!mounted) {
        _log.debug('loadWeekly cancelled: notifier disposed');
        return;
      }

      state = AsyncValue.data(report);
      
      _log.debug(
        'Weekly report loaded: ${report.totalDistanceKm} km, '
        '${report.tripCount} trips',
      );
    } catch (e, st) {
      _log.error(
        'Failed to load weekly report for device $deviceId',
        error: e,
        stackTrace: st,
      );

      if (!mounted) {
        _log.debug('loadWeekly error handling cancelled: notifier disposed');
        return;
      }

      state = AsyncValue.error(e, st);
    }
  }

  /// Loads monthly analytics report for the specified device.
  ///
  /// Fetches data for 30 days ending on the specified date.
  /// If no date is specified, uses the current date.
  ///
  /// Parameters:
  /// - [deviceId]: The ID of the device to fetch analytics for
  /// - [endDate]: Optional end date for the month. Defaults to today.
  ///
  /// Updates state with loading, data, or error status.
  Future<void> loadMonthly(int deviceId, {DateTime? endDate}) async {
    final targetDate = endDate ?? DateTime.now();
    _log.debug('Loading monthly report for device $deviceId ending ${_formatDate(targetDate)}');

    // Set loading state
    state = const AsyncValue.loading();

    try {
      final startDate = targetDate.subtract(const Duration(days: 30));
      final report = await _repository.fetchMonthlyReport(startDate, deviceId);

      // Check if still mounted before updating state
      if (!mounted) {
        _log.debug('loadMonthly cancelled: notifier disposed');
        return;
      }

      state = AsyncValue.data(report);
      
      _log.debug(
        'Monthly report loaded: ${report.totalDistanceKm} km, '
        '${report.tripCount} trips',
      );
    } catch (e, st) {
      _log.error(
        'Failed to load monthly report for device $deviceId',
        error: e,
        stackTrace: st,
      );

      if (!mounted) {
        _log.debug('loadMonthly error handling cancelled: notifier disposed');
        return;
      }

      state = AsyncValue.error(e, st);
    }
  }

  /// Helper to format date for logging
  String _formatDate(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }

  /// Loads analytics report for a custom date range.
  ///
  /// Useful for user-selected date ranges in the UI.
  ///
  /// Parameters:
  /// - [deviceId]: The ID of the device to fetch analytics for
  /// - [from]: Start date of the period
  /// - [to]: End date of the period
  ///
  /// Updates state with loading, data, or error status.
  Future<void> loadCustomRange(
    int deviceId,
    DateTime from,
    DateTime to,
  ) async {
    _log.debug(
      'Loading custom range report for device $deviceId: $from to $to',
    );

    // Set loading state
    state = const AsyncValue.loading();

    try {
      // Ensure 'from' starts at beginning of day and 'to' ends at end of day
      final adjustedFrom = DateTime(from.year, from.month, from.day);
      final adjustedTo = DateTime(to.year, to.month, to.day, 23, 59, 59);
      
      _log.debug(
        'Adjusted custom range: $adjustedFrom to $adjustedTo',
      );
      
      // Fetch the report for the custom date range
      final report = await _repository.fetchCustomReport(
        adjustedFrom,
        adjustedTo,
        deviceId,
      );

      // Check if still mounted before updating state
      if (!mounted) {
        _log.debug('loadCustomRange cancelled: notifier disposed');
        return;
      }

      state = AsyncValue.data(report);
      
      _log.debug(
        'Custom range report loaded: ${report.totalDistanceKm} km, '
        '${report.tripCount} trips',
      );
    } catch (e, st) {
      _log.error(
        'Failed to load custom range report for device $deviceId',
        error: e,
        stackTrace: st,
      );

      if (!mounted) {
        _log.debug('loadCustomRange error handling cancelled: notifier disposed');
        return;
      }

      state = AsyncValue.error(e, st);
    }
  }

  /// Refreshes the current report.
  ///
  /// Reloads the last fetched report type. Useful for pull-to-refresh.
  Future<void> refresh(int deviceId) async {
    _log.debug('Refreshing report for device $deviceId');

    final currentState = state;
    if (currentState is AsyncData<AnalyticsReport?>) {
      final report = currentState.value;
      if (report != null) {
        // Determine which period to reload based on the current report's date range
        final daysDifference = report.endTime.difference(report.startTime).inDays;
        
        if (daysDifference <= 1) {
          await loadDaily(deviceId);
        } else if (daysDifference <= 7) {
          await loadWeekly(deviceId);
        } else {
          await loadMonthly(deviceId);
        }
      }
    }
  }

  /// Clears the current report state.
  void clear() {
    _log.debug('Clearing analytics state');
    state = const AsyncValue.data(null);
  }
}
