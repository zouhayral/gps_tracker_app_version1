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
  /// Fetches data for the current day (midnight to 23:59:59).
  ///
  /// Parameters:
  /// - [deviceId]: The ID of the device to fetch analytics for
  ///
  /// Updates state with loading, data, or error status.
  Future<void> loadDaily(int deviceId) async {
    _log.debug('Loading daily report for device $deviceId');

    // Set loading state
    state = const AsyncValue.loading();

    try {
      final date = DateTime.now();
      final report = await _repository.fetchDailyReport(date, deviceId);

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
  /// Fetches data for the last 7 days starting from 7 days ago.
  ///
  /// Parameters:
  /// - [deviceId]: The ID of the device to fetch analytics for
  ///
  /// Updates state with loading, data, or error status.
  Future<void> loadWeekly(int deviceId) async {
    _log.debug('Loading weekly report for device $deviceId');

    // Set loading state
    state = const AsyncValue.loading();

    try {
      final startDate = DateTime.now().subtract(const Duration(days: 7));
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
  /// Fetches data for the last 30 days starting from 30 days ago.
  ///
  /// Parameters:
  /// - [deviceId]: The ID of the device to fetch analytics for
  ///
  /// Updates state with loading, data, or error status.
  Future<void> loadMonthly(int deviceId) async {
    _log.debug('Loading monthly report for device $deviceId');

    // Set loading state
    state = const AsyncValue.loading();

    try {
      final startDate = DateTime.now().subtract(const Duration(days: 30));
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
  // Always fetch using explicit range to match the UI selection exactly
      final report = await _repository.fetchRangeReport(from, to, deviceId);

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
  // Re-fetch the exact same range shown in the UI for consistency
        await loadRange(deviceId, report.startTime, report.endTime);
      }
    }
  }

  /// Clears the current report state.
  void clear() {
    _log.debug('Clearing analytics state');
    state = const AsyncValue.data(null);
  }

  /// Load report for an explicit range. Convenience for UI and refresh.
  Future<void> loadRange(int deviceId, DateTime from, DateTime to) async {
    _log.debug('Loading explicit range report for device $deviceId: $from → $to');
    state = const AsyncValue.loading();
    try {
      final report = await _repository.fetchRangeReport(from, to, deviceId);
      if (!mounted) return;
      state = AsyncValue.data(report);
    } catch (e, st) {
      if (!mounted) return;
      state = AsyncValue.error(e, st);
    }
  }
}
