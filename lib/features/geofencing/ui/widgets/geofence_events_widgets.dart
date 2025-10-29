import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:my_app_gps/features/geofencing/providers/geofence_events_filter_providers.dart';

/// Date range picker widget for geofence events filtering
class EventDateRangePicker extends ConsumerWidget {
  const EventDateRangePicker({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filterState = ref.watch(geofenceEventsFilterProvider);
    final filterNotifier = ref.read(geofenceEventsFilterProvider.notifier);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'Date Range',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          icon: const Icon(Icons.date_range),
          label: Text(
            filterState.dateRange == null
                ? 'Select Date Range'
                : '${DateFormat('MMM d, y').format(filterState.dateRange!.start)} - '
                    '${DateFormat('MMM d, y').format(filterState.dateRange!.end)}',
          ),
          onPressed: () async {
            final range = await showDateRangePicker(
              context: context,
              firstDate: DateTime.now().subtract(const Duration(days: 365)),
              lastDate: DateTime.now(),
              initialDateRange: filterState.dateRange,
            );
            if (range != null) {
              filterNotifier.setDateRange(range);
            }
          },
        ),
        if (filterState.dateRange != null)
          TextButton.icon(
            icon: const Icon(Icons.clear),
            label: const Text('Clear Date Range'),
            onPressed: () => filterNotifier.clearDateRange(),
          ),
      ],
    );
  }
}

/// Event type filter toggle widget
class EventTypeFilterToggle extends ConsumerWidget {
  const EventTypeFilterToggle({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filterState = ref.watch(geofenceEventsFilterProvider);
    final filterNotifier = ref.read(geofenceEventsFilterProvider.notifier);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'Event Type',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          children: [
            FilterChip(
              label: const Text('Entry'),
              avatar: const Icon(Icons.login, size: 16),
              selected: filterState.selectedEventTypes.contains('entry'),
              onSelected: (_) => filterNotifier.toggleEventType('entry'),
            ),
            FilterChip(
              label: const Text('Exit'),
              avatar: const Icon(Icons.logout, size: 16),
              selected: filterState.selectedEventTypes.contains('exit'),
              onSelected: (_) => filterNotifier.toggleEventType('exit'),
            ),
            FilterChip(
              label: const Text('Dwell'),
              avatar: const Icon(Icons.schedule, size: 16),
              selected: filterState.selectedEventTypes.contains('dwell'),
              onSelected: (_) => filterNotifier.toggleEventType('dwell'),
            ),
          ],
        ),
      ],
    );
  }
}

/// Status filter toggle widget
class StatusFilterToggle extends ConsumerWidget {
  const StatusFilterToggle({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filterState = ref.watch(geofenceEventsFilterProvider);
    final filterNotifier = ref.read(geofenceEventsFilterProvider.notifier);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'Status',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          children: [
            FilterChip(
              label: const Text('Pending'),
              avatar: const Icon(Icons.pending, size: 16),
              selected: filterState.selectedStatuses.contains('pending'),
              onSelected: (_) => filterNotifier.toggleStatus('pending'),
            ),
            FilterChip(
              label: const Text('Acknowledged'),
              avatar: const Icon(Icons.check_circle, size: 16),
              selected: filterState.selectedStatuses.contains('acknowledged'),
              onSelected: (_) => filterNotifier.toggleStatus('acknowledged'),
            ),
            FilterChip(
              label: const Text('Archived'),
              avatar: const Icon(Icons.archive, size: 16),
              selected: filterState.selectedStatuses.contains('archived'),
              onSelected: (_) => filterNotifier.toggleStatus('archived'),
            ),
          ],
        ),
      ],
    );
  }
}

/// Device filter selector widget
class DeviceFilterSelector extends ConsumerWidget {
  const DeviceFilterSelector({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filterState = ref.watch(geofenceEventsFilterProvider);
    final filterNotifier = ref.read(geofenceEventsFilterProvider.notifier);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'Device',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          value: filterState.selectedDevice,
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            hintText: 'All Devices',
          ),
          items: const [
            DropdownMenuItem(
              child: Text('All Devices'),
            ),
            DropdownMenuItem(
              value: 'Device-1',
              child: Text('Device-1'),
            ),
            DropdownMenuItem(
              value: 'Device-2',
              child: Text('Device-2'),
            ),
            DropdownMenuItem(
              value: 'Device-3',
              child: Text('Device-3'),
            ),
          ],
          onChanged: (value) => filterNotifier.setDevice(value),
        ),
      ],
    );
  }
}

/// Active filter chips display widget
class ActiveFilterChips extends ConsumerWidget {
  const ActiveFilterChips({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filterState = ref.watch(geofenceEventsFilterProvider);
    final filterNotifier = ref.read(geofenceEventsFilterProvider.notifier);
    final theme = Theme.of(context);

    if (!filterState.hasActiveFilters()) {
      return const SizedBox.shrink();
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(
          bottom: BorderSide(
            color: theme.colorScheme.outline.withValues(alpha: 0.2),
          ),
        ),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            // Event type chips (show only if filtered)
            if (filterState.selectedEventTypes.length < 3)
              ...filterState.selectedEventTypes.map((type) {
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Chip(
                    avatar: Icon(
                      _getEventTypeIcon(type),
                      size: 16,
                    ),
                    label: Text(_capitalizeFirst(type)),
                    deleteIcon: const Icon(Icons.close, size: 16),
                    onDeleted: () => filterNotifier.removeEventType(type),
                  ),
                );
              }),

            // Status chips (show only if filtered)
            if (filterState.selectedStatuses.length < 2)
              ...filterState.selectedStatuses.map((status) {
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Chip(
                    avatar: Icon(
                      _getStatusIcon(status),
                      size: 16,
                    ),
                    label: Text(_capitalizeFirst(status)),
                    deleteIcon: const Icon(Icons.close, size: 16),
                    onDeleted: () => filterNotifier.removeStatus(status),
                  ),
                );
              }),

            // Device chip
            if (filterState.selectedDevice != null)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Chip(
                  avatar: const Icon(Icons.smartphone, size: 16),
                  label: Text(filterState.selectedDevice!),
                  deleteIcon: const Icon(Icons.close, size: 16),
                  onDeleted: () => filterNotifier.clearDevice(),
                ),
              ),

            // Date range chip
            if (filterState.dateRange != null)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Chip(
                  avatar: const Icon(Icons.date_range, size: 16),
                  label: Text(
                    '${DateFormat('MMM d').format(filterState.dateRange!.start)} - '
                    '${DateFormat('MMM d').format(filterState.dateRange!.end)}',
                  ),
                  deleteIcon: const Icon(Icons.close, size: 16),
                  onDeleted: () => filterNotifier.clearDateRange(),
                ),
              ),

            // Clear all button
            TextButton.icon(
              icon: const Icon(Icons.clear_all, size: 16),
              label: const Text('Clear'),
              onPressed: () => filterNotifier.clearAll(),
            ),
          ],
        ),
      ),
    );
  }

  IconData _getEventTypeIcon(String type) {
    switch (type) {
      case 'entry':
        return Icons.login;
      case 'exit':
        return Icons.logout;
      case 'dwell':
        return Icons.schedule;
      default:
        return Icons.notifications;
    }
  }

  IconData _getStatusIcon(String status) {
    switch (status) {
      case 'pending':
        return Icons.pending;
      case 'acknowledged':
        return Icons.check_circle;
      case 'archived':
        return Icons.archive;
      default:
        return Icons.circle;
    }
  }

  String _capitalizeFirst(String text) {
    if (text.isEmpty) return text;
    return text[0].toUpperCase() + text.substring(1);
  }
}

/// Statistics bar showing event counts and sort info
class EventStatisticsBar extends ConsumerWidget {
  final int unacknowledgedCount;

  const EventStatisticsBar({
    required this.unacknowledgedCount,
    super.key,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filterState = ref.watch(geofenceEventsFilterProvider);
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        border: Border(
          bottom: BorderSide(
            color: theme.colorScheme.outline.withValues(alpha: 0.2),
          ),
        ),
      ),
      child: Row(
        children: [
          Icon(
            Icons.notifications_active,
            size: 16,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 8),
          Text(
            '$unacknowledgedCount unacknowledged',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w500,
            ),
          ),
          const Spacer(),
          Text(
            'Sort: ${filterState.sortBy.toUpperCase()}',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
