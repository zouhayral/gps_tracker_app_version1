import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:my_app_gps/providers/notification_providers.dart';

/// NotificationFilterBar provides severity and date filtering UI.
///
/// Features:
/// - Severity chips (High, Medium, Low) with custom colors
/// - Quick date filters (Today, Yesterday)
/// - Calendar picker for custom date range
/// - Mark all as read button
/// - Horizontal scrollable layout
class NotificationFilterBar extends ConsumerWidget {
  const NotificationFilterBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filter = ref.watch(notificationFilterProvider);

    return Container(
      color: const Color(0xFFF5FFE2), // Light green background
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Severity filters and mark all read button
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _buildSeverityChip(
                  context,
                  ref,
                  label: 'High',
                  value: 'high',
                  color: const Color(0xFFFF383C),
                  isSelected: filter.severity == 'high',
                ),
                const SizedBox(width: 8),
                _buildSeverityChip(
                  context,
                  ref,
                  label: 'Medium',
                  value: 'medium',
                  color: const Color(0xFFFFBD28),
                  isSelected: filter.severity == 'medium',
                ),
                const SizedBox(width: 8),
                _buildSeverityChip(
                  context,
                  ref,
                  label: 'Low',
                  value: 'low',
                  color: const Color(0xFF49454F),
                  isSelected: filter.severity == 'low',
                ),
                const SizedBox(width: 8),
                _buildMarkAllReadChip(context, ref),
              ],
            ),
          ),
          const SizedBox(height: 8),
          // Date filters
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _buildDateChip(
                  context,
                  ref,
                  label: 'Today',
                  date: _getToday(),
                  isSelected: _isSameDay(filter.date, _getToday()),
                ),
                const SizedBox(width: 8),
                _buildDateChip(
                  context,
                  ref,
                  label: 'Yesterday',
                  date: _getYesterday(),
                  isSelected: _isSameDay(filter.date, _getYesterday()),
                ),
                const SizedBox(width: 8),
                _buildCalendarButton(context, ref, filter),
                const SizedBox(width: 8),
                if (filter.isActive)
                  _buildClearButton(context, ref),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSeverityChip(
    BuildContext context,
    WidgetRef ref, {
    required String label,
    required String value,
    required Color color,
    required bool isSelected,
  }) {
    return FilterChip(
      label: Text(
        label,
        style: TextStyle(
          color: isSelected ? Colors.white : color,
          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
        ),
      ),
      selected: isSelected,
      onSelected: (selected) {
        final currentFilter = ref.read(notificationFilterProvider);
        if (selected) {
          // Set this severity
          ref.read(notificationFilterProvider.notifier).state =
              currentFilter.copyWith(
            severity: () => value,
          );
        } else {
          // Clear severity filter
          ref.read(notificationFilterProvider.notifier).state =
              currentFilter.copyWith(
            severity: () => null,
          );
        }
      },
      selectedColor: color,
      backgroundColor: Colors.white,
      side: BorderSide(color: color, width: 1.5),
      elevation: isSelected ? 4 : 0,
      pressElevation: 2,
    );
  }

  Widget _buildMarkAllReadChip(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    
    return InkWell(
      onTap: () async {
        // Mark all as read
        await ref.read(markAllAsReadProvider.future);
      },
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(
            color: Colors.grey.shade400,
            width: 1,
          ),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.done_all,
              size: 18,
              color: theme.colorScheme.onSurface,
            ),
            const SizedBox(width: 6),
            Text(
              'Mark all read',
              style: theme.textTheme.labelLarge?.copyWith(
                color: theme.colorScheme.onSurface,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDateChip(
    BuildContext context,
    WidgetRef ref, {
    required String label,
    required DateTime date,
    required bool isSelected,
  }) {
    final theme = Theme.of(context);
    
    return FilterChip(
      label: Text(
        label,
        style: TextStyle(
          color: isSelected ? Colors.white : theme.colorScheme.onSurface,
          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
        ),
      ),
      selected: isSelected,
      onSelected: (selected) {
        final currentFilter = ref.read(notificationFilterProvider);
        if (selected) {
          // Set this date
          ref.read(notificationFilterProvider.notifier).state =
              currentFilter.copyWith(
            date: () => date,
            dateRange: () => null, // Clear date range when selecting specific date
          );
        } else {
          // Clear date filter
          ref.read(notificationFilterProvider.notifier).state =
              currentFilter.copyWith(
            date: () => null,
          );
        }
      },
      selectedColor: theme.colorScheme.primary,
      backgroundColor: Colors.white,
      elevation: isSelected ? 4 : 0,
      pressElevation: 2,
    );
  }

  Widget _buildCalendarButton(
    BuildContext context,
    WidgetRef ref,
    NotificationFilter filter,
  ) {
    final theme = Theme.of(context);
    final hasDateRange = filter.dateRange != null;

    return ActionChip(
      label: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.calendar_month,
            size: 18,
            color: hasDateRange ? Colors.white : theme.colorScheme.primary,
          ),
          const SizedBox(width: 4),
          Text(
            hasDateRange ? 'Custom Range' : 'Calendar',
            style: TextStyle(
              color: hasDateRange ? Colors.white : theme.colorScheme.primary,
              fontWeight: hasDateRange ? FontWeight.bold : FontWeight.normal,
            ),
          ),
        ],
      ),
      onPressed: () async {
        final picked = await showDateRangePicker(
          context: context,
          firstDate: DateTime.now().subtract(const Duration(days: 365)),
          lastDate: DateTime.now(),
          initialDateRange: filter.dateRange,
        );

        if (picked != null) {
          final currentFilter = ref.read(notificationFilterProvider);
          ref.read(notificationFilterProvider.notifier).state =
              currentFilter.copyWith(
            dateRange: () => picked,
            date: () => null, // Clear single date when selecting range
          );
        }
      },
      backgroundColor: hasDateRange ? theme.colorScheme.primary : Colors.white,
      elevation: hasDateRange ? 4 : 0,
      pressElevation: 2,
    );
  }

  Widget _buildClearButton(BuildContext context, WidgetRef ref) {
    return ActionChip(
      label: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.clear, size: 18),
          SizedBox(width: 4),
          Text('Clear'),
        ],
      ),
      onPressed: () {
        ref.read(notificationFilterProvider.notifier).state =
            const NotificationFilter();
      },
      backgroundColor: Colors.white,
    );
  }

  DateTime _getToday() {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day);
  }

  DateTime _getYesterday() {
    final now = DateTime.now();
    final yesterday = now.subtract(const Duration(days: 1));
    return DateTime(yesterday.year, yesterday.month, yesterday.day);
  }

  bool _isSameDay(DateTime? date1, DateTime? date2) {
    if (date1 == null || date2 == null) return false;
    return date1.year == date2.year &&
        date1.month == date2.month &&
        date1.day == date2.day;
  }
}
