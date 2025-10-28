import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:my_app_gps/core/navigation/safe_navigation.dart';
import 'package:my_app_gps/data/models/geofence_event.dart';
import 'package:my_app_gps/features/geofencing/providers/geofence_providers.dart';

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
class GeofenceEventsPage extends ConsumerStatefulWidget {
  final GeofenceEventsViewMode mode;
  final String? geofenceId;

  const GeofenceEventsPage({
    required this.mode,
    this.geofenceId,
    super.key,
  });

  @override
  ConsumerState<GeofenceEventsPage> createState() =>
      _GeofenceEventsPageState();
}

class _GeofenceEventsPageState extends ConsumerState<GeofenceEventsPage> {
  // Filter state
  Set<String> _selectedEventTypes = {'entry', 'exit', 'dwell'};
  Set<String> _selectedStatuses = {'pending', 'acknowledged'};
  String? _selectedDevice;
  DateTimeRange? _dateRange;

  // Sort state
  String _sortBy = 'timestamp'; // timestamp, type, status
  bool _sortAscending = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // Watch events based on mode
    final eventsAsync = widget.mode == GeofenceEventsViewMode.singleGeofence
        ? ref.watch(eventsByGeofenceProvider(widget.geofenceId!))
        : ref.watch(geofenceEventsProvider);

    // Watch unacknowledged count for badge
    final unacknowledgedCount = ref.watch(unacknowledgedEventCountProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.mode == GeofenceEventsViewMode.singleGeofence
              ? 'Geofence Events'
              : 'All Events',
        ),
        actions: [
          // Filter button
          IconButton(
            icon: Badge(
              isLabelVisible: _hasActiveFilters(),
              child: const Icon(Icons.filter_list),
            ),
            tooltip: 'Filter',
            onPressed: () => _openFilterSheet(context),
          ),

          // Sort button
          PopupMenuButton<String>(
            icon: const Icon(Icons.sort),
            tooltip: 'Sort',
            onSelected: (value) {
              setState(() {
                if (_sortBy == value) {
                  _sortAscending = !_sortAscending;
                } else {
                  _sortBy = value;
                  _sortAscending = false;
                }
              });
            },
            itemBuilder: (context) => [
              PopupMenuItem(
                value: 'timestamp',
                child: Row(
                  children: [
                    const Icon(Icons.schedule),
                    const SizedBox(width: 8),
                    const Text('By Time'),
                    if (_sortBy == 'timestamp') ...[
                      const Spacer(),
                      Icon(
                        _sortAscending
                            ? Icons.arrow_upward
                            : Icons.arrow_downward,
                        size: 16,
                      ),
                    ],
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'type',
                child: Row(
                  children: [
                    const Icon(Icons.category),
                    const SizedBox(width: 8),
                    const Text('By Type'),
                    if (_sortBy == 'type') ...[
                      const Spacer(),
                      Icon(
                        _sortAscending
                            ? Icons.arrow_upward
                            : Icons.arrow_downward,
                        size: 16,
                      ),
                    ],
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'status',
                child: Row(
                  children: [
                    const Icon(Icons.flag),
                    const SizedBox(width: 8),
                    const Text('By Status'),
                    if (_sortBy == 'status') ...[
                      const Spacer(),
                      Icon(
                        _sortAscending
                            ? Icons.arrow_upward
                            : Icons.arrow_downward,
                        size: 16,
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),

          // Refresh button
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
            onPressed: () {
              ref.invalidate(geofenceEventsProvider);
              if (widget.geofenceId != null) {
                ref.invalidate(eventsByGeofenceProvider(widget.geofenceId!));
              }
            },
          ),

          // More actions
          PopupMenuButton(
            icon: const Icon(Icons.more_vert),
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'acknowledge_all',
                child: Row(
                  children: [
                    Icon(Icons.check_circle),
                    SizedBox(width: 8),
                    Text('Acknowledge All'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'archive_old',
                child: Row(
                  children: [
                    Icon(Icons.archive),
                    SizedBox(width: 8),
                    Text('Archive Old Events'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'export',
                child: Row(
                  children: [
                    Icon(Icons.download),
                    SizedBox(width: 8),
                    Text('Export Events'),
                  ],
                ),
              ),
            ],
            onSelected: (value) {
              switch (value) {
                case 'acknowledge_all':
                  _acknowledgeAll();
                case 'archive_old':
                  _archiveOld();
                case 'export':
                  _exportEvents();
              }
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // Statistics bar
          _buildStatisticsBar(theme, unacknowledgedCount),

          // Filter chips
          if (_hasActiveFilters()) _buildFilterChips(theme),

          // Events list
          Expanded(
            child: eventsAsync.when(
              data: (events) => _buildEventsList(context, theme, events),
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, stack) => _buildErrorState(theme, error),
            ),
          ),
        ],
      ),
      bottomNavigationBar: _buildBottomBar(theme),
    );
  }

  /// Build statistics bar
  Widget _buildStatisticsBar(ThemeData theme, int unacknowledgedCount) {
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
            'Sort: ${_sortBy.toUpperCase()}',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  /// Build filter chips
  Widget _buildFilterChips(ThemeData theme) {
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
            // Event type chips
            if (_selectedEventTypes.length < 3)
              ..._selectedEventTypes.map((type) {
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Chip(
                    avatar: Icon(
                      _getEventTypeIcon(type),
                      size: 16,
                    ),
                    label: Text(_capitalizeFirst(type)),
                    deleteIcon: const Icon(Icons.close, size: 16),
                    onDeleted: () {
                      setState(() {
                        _selectedEventTypes.remove(type);
                        if (_selectedEventTypes.isEmpty) {
                          _selectedEventTypes = {'entry', 'exit', 'dwell'};
                        }
                      });
                    },
                  ),
                );
              }),

            // Status chips
            if (_selectedStatuses.length < 3)
              ..._selectedStatuses.map((status) {
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Chip(
                    avatar: Icon(
                      _getStatusIcon(status),
                      size: 16,
                    ),
                    label: Text(_capitalizeFirst(status)),
                    deleteIcon: const Icon(Icons.close, size: 16),
                    onDeleted: () {
                      setState(() {
                        _selectedStatuses.remove(status);
                        if (_selectedStatuses.isEmpty) {
                          _selectedStatuses = {
                            'pending',
                            'acknowledged',
                            'archived'
                          };
                        }
                      });
                    },
                  ),
                );
              }),

            // Device chip
            if (_selectedDevice != null)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Chip(
                  avatar: const Icon(Icons.smartphone, size: 16),
                  label: Text(_selectedDevice!),
                  deleteIcon: const Icon(Icons.close, size: 16),
                  onDeleted: () {
                    setState(() {
                      _selectedDevice = null;
                    });
                  },
                ),
              ),

            // Date range chip
            if (_dateRange != null)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Chip(
                  avatar: const Icon(Icons.date_range, size: 16),
                  label: Text(
                    '${DateFormat('MMM d').format(_dateRange!.start)} - '
                    '${DateFormat('MMM d').format(_dateRange!.end)}',
                  ),
                  deleteIcon: const Icon(Icons.close, size: 16),
                  onDeleted: () {
                    setState(() {
                      _dateRange = null;
                    });
                  },
                ),
              ),

            // Clear all
            if (_hasActiveFilters())
              TextButton.icon(
                icon: const Icon(Icons.clear_all, size: 16),
                label: const Text('Clear'),
                onPressed: () {
                  setState(() {
                    _selectedEventTypes = {'entry', 'exit', 'dwell'};
                    _selectedStatuses = {'pending', 'acknowledged'};
                    _selectedDevice = null;
                    _dateRange = null;
                  });
                },
              ),
          ],
        ),
      ),
    );
  }

  /// Build events list
  Widget _buildEventsList(
    BuildContext context,
    ThemeData theme,
    List<GeofenceEvent> events,
  ) {
    // Apply filters
    final filteredEvents = _applyFilters(events);

    // Apply sorting
    final sortedEvents = _applySorting(filteredEvents);

    if (sortedEvents.isEmpty) {
      return _buildEmptyState(theme);
    }

    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(geofenceEventsProvider);
        if (widget.geofenceId != null) {
          ref.invalidate(eventsByGeofenceProvider(widget.geofenceId!));
        }
      },
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: sortedEvents.length,
        itemBuilder: (context, index) {
          final event = sortedEvents[index];
          return _buildEventTile(context, theme, event);
        },
      ),
    );
  }

  /// Build event tile
  Widget _buildEventTile(
    BuildContext context,
    ThemeData theme,
    GeofenceEvent event,
  ) {
    final eventTypeColor = _getEventTypeColor(event.eventType, theme);
    final statusColor = _getStatusColor(event.status, theme);

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: () => _showEventDetails(context, event),
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
                      onPressed: () => _acknowledgeEvent(event),
                    ),

                  // Archive button (if acknowledged)
                  if (event.status == 'acknowledged')
                    IconButton(
                      icon: const Icon(Icons.archive_outlined),
                      tooltip: 'Archive',
                      iconSize: 20,
                      onPressed: () => _archiveEvent(event),
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
  Widget _buildEmptyState(ThemeData theme) {
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
              _hasActiveFilters()
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
                if (widget.geofenceId != null) {
                  ref.invalidate(eventsByGeofenceProvider(widget.geofenceId!));
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  /// Build error state
  Widget _buildErrorState(ThemeData theme, Object error) {
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
                if (widget.geofenceId != null) {
                  ref.invalidate(eventsByGeofenceProvider(widget.geofenceId!));
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
              onPressed: _acknowledgeAll,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: OutlinedButton.icon(
              icon: const Icon(Icons.archive),
              label: const Text('Archive Old'),
              onPressed: _archiveOld,
            ),
          ),
        ],
      ),
    );
  }

  /// Open filter sheet
  void _openFilterSheet(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
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
                              setState(() {
                                _selectedEventTypes = {
                                  'entry',
                                  'exit',
                                  'dwell'
                                };
                                _selectedStatuses = {
                                  'pending',
                                  'acknowledged'
                                };
                                _selectedDevice = null;
                                _dateRange = null;
                              });
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
                          children: [
                            // Event Type
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
                                  selected:
                                      _selectedEventTypes.contains('entry'),
                                  onSelected: (selected) {
                                    setModalState(() {
                                      setState(() {
                                        if (selected) {
                                          _selectedEventTypes.add('entry');
                                        } else {
                                          _selectedEventTypes.remove('entry');
                                        }
                                      });
                                    });
                                  },
                                ),
                                FilterChip(
                                  label: const Text('Exit'),
                                  avatar: const Icon(Icons.logout, size: 16),
                                  selected: _selectedEventTypes.contains('exit'),
                                  onSelected: (selected) {
                                    setModalState(() {
                                      setState(() {
                                        if (selected) {
                                          _selectedEventTypes.add('exit');
                                        } else {
                                          _selectedEventTypes.remove('exit');
                                        }
                                      });
                                    });
                                  },
                                ),
                                FilterChip(
                                  label: const Text('Dwell'),
                                  avatar: const Icon(Icons.schedule, size: 16),
                                  selected:
                                      _selectedEventTypes.contains('dwell'),
                                  onSelected: (selected) {
                                    setModalState(() {
                                      setState(() {
                                        if (selected) {
                                          _selectedEventTypes.add('dwell');
                                        } else {
                                          _selectedEventTypes.remove('dwell');
                                        }
                                      });
                                    });
                                  },
                                ),
                              ],
                            ),

                            const SizedBox(height: 16),

                            // Status
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
                                  selected:
                                      _selectedStatuses.contains('pending'),
                                  onSelected: (selected) {
                                    setModalState(() {
                                      setState(() {
                                        if (selected) {
                                          _selectedStatuses.add('pending');
                                        } else {
                                          _selectedStatuses.remove('pending');
                                        }
                                      });
                                    });
                                  },
                                ),
                                FilterChip(
                                  label: const Text('Acknowledged'),
                                  avatar:
                                      const Icon(Icons.check_circle, size: 16),
                                  selected:
                                      _selectedStatuses.contains('acknowledged'),
                                  onSelected: (selected) {
                                    setModalState(() {
                                      setState(() {
                                        if (selected) {
                                          _selectedStatuses.add('acknowledged');
                                        } else {
                                          _selectedStatuses
                                              .remove('acknowledged');
                                        }
                                      });
                                    });
                                  },
                                ),
                                FilterChip(
                                  label: const Text('Archived'),
                                  avatar: const Icon(Icons.archive, size: 16),
                                  selected:
                                      _selectedStatuses.contains('archived'),
                                  onSelected: (selected) {
                                    setModalState(() {
                                      setState(() {
                                        if (selected) {
                                          _selectedStatuses.add('archived');
                                        } else {
                                          _selectedStatuses.remove('archived');
                                        }
                                      });
                                    });
                                  },
                                ),
                              ],
                            ),

                            const SizedBox(height: 16),

                            // Device (TODO: Load from provider)
                            Text(
                              'Device',
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            const SizedBox(height: 8),
                            DropdownButtonFormField<String>(
                              initialValue: _selectedDevice,
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
                              onChanged: (value) {
                                setModalState(() {
                                  setState(() {
                                    _selectedDevice = value;
                                  });
                                });
                              },
                            ),

                            const SizedBox(height: 16),

                            // Date Range
                            Text(
                              'Date Range',
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            const SizedBox(height: 8),
                            OutlinedButton.icon(
                              icon: const Icon(Icons.date_range),
                              label: Text(
                                _dateRange == null
                                    ? 'Select Date Range'
                                    : '${DateFormat('MMM d, y').format(_dateRange!.start)} - '
                                        '${DateFormat('MMM d, y').format(_dateRange!.end)}',
                              ),
                              onPressed: () async {
                                final range = await showDateRangePicker(
                                  context: context,
                                  firstDate: DateTime.now()
                                      .subtract(const Duration(days: 365)),
                                  lastDate: DateTime.now(),
                                  initialDateRange: _dateRange,
                                );
                                if (range != null) {
                                  setModalState(() {
                                    setState(() {
                                      _dateRange = range;
                                    });
                                  });
                                }
                              },
                            ),
                            if (_dateRange != null)
                              TextButton.icon(
                                icon: const Icon(Icons.clear),
                                label: const Text('Clear Date Range'),
                                onPressed: () {
                                  setModalState(() {
                                    setState(() {
                                      _dateRange = null;
                                    });
                                  });
                                },
                              ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 16),

                      // Apply button
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton(
                          onPressed: () => context.safePop<void>(),
                          child: const Text('Apply Filters'),
                        ),
                      ),
                    ],
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  /// Show event details dialog
  void _showEventDetails(BuildContext context, GeofenceEvent event) {
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
                _acknowledgeEvent(event);
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
  Future<void> _acknowledgeEvent(GeofenceEvent event) async {
    try {
      // Await repository initialization before acknowledging
      final repo = await ref.read(geofenceEventRepositoryProvider.future);
      await repo.acknowledgeEvent(event.id);

      // Invalidate providers to trigger immediate UI update
      ref.invalidate(geofenceEventsProvider);
      ref.invalidate(unacknowledgedEventsProvider);

      if (mounted) {
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
      if (mounted) {
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
  Future<void> _archiveEvent(GeofenceEvent event) async {
    try {
      // Await repository initialization before archiving
      final repo = await ref.read(geofenceEventRepositoryProvider.future);
      // For now, acknowledge the event as archived status
      // TODO: Add archive status support to repository
      await repo.acknowledgeEvent(event.id);

      // Invalidate providers to trigger immediate UI update
      ref.invalidate(geofenceEventsProvider);
      ref.invalidate(unacknowledgedEventsProvider);
      
      if (mounted) {
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
      if (mounted) {
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
  Future<void> _acknowledgeAll() async {
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
          // ignore: use_build_context_synchronously
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
  Future<void> _archiveOld() async {
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
  void _exportEvents() {
    // TODO: Implement export to CSV/JSON
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Export feature coming soon'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  /// Apply filters to events list
  List<GeofenceEvent> _applyFilters(List<GeofenceEvent> events) {
    return events.where((event) {
      // Filter by event type
      if (!_selectedEventTypes.contains(event.eventType)) {
        return false;
      }

      // Filter by status
      if (!_selectedStatuses.contains(event.status)) {
        return false;
      }

      // Filter by device
      if (_selectedDevice != null && event.deviceId != _selectedDevice) {
        return false;
      }

      // Filter by date range
      if (_dateRange != null) {
        if (event.timestamp.isBefore(_dateRange!.start) ||
            event.timestamp.isAfter(_dateRange!.end)) {
          return false;
        }
      }

      return true;
    }).toList();
  }

  /// Apply sorting to events list
  List<GeofenceEvent> _applySorting(List<GeofenceEvent> events) {
    final sorted = List<GeofenceEvent>.from(events);

    sorted.sort((a, b) {
      int comparison;

      switch (_sortBy) {
        case 'timestamp':
          comparison = a.timestamp.compareTo(b.timestamp);
        case 'type':
          comparison = a.eventType.compareTo(b.eventType);
        case 'status':
          comparison = a.status.compareTo(b.status);
        default:
          comparison = 0;
      }

      return _sortAscending ? comparison : -comparison;
    });

    return sorted;
  }

  /// Check if any filters are active
  bool _hasActiveFilters() {
    return _selectedEventTypes.length < 3 ||
        _selectedStatuses.length < 3 ||
        _selectedDevice != null ||
        _dateRange != null;
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
