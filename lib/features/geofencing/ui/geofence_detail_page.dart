import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:my_app_gps/core/navigation/safe_navigation.dart';
import 'package:my_app_gps/data/models/geofence.dart';
import 'package:my_app_gps/data/models/geofence_event.dart';
import 'package:my_app_gps/features/geofencing/providers/geofence_providers.dart';
import 'package:my_app_gps/features/geofencing/ui/widgets/geofence_map_widget.dart';

/// Detail page for viewing a single geofence.
///
/// This page displays:
/// - Geofence metadata (name, type, triggers, notifications)
/// - Map preview with boundary visualization
/// - List of monitored devices
/// - Recent events (entry/exit/dwell)
/// - Actions (enable/disable, edit, delete)
///
/// ## Navigation
/// Route: `/geofences/:id`
///
/// ## Example Usage in GoRouter
/// ```dart
/// GoRoute(
///   path: '/geofences/:id',
///   builder: (context, state) {
///     final id = state.pathParameters['id']!;
///     return GeofenceDetailPage(geofenceId: id);
///   },
/// ),
/// ```
///
/// ## Features
/// - Reactive updates via Riverpod streams
/// - Material Design 3 styling
/// - Light + dark mode support
/// - Map preview (read-only)
/// - Recent events feed
/// - Quick actions (edit, delete, duplicate)
class GeofenceDetailPage extends ConsumerWidget {
  final String geofenceId;

  const GeofenceDetailPage({
    required this.geofenceId,
    super.key,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final geofencesAsync = ref.watch(geofencesProvider);
    final eventsAsync = ref.watch(eventsByGeofenceProvider(geofenceId));

    return geofencesAsync.when(
      data: (geofences) {
        // Find the geofence
        final geofence = geofences.firstWhere(
          (g) => g.id == geofenceId,
          orElse: () => throw Exception('Geofence not found'),
        );

        return Scaffold(
          appBar: _buildAppBar(context, ref, geofence),
          body: _buildBody(context, ref, geofence, eventsAsync),
          floatingActionButton: _buildFAB(context, geofence),
        );
      },
      loading: () => Scaffold(
        appBar: AppBar(title: const Text('Loading...')),
        body: const Center(child: CircularProgressIndicator()),
      ),
      error: (error, _) => Scaffold(
        appBar: AppBar(title: const Text('Error')),
        body: _buildErrorState(context, error),
      ),
    );
  }

  /// Build app bar with actions
  PreferredSizeWidget _buildAppBar(
    BuildContext context,
    WidgetRef ref,
    Geofence geofence,
  ) {
    return AppBar(
      title: const Text('Geofence Details'),
      actions: [
        // Edit button
        IconButton(
          icon: const Icon(Icons.edit),
          tooltip: 'Edit',
          onPressed: () => context.safePush<void>('/geofences/$geofenceId/edit'),
        ),

        // More menu
        PopupMenuButton<String>(
          icon: const Icon(Icons.more_vert),
          onSelected: (value) {
            switch (value) {
              case 'duplicate':
                _duplicateGeofence(context, ref, geofence);
                break;
              case 'delete':
                _confirmDelete(context, ref, geofence);
                break;
              case 'share':
                _shareGeofence(context, geofence);
                break;
            }
          },
          itemBuilder: (context) => [
            const PopupMenuItem(
              value: 'duplicate',
              child: Row(
                children: [
                  Icon(Icons.copy),
                  SizedBox(width: 8),
                  Text('Duplicate'),
                ],
              ),
            ),
            const PopupMenuItem(
              value: 'share',
              child: Row(
                children: [
                  Icon(Icons.share),
                  SizedBox(width: 8),
                  Text('Share'),
                ],
              ),
            ),
            const PopupMenuDivider(),
            const PopupMenuItem(
              value: 'delete',
              child: Row(
                children: [
                  Icon(Icons.delete, color: Colors.red),
                  SizedBox(width: 8),
                  Text('Delete', style: TextStyle(color: Colors.red)),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  /// Build main body content
  Widget _buildBody(
    BuildContext context,
    WidgetRef ref,
    Geofence geofence,
    AsyncValue<List<GeofenceEvent>> eventsAsync,
  ) {
    return SingleChildScrollView(
      padding: const EdgeInsets.only(bottom: 80), // Space for FAB
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header card
          _buildHeaderCard(context, ref, geofence),

          // Map preview
          _buildMapPreview(context, geofence, eventsAsync),

          // Info section
          _buildInfoSection(context, geofence),

          // Devices section
          _buildDevicesSection(context, geofence),

          // Recent events section
          _buildEventsSection(context, eventsAsync),

          const SizedBox(height: 16),
        ],
      ),
    );
  }

  /// Build header card with name, type, and toggle
  Widget _buildHeaderCard(
    BuildContext context,
    WidgetRef ref,
    Geofence geofence,
  ) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Card(
      margin: const EdgeInsets.all(16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Name and type badge
            Row(
              children: [
                // Type icon
                CircleAvatar(
                  backgroundColor: geofence.enabled
                      ? colorScheme.primaryContainer
                      : colorScheme.surfaceVariant,
                  child: Icon(
                    geofence.type == 'circle'
                        ? Icons.circle_outlined
                        : Icons.polyline,
                    color: geofence.enabled
                        ? colorScheme.onPrimaryContainer
                        : colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(width: 12),

                // Name
                Expanded(
                  child: Text(
                    geofence.name,
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),

                // Enable/disable switch
                Switch(
                  value: geofence.enabled,
                  onChanged: (enabled) =>
                      _toggleGeofence(context, ref, geofence, enabled),
                ),
              ],
            ),

            const SizedBox(height: 16),

            // Timestamps
            Row(
              children: [
                Expanded(
                  child: _buildTimestampItem(
                    context,
                    icon: Icons.add_circle_outline,
                    label: 'Created',
                    timestamp: geofence.createdAt,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: _buildTimestampItem(
                    context,
                    icon: Icons.update,
                    label: 'Updated',
                    timestamp: geofence.updatedAt,
                  ),
                ),
              ],
            ),

            // Status badge
            const SizedBox(height: 12),
            Row(
              children: [
                Icon(
                  geofence.enabled ? Icons.check_circle : Icons.pause_circle,
                  size: 16,
                  color: geofence.enabled ? Colors.green : Colors.grey,
                ),
                const SizedBox(width: 4),
                Text(
                  geofence.enabled ? 'Active' : 'Inactive',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: geofence.enabled ? Colors.green : Colors.grey,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// Build timestamp item
  Widget _buildTimestampItem(
    BuildContext context, {
    required IconData icon,
    required String label,
    required DateTime timestamp,
  }) {
    final theme = Theme.of(context);
    final formattedDate = DateFormat('MMM d, yyyy').format(timestamp);
    final formattedTime = DateFormat('h:mm a').format(timestamp);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 14, color: theme.textTheme.bodySmall?.color),
            const SizedBox(width: 4),
            Text(
              label,
              style: theme.textTheme.labelSmall,
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          formattedDate,
          style: theme.textTheme.bodySmall?.copyWith(
            fontWeight: FontWeight.w500,
          ),
        ),
        Text(
          formattedTime,
          style: theme.textTheme.bodySmall,
        ),
      ],
    );
  }

  /// Build map preview section
  Widget _buildMapPreview(
    BuildContext context,
    Geofence geofence,
    AsyncValue<List<GeofenceEvent>> eventsAsync,
  ) {
    final theme = Theme.of(context);

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Icon(Icons.map, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Text(
                  'Location',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),

          // Map widget
          SizedBox(
            height: 240,
            child: eventsAsync.when(
              data: (events) => GeofenceMapWidget(
                geofence: geofence,
                events: events.take(5).toList(),
                editable: false,
              ),
              loading: () => Container(
                color: theme.colorScheme.surfaceVariant,
                child: const Center(
                  child: CircularProgressIndicator(),
                ),
              ),
              error: (_, __) => Container(
                color: theme.colorScheme.surfaceVariant,
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.map_outlined,
                        size: 48,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Map Preview',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),

          // Location details
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (geofence.type == 'circle') ...[
                  _buildInfoRow(
                    context,
                    icon: Icons.location_on,
                    label: 'Center',
                    value:
                        '${geofence.centerLat?.toStringAsFixed(6)}, ${geofence.centerLng?.toStringAsFixed(6)}',
                  ),
                  const SizedBox(height: 8),
                  _buildInfoRow(
                    context,
                    icon: Icons.straighten,
                    label: 'Radius',
                    value: _formatDistance(geofence.radius ?? 0),
                  ),
                ] else ...[
                  _buildInfoRow(
                    context,
                    icon: Icons.polyline,
                    label: 'Vertices',
                    value: '${geofence.vertices?.length ?? 0} points',
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Build info section with triggers and notifications
  Widget _buildInfoSection(BuildContext context, Geofence geofence) {
    final theme = Theme.of(context);

    return Card(
      margin: const EdgeInsets.all(16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                Icon(Icons.info, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Text(
                  'Settings',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),

            const SizedBox(height: 16),

            // Triggers
            Text(
              'Triggers',
              style: theme.textTheme.labelMedium,
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (geofence.onEnter)
                  Chip(
                    avatar: const Icon(Icons.login, size: 16),
                    label: const Text('On Enter'),
                    backgroundColor: theme.colorScheme.primaryContainer,
                  ),
                if (geofence.onExit)
                  Chip(
                    avatar: const Icon(Icons.logout, size: 16),
                    label: const Text('On Exit'),
                    backgroundColor: theme.colorScheme.primaryContainer,
                  ),
                if (geofence.dwellMs != null && geofence.dwellMs! > 0)
                  Chip(
                    avatar: const Icon(Icons.schedule, size: 16),
                    label: Text(
                      'Dwell ${_formatDuration(Duration(milliseconds: geofence.dwellMs!))}',
                    ),
                    backgroundColor: theme.colorScheme.primaryContainer,
                  ),
                if (!geofence.onEnter &&
                    !geofence.onExit &&
                    (geofence.dwellMs == null || geofence.dwellMs == 0))
                  Chip(
                    label: const Text('No triggers'),
                    backgroundColor: theme.colorScheme.surfaceVariant,
                  ),
              ],
            ),

            const SizedBox(height: 16),

            // Notification type
            Text(
              'Notifications',
              style: theme.textTheme.labelMedium,
            ),
            const SizedBox(height: 8),
            Chip(
              avatar: Icon(
                geofence.notificationType == 'local'
                    ? Icons.notifications
                    : geofence.notificationType == 'push'
                        ? Icons.cloud
                        : Icons.notifications_active,
                size: 16,
              ),
              label: Text(
                geofence.notificationType.toUpperCase(),
              ),
              backgroundColor: theme.colorScheme.secondaryContainer,
            ),

            const SizedBox(height: 16),

            // Sync status
            _buildInfoRow(
              context,
              icon: Icons.sync,
              label: 'Sync Status',
              value: geofence.syncStatus.toUpperCase(),
            ),
            const SizedBox(height: 8),
            _buildInfoRow(
              context,
              icon: Icons.tag,
              label: 'Version',
              value: geofence.version.toString(),
            ),
          ],
        ),
      ),
    );
  }

  /// Build devices section
  Widget _buildDevicesSection(BuildContext context, Geofence geofence) {
    final theme = Theme.of(context);

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                Icon(Icons.devices, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Text(
                  'Monitored Devices',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                Text(
                  '${geofence.monitoredDevices.length}',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: theme.colorScheme.primary,
                  ),
                ),
              ],
            ),

            const SizedBox(height: 16),

            // Device list
            if (geofence.monitoredDevices.isEmpty)
              Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: Column(
                    children: [
                      Icon(
                        Icons.devices_other,
                        size: 48,
                        color: theme.colorScheme.outline,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'No devices monitored',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              )
            else
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: geofence.monitoredDevices.map((deviceId) {
                  return Chip(
                    avatar: CircleAvatar(
                      backgroundColor: theme.colorScheme.primaryContainer,
                      child: Icon(
                        Icons.smartphone,
                        size: 16,
                        color: theme.colorScheme.onPrimaryContainer,
                      ),
                    ),
                    label: Text(deviceId),
                  );
                }).toList(),
              ),

            const SizedBox(height: 12),

            // Manage devices button
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                icon: const Icon(Icons.edit),
                label: const Text('Manage Devices'),
                onPressed: () =>
                    context.safePush<void>('/geofences/$geofenceId/edit#devices'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Build recent events section
  Widget _buildEventsSection(
    BuildContext context,
    AsyncValue<List<GeofenceEvent>> eventsAsync,
  ) {
    final theme = Theme.of(context);

    return Card(
      margin: const EdgeInsets.all(16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                Icon(Icons.history, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Text(
                  'Recent Activity',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),

            const SizedBox(height: 16),

            // Events list
            eventsAsync.when(
              data: (events) {
                if (events.isEmpty) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      child: Column(
                        children: [
                          Icon(
                            Icons.event_busy,
                            size: 48,
                            color: theme.colorScheme.outline,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'No events yet',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }

                // Show up to 5 recent events
                final recentEvents = events.take(5).toList();

                return Column(
                  children: [
                    ...recentEvents.map((event) => _buildEventTile(
                          context,
                          event,
                        )),

                    // View all button if more than 5 events
                    if (events.length > 5) ...[
                      const SizedBox(height: 8),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          icon: const Icon(Icons.list),
                          label: Text('View All (${events.length})'),
                          onPressed: () =>
                              context.safePush<void>('/geofences/$geofenceId/events'),
                        ),
                      ),
                    ],
                  ],
                );
              },
              loading: () => const Center(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: CircularProgressIndicator(),
                ),
              ),
              error: (error, _) => Center(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    'Error loading events: $error',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.error,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Build individual event tile
  Widget _buildEventTile(BuildContext context, GeofenceEvent event) {
    final theme = Theme.of(context);

    // Event icon and color
    IconData icon;
    Color color;
    switch (event.eventType) {
      case 'entry':
        icon = Icons.login;
        color = Colors.green;
        break;
      case 'exit':
        icon = Icons.logout;
        color = Colors.orange;
        break;
      case 'dwell':
        icon = Icons.schedule;
        color = Colors.blue;
        break;
      default:
        icon = Icons.place;
        color = theme.colorScheme.primary;
    }

    // Format timestamp
    final timestamp = _formatEventTime(event.timestamp);

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        contentPadding: EdgeInsets.zero,
        leading: CircleAvatar(
          backgroundColor: color.withOpacity(0.1),
          child: Icon(icon, color: color, size: 20),
        ),
        title: Text(
          event.eventType.toUpperCase(),
          style: theme.textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.w500,
          ),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            Row(
              children: [
                Icon(
                  Icons.smartphone,
                  size: 14,
                  color: theme.textTheme.bodySmall?.color,
                ),
                const SizedBox(width: 4),
                Text(
                  event.deviceName.isNotEmpty
                      ? event.deviceName
                      : event.deviceId,
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
            const SizedBox(height: 2),
            Row(
              children: [
                Icon(
                  Icons.access_time,
                  size: 14,
                  color: theme.textTheme.bodySmall?.color,
                ),
                const SizedBox(width: 4),
                Text(
                  timestamp,
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
          ],
        ),
        trailing: Chip(
          label: Text(
            event.status,
            style: theme.textTheme.labelSmall,
          ),
          backgroundColor: event.status == 'pending'
              ? Colors.orange.withOpacity(0.2)
              : event.status == 'acknowledged'
                  ? Colors.green.withOpacity(0.2)
                  : theme.colorScheme.surfaceVariant,
          visualDensity: VisualDensity.compact,
        ),
      ),
    );
  }

  /// Build info row
  Widget _buildInfoRow(
    BuildContext context, {
    required IconData icon,
    required String label,
    required String value,
  }) {
    final theme = Theme.of(context);

    return Row(
      children: [
        Icon(icon, size: 16, color: theme.textTheme.bodySmall?.color),
        const SizedBox(width: 8),
        Text(
          '$label: ',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    );
  }

  /// Build error state
  Widget _buildErrorState(BuildContext context, Object error) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.error_outline,
              size: 64,
              color: colorScheme.error,
            ),
            const SizedBox(height: 16),
            Text(
              'Error Loading Geofence',
              style: theme.textTheme.titleLarge?.copyWith(
                color: colorScheme.error,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              error.toString(),
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              icon: const Icon(Icons.arrow_back),
              label: const Text('Go Back'),
              onPressed: () => context.safePop<void>(),
            ),
          ],
        ),
      ),
    );
  }

  /// Build floating action button
  Widget _buildFAB(BuildContext context, Geofence geofence) {
    return FloatingActionButton.extended(
      icon: const Icon(Icons.edit_location),
      label: const Text('Edit on Map'),
      onPressed: () => context.safePush<void>('/geofences/$geofenceId/edit'),
    );
  }

  /// Toggle geofence enabled state
  Future<void> _toggleGeofence(
    BuildContext context,
    WidgetRef ref,
    Geofence geofence,
    bool enabled,
  ) async {
    try {
      // Await repository initialization before updating
      final repo = await ref.read(geofenceRepositoryProvider.future);
      final updated = geofence.copyWith(enabled: enabled);
      await repo.updateGeofence(updated);

      // Invalidate providers to trigger immediate UI update
      ref.invalidate(geofencesProvider);
      ref.invalidate(geofenceStatsProvider);

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              enabled
                  ? '${geofence.name} enabled'
                  : '${geofence.name} disabled',
            ),
            backgroundColor: Colors.green[700],
            duration: const Duration(seconds: 2),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error updating geofence: $e'),
            backgroundColor: Theme.of(context).colorScheme.error,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  /// Confirm and delete geofence
  Future<void> _confirmDelete(
    BuildContext context,
    WidgetRef ref,
    Geofence geofence,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Geofence'),
        content: Text(
          'Are you sure you want to delete "${geofence.name}"?\n\n'
          'This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => context.safePop<bool>(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => context.safePop<bool>(true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true && context.mounted) {
      try {
        // Await repository initialization before deleting
        final repo = await ref.read(geofenceRepositoryProvider.future);
        await repo.deleteGeofence(geofence.id);

        // Invalidate providers to trigger immediate UI update
        ref.invalidate(geofencesProvider);
        ref.invalidate(geofenceStatsProvider);

        if (context.mounted) {
          context.safePop<void>(); // Return to list
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('${geofence.name} deleted'),
              backgroundColor: Colors.green[700],
              duration: const Duration(seconds: 2),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error deleting geofence: $e'),
              backgroundColor: Theme.of(context).colorScheme.error,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      }
    }
  }

  /// Duplicate geofence
  Future<void> _duplicateGeofence(
    BuildContext context,
    WidgetRef ref,
    Geofence geofence,
  ) async {
    try {
      // Await repository initialization before creating
      final repo = await ref.read(geofenceRepositoryProvider.future);
      final now = DateTime.now();

      // Create duplicate with new ID and updated name
      final duplicate = geofence.copyWith(
        id: 'geofence_${now.millisecondsSinceEpoch}',
        name: '${geofence.name} (Copy)',
        createdAt: now,
        updatedAt: now,
        version: 1,
        syncStatus: 'pending',
      );

      await repo.createGeofence(duplicate);

      // Invalidate providers to trigger immediate UI update
      ref.invalidate(geofencesProvider);
      ref.invalidate(geofenceStatsProvider);

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${geofence.name} duplicated'),
            backgroundColor: Colors.green[700],
            duration: const Duration(seconds: 2),
            behavior: SnackBarBehavior.floating,
            action: SnackBarAction(
              label: 'View',
              onPressed: () => context.safePush<void>('/geofences/${duplicate.id}'),
            ),
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error duplicating geofence: $e'),
            backgroundColor: Theme.of(context).colorScheme.error,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  /// Share geofence
  void _shareGeofence(BuildContext context, Geofence geofence) {
    // TODO: Implement sharing functionality
    // Could export as JSON, generate shareable link, etc.
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Share feature coming soon'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  /// View geofence on full map
  void _viewOnFullMap(BuildContext context, Geofence geofence) {
    // TODO: Navigate to map page with geofence highlighted
    // context.push('/map?highlight=$geofenceId');
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Map view coming soon'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  /// Format distance
  String _formatDistance(double meters) {
    if (meters >= 1000) {
      return '${(meters / 1000).toStringAsFixed(2)} km';
    } else {
      return '${meters.toStringAsFixed(0)} m';
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

  /// Format event timestamp
  String _formatEventTime(DateTime timestamp) {
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
        GoRoute(
          path: 'geofences',
          builder: (context, state) => const GeofenceListPage(),
          routes: [
            // Geofence details
            GoRoute(
              path: ':id',
              builder: (context, state) {
                final id = state.pathParameters['id']!;
                return GeofenceDetailPage(geofenceId: id);
              },
              routes: [
                // Edit geofence
                GoRoute(
                  path: 'edit',
                  builder: (context, state) {
                    final id = state.pathParameters['id']!;
                    return GeofenceEditPage(geofenceId: id);
                  },
                ),
                // Events list
                GoRoute(
                  path: 'events',
                  builder: (context, state) {
                    final id = state.pathParameters['id']!;
                    return GeofenceEventsPage(geofenceId: id);
                  },
                ),
              ],
            ),
            // Create geofence
            GoRoute(
              path: 'create',
              builder: (context, state) => const GeofenceCreatePage(),
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
/// Example: Navigate to detail page
void navigateToDetail(BuildContext context, String geofenceId) {
  context.safePush<void>('/geofences/$geofenceId');
}

/// Example: Deep link to edit with device section
void navigateToEditDevices(BuildContext context, String geofenceId) {
  context.safePush<void>('/geofences/$geofenceId/edit#devices');
}

/// Example: View all events for a geofence
void viewAllEvents(BuildContext context, String geofenceId) {
  context.safePush<void>('/geofences/$geofenceId/events');
}
*/
