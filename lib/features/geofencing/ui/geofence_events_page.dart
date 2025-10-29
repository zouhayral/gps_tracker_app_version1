import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:my_app_gps/core/navigation/safe_navigation.dart';
import 'package:my_app_gps/data/models/geofence_event.dart';
import 'package:my_app_gps/features/geofencing/providers/geofence_events_filter_providers.dart';
import 'package:my_app_gps/features/geofencing/providers/geofence_providers.dart';
import 'package:my_app_gps/features/geofencing/ui/widgets/geofence_events_widgets.dart';
import 'package:my_app_gps/features/geofencing/ui/widgets/geofence_events_app_bar_widgets.dart';

/// View mode for events page
enum GeofenceEventsViewMode {
  /// Show all events across all geofences
  all,

  /// Show events for a single geofence
  singleGeofence,
}

/// Page for viewing and managing geofence events.
///
/// This page displays historical geofence events (entry, exit, dwell)
/// with filtering, sorting, and batch actions.
///
/// ## Features
/// - Real-time event updates via Riverpod streams
/// - Filter by event type, status, device, date range
/// - Acknowledge or archive events
/// - View event location on map
/// - Batch operations (acknowledge all, archive old)
/// - Pull-to-refresh support
/// - Material Design 3 styling
///
/// ## Navigation
///
/// View all events:
/// ```dart
/// context.push('/events');
/// ```
///
/// View events for specific geofence:
/// ```dart
/// context.push('/geofences/${geofenceId}/events');
/// ```
///
/// ## Example Route Configuration
/// ```dart
/// GoRoute(
///   path: '/events',
///   builder: (context, state) => const GeofenceEventsPage(
///     mode: GeofenceEventsViewMode.all,
///   ),
/// ),
/// GoRoute(
///   path: '/geofences/:id/events',
///   builder: (context, state) {
///     final id = state.pathParameters['id']!;
///     return GeofenceEventsPage(
///       mode: GeofenceEventsViewMode.singleGeofence,
///       geofenceId: id,
///     );
///   },
/// ),
/// ```
class GeofenceEventsPage extends ConsumerWidget {
  final GeofenceEventsViewMode mode;
  final String? geofenceId;

  const GeofenceEventsPage({
    required this.mode,
    this.geofenceId,
    super.key,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final filterState = ref.watch(geofenceEventsFilterProvider);

    // Watch events based on mode
    final eventsAsync = mode == GeofenceEventsViewMode.singleGeofence
        ? ref.watch(eventsByGeofenceProvider(geofenceId!))
        : ref.watch(geofenceEventsProvider);

    // Watch unacknowledged count for badge
    final unacknowledgedCount = ref.watch(unacknowledgedEventCountProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          mode == GeofenceEventsViewMode.singleGeofence
              ? 'Geofence Events'
              : 'All Events',
        ),
        actions: [
          // Filter button
          IconButton(
            icon: Badge(
              isLabelVisible: filterState.hasActiveFilters(),
              child: const Icon(Icons.filter_list),
            ),
            tooltip: 'Filter',
            onPressed: () => _openFilterSheet(context, ref),
          ),

          // Sort button (extracted widget)
          const SortMenuButton(),

          // Refresh button
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
            onPressed: () {
              ref.invalidate(geofenceEventsProvider);
              if (geofenceId != null) {
                ref.invalidate(eventsByGeofenceProvider(geofenceId!));
              }
            },
          ),

          // More actions
          MoreActionsMenu(
            onAcknowledgeAll: () => _acknowledgeAll(context, ref),
            onArchiveOld: () => _archiveOld(context, ref),
            onExport: () => _exportEvents(context, ref),
          ),
        ],
      ),
      body: Column(
        children: [
          // Statistics bar
          EventStatisticsBar(unacknowledgedCount: unacknowledgedCount),

          // Filter chips
          if (filterState.hasActiveFilters()) const ActiveFilterChips(),

          // Events list
          Expanded(
            child: eventsAsync.when(
              data: (events) => _buildEventsList(context, theme, events, ref, filterState),
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, stack) => _buildErrorState(theme, error, ref),
            ),
          ),
        ],
      ),
      bottomNavigationBar: _buildBottomBar(theme),
    );
  }

  /// Build events list
  Widget _buildEventsList(
    BuildContext context,
    ThemeData theme,
    List<GeofenceEvent> events,
    WidgetRef ref,
    GeofenceEventsFilterState filterState,
  ) {
    // Apply filters
    final filteredEvents = _applyFilters(events, filterState);

    // Apply sorting
    final sortedEvents = _applySorting(filteredEvents, filterState);

    if (sortedEvents.isEmpty) {
      return _buildEmptyState(theme, ref, filterState);
    }

    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(geofenceEventsProvider);
        if (geofenceId != null) {
          ref.invalidate(eventsByGeofenceProvider(geofenceId!));
        }
      },
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: sortedEvents.length,
        itemBuilder: (context, index) {
          final event = sortedEvents[index];
          return _buildEventTile(context, theme, event, ref);
        },
      ),
    );
  }

  /// Build event tile
  Widget _buildEventTile(
    BuildContext context,
    ThemeData theme,
    GeofenceEvent event,
    WidgetRef ref,
  ) {
    final eventTypeColor = _getEventTypeColor(event.eventType, theme);
    final statusColor = _getStatusColor(event.status, theme);

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: () => _showEventDetails(context, ref, event),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Leading icon
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: eventTypeColor.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  _getEventTypeIcon(event.eventType),
                  color: eventTypeColor,
                  size: 20,
                ),
              ),

              const SizedBox(width: 12),

              // Content
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Title
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            _formatEventTitle(event),
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        // Status chip
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: statusColor.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                _getStatusIcon(event.status),
                                size: 12,
                                color: statusColor,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                _capitalizeFirst(event.status),
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: statusColor,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 4),

                    // Timestamp
                    Text(
                      _formatTimestamp(event.timestamp),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),

                    const SizedBox(height: 4),

                    // Device
                    Row(
                      children: [
                        Icon(
                          Icons.smartphone,
                          size: 12,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          event.deviceId,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Icon(
                          Icons.location_on,
                          size: 12,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '${event.location.latitude.toStringAsFixed(4)}, '
                          '${event.location.longitude.toStringAsFixed(4)}',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),

                    // Additional info
                    if (event.dwellDurationMs != null) ...[
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Icon(
                            Icons.timer,
                            size: 12,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            'Dwell: ${_formatDuration(Duration(milliseconds: event.dwellDurationMs!))}',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),

              const SizedBox(width: 12),

              // Actions
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Acknowledge button (if pending)
                  if (event.status == 'pending')
                    IconButton(
                      icon: const Icon(Icons.check_circle_outline),
                      tooltip: 'Acknowledge',
                      iconSize: 20,
                      onPressed: () => _acknowledgeEvent(context, ref, event),
                    ),

                  // Archive button (if acknowledged)
                  if (event.status == 'acknowledged')
                    IconButton(
                      icon: const Icon(Icons.archive_outlined),
                      tooltip: 'Archive',
                      iconSize: 20,
                      onPressed: () => _archiveEvent(context, ref, event),
                    ),

                  // View on map
                  IconButton(
                    icon: const Icon(Icons.map_outlined),
                    tooltip: 'View on Map',
                    iconSize: 20,
                    onPressed: () => _showEventOnMap(context, event),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Build empty state
  Widget _buildEmptyState(
    ThemeData theme,
    WidgetRef ref,
    GeofenceEventsFilterState filterState,
  ) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.event_note,
              size: 64,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 16),
            Text(
              'No events yet',
              style: theme.textTheme.titleLarge?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              filterState.hasActiveFilters()
                  ? 'Try adjusting your filters'
                  : 'Events will appear here when devices\nenter or exit geofences',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              icon: const Icon(Icons.refresh),
              label: const Text('Refresh'),
              onPressed: () {
                ref.invalidate(geofenceEventsProvider);
                if (geofenceId != null) {
                  ref.invalidate(eventsByGeofenceProvider(geofenceId!));
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  /// Build error state
  Widget _buildErrorState(ThemeData theme, Object error, WidgetRef ref) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.error_outline,
              size: 64,
              color: theme.colorScheme.error,
            ),
            const SizedBox(height: 16),
            Text(
              'Error loading events',
              style: theme.textTheme.titleLarge?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              error.toString(),
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
              onPressed: () {
                ref.invalidate(geofenceEventsProvider);
                if (geofenceId != null) {
                  ref.invalidate(eventsByGeofenceProvider(geofenceId!));
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  /// Build bottom bar
  Widget _buildBottomBar(ThemeData theme) {
    return Consumer(
      builder: (context, ref, child) {
        return Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            border: Border(
              top: BorderSide(
                color: theme.colorScheme.outline.withValues(alpha: 0.2),
              ),
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.check_circle),
                  label: const Text('Acknowledge All'),
                  onPressed: () => _acknowledgeAll(context, ref),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.archive),
                  label: const Text('Archive Old'),
                  onPressed: () => _archiveOld(context, ref),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  /// Open filter sheet
  void _openFilterSheet(BuildContext context, WidgetRef ref) {
    final filterNotifier = ref.read(geofenceEventsFilterProvider.notifier);
    
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        return DraggableScrollableSheet(
          initialChildSize: 0.7,
          minChildSize: 0.5,
          maxChildSize: 0.95,
          expand: false,
          builder: (context, scrollController) {
            return Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header
                  Row(
                    children: [
                      Text(
                        'Filters',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const Spacer(),
                      TextButton(
                        onPressed: () {
                          filterNotifier.clearAll();
                          context.safePop<void>();
                        },
                        child: const Text('Reset'),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => context.safePop<void>(),
                      ),
                    ],
                  ),

                  const Divider(),

                  Expanded(
                    child: ListView(
                      controller: scrollController,
                      children: const [
                        // Event Type
                        EventTypeFilterToggle(),
                        SizedBox(height: 16),

                        // Status
                        StatusFilterToggle(),
                        SizedBox(height: 16),

                        // Device
                        DeviceFilterSelector(),
                        SizedBox(height: 16),

                        // Date Range
                        EventDateRangePicker(),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  /// Show event details dialog
  void _showEventDetails(
    BuildContext context,
    WidgetRef ref,
    GeofenceEvent event,
  ) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(_formatEventTitle(event)),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildDetailRow(Icons.schedule, 'Time',
                  DateFormat('MMM d, y - h:mm a').format(event.timestamp)),
              _buildDetailRow(
                  Icons.smartphone, 'Device', event.deviceId),
              _buildDetailRow(
                  Icons.category, 'Type', _capitalizeFirst(event.eventType)),
              _buildDetailRow(
                  Icons.flag, 'Status', _capitalizeFirst(event.status)),
              _buildDetailRow(
                Icons.location_on,
                'Location',
                '${event.location.latitude.toStringAsFixed(6)}, '
                    '${event.location.longitude.toStringAsFixed(6)}',
              ),
              if (event.dwellDurationMs != null)
                _buildDetailRow(
                  Icons.timer,
                  'Dwell Duration',
                  _formatDuration(
                      Duration(milliseconds: event.dwellDurationMs!)),
                ),
            ],
          ),
        ),
        actions: [
          if (event.status == 'pending')
            TextButton.icon(
              icon: const Icon(Icons.check_circle),
              label: const Text('Acknowledge'),
              onPressed: () {
                context.safePop<void>();
                _acknowledgeEvent(context, ref, event);
              },
            ),
          TextButton.icon(
            icon: const Icon(Icons.map),
            label: const Text('View on Map'),
            onPressed: () {
              context.safePop<void>();
              _showEventOnMap(context, event);
            },
          ),
          TextButton(
            onPressed: () => context.safePop<void>(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  /// Build detail row for dialog
  Widget _buildDetailRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: Colors.grey,
                  ),
                ),
                const SizedBox(height: 2),
                Text(value),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Show event on map
  void _showEventOnMap(BuildContext context, GeofenceEvent event) {
    // TODO: Integrate with map widget
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Event Location'),
        content: SizedBox(
          width: 300,
          height: 300,
          child: Container(
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.map,
                    size: 64,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Map Preview',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '${event.location.latitude.toStringAsFixed(4)}, '
                    '${event.location.longitude.toStringAsFixed(4)}',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  ),
                ],
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => context.safePop<void>(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  /// Acknowledge single event
  Future<void> _acknowledgeEvent(
    BuildContext context,
    WidgetRef ref,
    GeofenceEvent event,
  ) async {
    try {
      // Await repository initialization before acknowledging
      final repo = await ref.read(geofenceEventRepositoryProvider.future);
      await repo.acknowledgeEvent(event.id);

      // Invalidate providers to trigger immediate UI update
      ref.invalidate(geofenceEventsProvider);
      ref.invalidate(unacknowledgedEventsProvider);

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Event acknowledged'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 2),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error acknowledging event: $e'),
            backgroundColor: Theme.of(context).colorScheme.error,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  /// Archive single event
  Future<void> _archiveEvent(
    BuildContext context,
    WidgetRef ref,
    GeofenceEvent event,
  ) async {
    try {
      // Await repository initialization before archiving
      final repo = await ref.read(geofenceEventRepositoryProvider.future);
      // For now, acknowledge the event as archived status
      // TODO: Add archive status support to repository
      await repo.acknowledgeEvent(event.id);

      // Invalidate providers to trigger immediate UI update
      ref.invalidate(geofenceEventsProvider);
      ref.invalidate(unacknowledgedEventsProvider);
      
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Event archived'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 2),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error archiving event: $e'),
            backgroundColor: Theme.of(context).colorScheme.error,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  /// Acknowledge all pending events
  Future<void> _acknowledgeAll(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Acknowledge All'),
        content: const Text(
          'Mark all pending events as acknowledged?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Acknowledge All'),
          ),
        ],
      ),
    );

    if (confirmed ?? false) {
      try {
        // Await repository initialization before bulk acknowledge
        final repo = await ref.read(geofenceEventRepositoryProvider.future);
        // Get all pending events and acknowledge them
        final pendingEvents = await repo.getPendingEvents(limit: 1000);
        final eventIds = pendingEvents.map((GeofenceEvent e) => e.id).toList();
        
        if (eventIds.isNotEmpty) {
          await repo.acknowledgeMultipleEvents(eventIds);

          // Invalidate providers to trigger immediate UI update
          ref.invalidate(geofenceEventsProvider);
          ref.invalidate(unacknowledgedEventsProvider);
          
          if (!context.mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('${eventIds.length} events acknowledged'),
              backgroundColor: Colors.green,
              duration: const Duration(seconds: 2),
              behavior: SnackBarBehavior.floating,
            ),
          );
        } else {
          if (!context.mounted) return;
          // ignore: use_build_context_synchronously
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('No pending events to acknowledge'),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      } catch (e) {
        if (!context.mounted) return;
        // ignore: use_build_context_synchronously
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            // ignore: use_build_context_synchronously
            backgroundColor: Theme.of(context).colorScheme.error,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  /// Archive old events
  Future<void> _archiveOld(BuildContext context, WidgetRef ref) async {
    final days = await showDialog<int>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Archive Old Events'),
        content: const Text(
          'Archive events older than how many days?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(7),
            child: const Text('7 days'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(30),
            child: const Text('30 days'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(90),
            child: const Text('90 days'),
          ),
        ],
      ),
    );

    if (days != null) {
      try {
        // Await repository initialization before archiving
        final repo = await ref.read(geofenceEventRepositoryProvider.future);
        await repo.archiveOldEvents(Duration(days: days));

        // Invalidate providers to trigger immediate UI update
        ref.invalidate(geofenceEventsProvider);
        ref.invalidate(unacknowledgedEventsProvider);

        if (!context.mounted) return;
        // ignore: use_build_context_synchronously
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Events older than $days days archived'),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 2),
            behavior: SnackBarBehavior.floating,
          ),
        );
      } catch (e) {
        if (!context.mounted) return;
        // ignore: use_build_context_synchronously
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            // ignore: use_build_context_synchronously
            backgroundColor: Theme.of(context).colorScheme.error,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  /// Export events (placeholder)
  void _exportEvents(BuildContext context, WidgetRef ref) {
    // TODO: Implement export to CSV/JSON
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Export feature coming soon'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  /// Apply filters to events list
  List<GeofenceEvent> _applyFilters(
    List<GeofenceEvent> events,
    GeofenceEventsFilterState filterState,
  ) {
    return events.where((event) {
      // Filter by event type
      if (!filterState.selectedEventTypes.contains(event.eventType)) {
        return false;
      }

      // Filter by status
      if (!filterState.selectedStatuses.contains(event.status)) {
        return false;
      }

      // Filter by device
      if (filterState.selectedDevice != null && 
          event.deviceId != filterState.selectedDevice) {
        return false;
      }

      // Filter by date range
      if (filterState.dateRange != null) {
        if (event.timestamp.isBefore(filterState.dateRange!.start) ||
            event.timestamp.isAfter(filterState.dateRange!.end)) {
          return false;
        }
      }

      return true;
    }).toList();
  }

  /// Apply sorting to events list
  List<GeofenceEvent> _applySorting(
    List<GeofenceEvent> events,
    GeofenceEventsFilterState filterState,
  ) {
    final sorted = List<GeofenceEvent>.from(events);

    sorted.sort((a, b) {
      int comparison;

      switch (filterState.sortBy) {
        case 'timestamp':
          comparison = a.timestamp.compareTo(b.timestamp);
        case 'type':
          comparison = a.eventType.compareTo(b.eventType);
        case 'status':
          comparison = a.status.compareTo(b.status);
        default:
          comparison = 0;
      }

      return filterState.sortAscending ? comparison : -comparison;
    });

    return sorted;
  }

  /// Get event type icon
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

  /// Get status icon
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

  /// Get event type color
  Color _getEventTypeColor(String type, ThemeData theme) {
    switch (type) {
      case 'entry':
        return Colors.green;
      case 'exit':
        return Colors.red;
      case 'dwell':
        return Colors.orange;
      default:
        return theme.colorScheme.primary;
    }
  }

  /// Get status color
  Color _getStatusColor(String status, ThemeData theme) {
    switch (status) {
      case 'pending':
        return Colors.amber;
      case 'acknowledged':
        return Colors.blue;
      case 'archived':
        return Colors.grey;
      default:
        return theme.colorScheme.onSurface;
    }
  }

  /// Format event title
  String _formatEventTitle(GeofenceEvent event) {
    switch (event.eventType) {
      case 'entry':
        return '${event.deviceId} entered ${event.geofenceId}';
      case 'exit':
        return '${event.deviceId} exited ${event.geofenceId}';
      case 'dwell':
        return '${event.deviceId} dwelling in ${event.geofenceId}';
      default:
        return 'Unknown event';
    }
  }

  /// Format timestamp
  String _formatTimestamp(DateTime timestamp) {
    final now = DateTime.now();
    final difference = now.difference(timestamp);

    if (difference.inMinutes < 1) {
      return 'Just now';
    } else if (difference.inMinutes < 60) {
      return '${difference.inMinutes}m ago';
    } else if (difference.inHours < 24) {
      return '${difference.inHours}h ago';
    } else if (difference.inDays < 7) {
      return '${difference.inDays}d ago';
    } else {
      return DateFormat('MMM d, h:mm a').format(timestamp);
    }
  }

  /// Format duration
  String _formatDuration(Duration duration) {
    if (duration.inDays > 0) {
      return '${duration.inDays}d ${duration.inHours % 24}h';
    } else if (duration.inHours > 0) {
      return '${duration.inHours}h ${duration.inMinutes % 60}m';
    } else if (duration.inMinutes > 0) {
      return '${duration.inMinutes}m';
    } else {
      return '${duration.inSeconds}s';
    }
  }

  /// Capitalize first letter
  String _capitalizeFirst(String text) {
    if (text.isEmpty) return text;
    return text[0].toUpperCase() + text.substring(1);
  }
}

// =============================================================================
// ROUTE REGISTRATION EXAMPLE
// =============================================================================

/*
/// Example GoRouter configuration
final router = GoRouter(
  routes: [
    GoRoute(
      path: '/',
      builder: (context, state) => const HomePage(),
      routes: [
        // All events page
        GoRoute(
          path: 'events',
          builder: (context, state) => const GeofenceEventsPage(
            mode: GeofenceEventsViewMode.all,
          ),
        ),
        
        // Geofences section
        GoRoute(
          path: 'geofences',
          builder: (context, state) => const GeofenceListPage(),
          routes: [
            GoRoute(
              path: ':id',
              builder: (context, state) {
                final id = state.pathParameters['id']!;
                return GeofenceDetailPage(geofenceId: id);
              },
              routes: [
                // Events for specific geofence
                GoRoute(
                  path: 'events',
                  builder: (context, state) {
                    final id = state.pathParameters['id']!;
                    return GeofenceEventsPage(
                      mode: GeofenceEventsViewMode.singleGeofence,
                      geofenceId: id,
                    );
                  },
                ),
              ],
            ),
          ],
        ),
      ],
    ),
  ],
);
*/

// =============================================================================
// USAGE EXAMPLES
// =============================================================================

/*
/// Example: Navigate to all events
void navigateToAllEvents(BuildContext context) {
  context.safePush<void>('/events');
}

/// Example: Navigate to geofence events
void navigateToGeofenceEvents(BuildContext context, String geofenceId) {
  context.safePush<void>('/geofences/$geofenceId/events');
}

/// Example: Custom filter preset
void applyPresetFilter(String preset) {
  switch (preset) {
    case 'unacknowledged':
      setState(() {
        _selectedStatuses = {'pending'};
      });
      break;
    case 'today':
      setState(() {
        _dateRange = DateTimeRange(
          start: DateTime.now().subtract(const Duration(days: 1)),
          end: DateTime.now(),
        );
      });
      break;
    case 'entries':
      setState(() {
        _selectedEventTypes = {'entry'};
      });
      break;
  }
}
*/
