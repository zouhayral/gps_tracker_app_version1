import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Provider for the currently selected report period.
///
/// Controls which time range of analytics data to display.
/// Valid values: 'daily', 'weekly', 'monthly', 'custom'
///
/// Default: 'daily' (shows today's statistics)
///
/// Example usage:
/// ```dart
/// final period = ref.watch(reportPeriodProvider);
/// ref.read(reportPeriodProvider.notifier).state = 'weekly';
/// ```
final reportPeriodProvider = StateProvider<String>((ref) => 'daily');

/// Provider for the currently selected device ID.
///
/// Determines which device's analytics data to fetch and display.
/// When null, the UI should either:
/// - Show a device selector prompt
/// - Default to the first available device
/// - Use the currently active device from the map
///
/// Example usage:
/// ```dart
/// final deviceId = ref.watch(selectedDeviceIdProvider);
/// if (deviceId != null) {
///   // Fetch analytics for this device
/// }
/// 
/// // Update selected device
/// ref.read(selectedDeviceIdProvider.notifier).state = 123;
/// ```
final selectedDeviceIdProvider = StateProvider<int?>((ref) => null);

/// Provider for a custom date range selection.
///
/// Used when the user selects 'custom' period and picks a specific
/// date range using a date range picker.
///
/// When null, indicates no custom range is selected.
/// When the period is 'daily', 'weekly', or 'monthly', this value
/// should be null as those periods are calculated automatically.
///
/// Example usage:
/// ```dart
/// final range = ref.watch(dateRangeProvider);
/// if (range != null) {
///   // Fetch analytics for custom range
///   print('From: ${range.start}, To: ${range.end}');
/// }
/// 
/// // Update date range from date picker
/// ref.read(dateRangeProvider.notifier).state = DateTimeRange(
///   start: DateTime(2025, 1, 1),
///   end: DateTime(2025, 1, 31),
/// );
/// ```
final dateRangeProvider = StateProvider<DateTimeRange?>((ref) => null);

/// Provider that computes the effective date range based on the selected period.
///
/// Returns a [DateTimeRange] based on:
/// - 'daily': Today (midnight to 23:59:59)
/// - 'weekly': Last 7 days
/// - 'monthly': Last 30 days
/// - 'custom': Uses [dateRangeProvider] value
///
/// This computed provider makes it easy for UI components to get the
/// current date range without having to recalculate it everywhere.
///
/// Example usage:
/// ```dart
/// final effectiveRange = ref.watch(effectiveDateRangeProvider);
/// if (effectiveRange != null) {
///   Text('Showing data from ${effectiveRange.start} to ${effectiveRange.end}');
/// }
/// ```
final effectiveDateRangeProvider = Provider<DateTimeRange?>((ref) {
  final period = ref.watch(reportPeriodProvider);
  final customRange = ref.watch(dateRangeProvider);

  final now = DateTime.now();

  switch (period) {
    case 'daily':
      final startOfDay = DateTime(now.year, now.month, now.day);
      final endOfDay = DateTime(now.year, now.month, now.day, 23, 59, 59);
      return DateTimeRange(start: startOfDay, end: endOfDay);

    case 'weekly':
      final startOfWeek = now.subtract(const Duration(days: 7));
      return DateTimeRange(start: startOfWeek, end: now);

    case 'monthly':
      final startOfMonth = now.subtract(const Duration(days: 30));
      return DateTimeRange(start: startOfMonth, end: now);

    case 'custom':
      return customRange;

    default:
      // Fallback to daily if unknown period
      final startOfDay = DateTime(now.year, now.month, now.day);
      final endOfDay = DateTime(now.year, now.month, now.day, 23, 59, 59);
      return DateTimeRange(start: startOfDay, end: endOfDay);
  }
});

/// Provider that determines if a custom date range is required.
///
/// Returns true when the selected period is 'custom' but no date range
/// has been selected yet, indicating the UI should prompt the user to
/// select a date range.
///
/// Example usage:
/// ```dart
/// final needsDatePicker = ref.watch(needsCustomRangeProvider);
/// if (needsDatePicker) {
///   // Show date picker dialog
///   showDateRangePicker(context: context);
/// }
/// ```
final needsCustomRangeProvider = Provider<bool>((ref) {
  final period = ref.watch(reportPeriodProvider);
  final customRange = ref.watch(dateRangeProvider);

  return period == 'custom' && customRange == null;
});

/// Provider that returns a human-readable label for the current period.
///
/// Useful for displaying in UI headers, titles, or summaries.
///
/// Example usage:
/// ```dart
/// final label = ref.watch(periodLabelProvider);
/// Text('Analytics Report: $label');
/// ```
final periodLabelProvider = Provider<String>((ref) {
  final period = ref.watch(reportPeriodProvider);
  final customRange = ref.watch(dateRangeProvider);

  switch (period) {
    case 'daily':
      return 'Today';
    case 'weekly':
      return 'Last 7 Days';
    case 'monthly':
      return 'Last 30 Days';
    case 'custom':
      if (customRange != null) {
        final start = customRange.start;
        final end = customRange.end;
        return '${_formatDate(start)} - ${_formatDate(end)}';
      }
      return 'Custom Range';
    default:
      return 'Unknown Period';
  }
});

/// Helper function to format date for display.
String _formatDate(DateTime date) {
  return '${date.day}/${date.month}/${date.year}';
}
