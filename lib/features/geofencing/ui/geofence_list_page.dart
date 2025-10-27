import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:my_app_gps/core/navigation/safe_navigation.dart';
import 'package:my_app_gps/data/models/geofence.dart';
import 'package:my_app_gps/features/geofencing/providers/geofence_providers.dart';
import 'package:my_app_gps/l10n/app_localizations.dart';

/// Main page for viewing and managing geofences.
///
/// This page displays a list of all geofences with the ability to:
/// - View geofence details
/// - Enable/disable geofences
/// - Edit and delete geofences
/// - Filter and sort geofences
/// - View monitoring status
/// - Create new geofences
///
/// ## Navigation
/// Route: `/geofences`
///
/// ## Example Usage in GoRouter
/// ```dart
/// GoRoute(
///   path: '/geofences',
///   builder: (context, state) => const GeofenceListPage(),
/// ),
/// ```
///
/// ## Features
/// - Pull-to-refresh
/// - Real-time updates via Riverpod streams
/// - Material Design 3 styling
/// - Light + dark mode support
/// - Empty state with call-to-action
/// - Bottom stats bar
/// - Filter and sort options
class GeofenceListPage extends ConsumerStatefulWidget {
  const GeofenceListPage({super.key});

  @override
  ConsumerState<GeofenceListPage> createState() => _GeofenceListPageState();
}

class _GeofenceListPageState extends ConsumerState<GeofenceListPage> {
  // Filter state
  GeofenceTypeFilter _typeFilter = GeofenceTypeFilter.all;
  GeofenceStatusFilter _statusFilter = GeofenceStatusFilter.all;
  GeofenceSortOption _sortOption = GeofenceSortOption.name;

  // Search state
  String _searchQuery = '';
  bool _isSearching = false;
  final TextEditingController _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final geofencesAsync = ref.watch(geofencesProvider);
    final statsAsync = ref.watch(geofenceStatsProvider);
    final isMonitoring = ref.watch(isMonitoringActiveProvider);

    return Scaffold(
      appBar: _buildAppBar(context),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(geofencesProvider);
          ref.invalidate(geofenceStatsProvider);
        },
        child: geofencesAsync.when(
          data: (geofences) {
            // Apply filters and search
            final filteredGeofences = _applyFilters(geofences);

            return _buildContent(context, filteredGeofences);
          },
          loading: () => const Center(
            child: CircularProgressIndicator(),
          ),
          error: (error, stackTrace) => _buildErrorState(context, error),
        ),
      ),
      floatingActionButton: _buildFAB(context),
      bottomNavigationBar: statsAsync.when(
        data: (stats) => _buildStatsBar(context, stats, isMonitoring),
        loading: () => null,
        error: (_, __) => null,
      ),
    );
  }

  /// Build app bar with search and actions
  PreferredSizeWidget _buildAppBar(BuildContext context) {
    if (_isSearching) {
      return AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            setState(() {
              _isSearching = false;
              _searchQuery = '';
              _searchController.clear();
            });
          },
        ),
        title: TextField(
          controller: _searchController,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'Search geofences...',
            border: InputBorder.none,
          ),
          onChanged: (value) {
            setState(() {
              _searchQuery = value.toLowerCase();
            });
          },
        ),
        actions: [
          if (_searchQuery.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.clear),
              onPressed: () {
                setState(() {
                  _searchQuery = '';
                  _searchController.clear();
                });
              },
            ),
        ],
      );
    }

    final t = AppLocalizations.of(context);
    
    return AppBar(
      title: Text(t?.geofences ?? 'Geofences'),
      actions: [
        IconButton(
          icon: const Icon(Icons.search),
          tooltip: 'Search',
          onPressed: () {
            setState(() {
              _isSearching = true;
            });
          },
        ),
        IconButton(
          icon: const Icon(Icons.filter_list),
          tooltip: 'Filter & Sort',
          onPressed: () => _openFilterSheet(context),
        ),
        IconButton(
          icon: const Icon(Icons.settings),
          tooltip: 'Geofence Settings',
          onPressed: () => context.safePush<void>('/geofences/settings'),
        ),
        IconButton(
          icon: const Icon(Icons.refresh),
          tooltip: 'Refresh',
          onPressed: () {
            ref.invalidate(geofencesProvider);
            ref.invalidate(geofenceStatsProvider);
          },
        ),
      ],
    );
  }

  /// Build main content (list or empty state)
  Widget _buildContent(BuildContext context, List<Geofence> geofences) {
    if (geofences.isEmpty) {
      return _buildEmptyState(context);
    }

    return ListView.builder(
      padding: const EdgeInsets.only(
        top: 8,
        bottom: 80, // Space for FAB
      ),
      itemCount: geofences.length,
      itemBuilder: (context, index) {
        final geofence = geofences[index];
        return _buildGeofenceTile(context, geofence);
      },
    );
  }

  /// Build individual geofence list tile
  Widget _buildGeofenceTile(BuildContext context, Geofence geofence) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    // Get last event for this geofence
    final eventsAsync = ref.watch(eventsByGeofenceProvider(geofence.id));
    final lastEvent = eventsAsync.when(
      data: (events) => events.isNotEmpty ? events.first : null,
      loading: () => null,
      error: (_, __) => null,
    );

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: ListTile(
        // Type icon
        leading: CircleAvatar(
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

        // Name and subtitle
        title: Text(
          geofence.name,
          style: theme.textTheme.titleMedium?.copyWith(
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
                  Icons.devices,
                  size: 14,
                  color: theme.textTheme.bodySmall?.color,
                ),
                const SizedBox(width: 4),
                Text(
                  '${geofence.monitoredDevices.length} device(s)',
                  style: theme.textTheme.bodySmall,
                ),
                if (lastEvent != null) ...[
                  const SizedBox(width: 12),
                  Icon(
                    Icons.access_time,
                    size: 14,
                    color: theme.textTheme.bodySmall?.color,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    _formatLastEvent(lastEvent.timestamp),
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ],
            ),
            const SizedBox(height: 4),
            _buildNotificationBadges(context, geofence),
          ],
        ),

        // Enable/disable switch
        trailing: Switch(
          value: geofence.enabled,
          onChanged: (enabled) => _toggleGeofence(geofence, enabled),
        ),

        // Tap to view details
        onTap: () async {
          await context.safePush<void>('/geofences/${geofence.id}');
        },
      ),
    );
  }

  /// Build notification type badges
  Widget _buildNotificationBadges(BuildContext context, Geofence geofence) {
    final theme = Theme.of(context);
    final chips = <Widget>[];
    final t = AppLocalizations.of(context);

    // Notification type chip
    if (geofence.notificationType != 'none') {
      chips.add(
        Chip(
          label: Text(
            geofence.notificationType == 'local' 
                ? (t?.local ?? geofence.notificationType)
                : geofence.notificationType == 'push'
                    ? (t?.push ?? geofence.notificationType)
                    : (t?.both ?? geofence.notificationType),
            style: theme.textTheme.labelSmall,
          ),
          avatar: Icon(
            geofence.notificationType == 'local'
                ? Icons.notifications
                : geofence.notificationType == 'push'
                    ? Icons.cloud
                    : Icons.notifications_active,
            size: 16,
          ),
          visualDensity: VisualDensity.compact,
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
      );
    }

    // Trigger chips
    if (geofence.onEnter) {
      chips.add(
        Chip(
          label: Text(t?.entry ?? 'Entry', style: theme.textTheme.labelSmall),
          avatar: const Icon(Icons.login, size: 16),
          visualDensity: VisualDensity.compact,
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
      );
    }

    if (geofence.onExit) {
      chips.add(
        Chip(
          label: Text(t?.exit ?? 'Exit', style: theme.textTheme.labelSmall),
          avatar: const Icon(Icons.logout, size: 16),
          visualDensity: VisualDensity.compact,
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
      );
    }

    if (geofence.dwellMs != null && geofence.dwellMs! > 0) {
      chips.add(
        Chip(
          label: Text(
            'Dwell ${_formatDuration(Duration(milliseconds: geofence.dwellMs!))}',
            style: theme.textTheme.labelSmall,
          ),
          avatar: const Icon(Icons.schedule, size: 16),
          visualDensity: VisualDensity.compact,
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
      );
    }

    if (chips.isEmpty) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Wrap(
        spacing: 4,
        runSpacing: 4,
        children: chips,
      ),
    );
  }

  /// Build empty state
  Widget _buildEmptyState(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    String message = 'No geofences yet';
    String hint = 'Create your first geofence to get started';

    if (_searchQuery.isNotEmpty) {
      message = 'No results found';
      hint = 'Try adjusting your search or filters';
    } else if (_typeFilter != GeofenceTypeFilter.all ||
        _statusFilter != GeofenceStatusFilter.all) {
      message = 'No matching geofences';
      hint = 'Try different filter options';
    }

    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.only(bottom: 80), // Avoid bottom nav overlap
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.fence,
                  size: 64,
                  color: colorScheme.outline,
                ),
                const SizedBox(height: 16),
                Text(
                  message,
                  style: theme.textTheme.titleLarge?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  hint,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                  textAlign: TextAlign.center,
                ),
                if (_searchQuery.isEmpty &&
                    _typeFilter == GeofenceTypeFilter.all &&
                    _statusFilter == GeofenceStatusFilter.all) ...[
                  const SizedBox(height: 24),
                  FilledButton.icon(
                    icon: const Icon(Icons.add),
                    label: const Text('Create Geofence'),
                    onPressed: () => context.safePush<void>('/geofences/create'),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Build error state
  Widget _buildErrorState(BuildContext context, Object error) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.only(bottom: 80), // Avoid bottom nav overlap
        child: Center(
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
                  'Error Loading Geofences',
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
                  icon: const Icon(Icons.refresh),
                  label: const Text('Retry'),
                  onPressed: () {
                    ref.invalidate(geofencesProvider);
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Build floating action button
  Widget _buildFAB(BuildContext context) {
    final t = AppLocalizations.of(context);
    return FloatingActionButton.extended(
      icon: const Icon(Icons.add),
      label: Text(t?.createGeofence ?? 'Create'),
      onPressed: () => context.safePush<void>('/geofences/create'),
    );
  }

  /// Build stats bar at bottom
  Widget? _buildStatsBar(
    BuildContext context,
    GeofenceStats stats,
    bool isMonitoring,
  ) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final t = AppLocalizations.of(context);

    return SafeArea(
      child: BottomAppBar(
        height: null, // Allow dynamic height based on content
        padding: EdgeInsets.zero, // Remove default padding
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            border: Border(
              top: BorderSide(
                color: theme.colorScheme.outlineVariant.withOpacity(0.5),
                width: 1,
              ),
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            mainAxisSize: MainAxisSize.min,
            children: [
              // Total count
              _buildStatItem(
                context,
                icon: Icons.fence,
                label: t?.total ?? 'Total',
                value: stats.total.toString(),
              ),

              // Active count
              _buildStatItem(
                context,
                icon: Icons.check_circle,
                label: t?.active ?? 'Active',
                value: stats.active.toString(),
                color: stats.active > 0 ? Colors.green : null,
              ),

              // Unacknowledged events
              _buildStatItem(
                context,
                icon: Icons.notification_important,
                label: t?.alertsTitle ?? 'Alerts',
                value: stats.unacknowledgedEvents.toString(),
                color: stats.unacknowledgedEvents > 0 ? Colors.orange : null,
              ),

              // Monitoring status
              Flexible(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      isMonitoring
                          ? Icons.play_circle_filled
                          : Icons.pause_circle_filled,
                      color: isMonitoring ? Colors.green : colorScheme.outline,
                      size: 20, // Reduced from 28 for consistency
                    ),
                    const SizedBox(height: 1), // Reduced spacing
                    Text(
                      isMonitoring ? (t?.active ?? 'Active') : (t?.paused ?? 'Paused'),
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: isMonitoring ? Colors.green : colorScheme.outline,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Build individual stat item
  Widget _buildStatItem(
    BuildContext context, {
    required IconData icon,
    required String label,
    required String value,
    Color? color,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final effectiveColor = color ?? colorScheme.onSurface;

    return Flexible(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            color: effectiveColor,
            size: 20, // Reduced from 24 to fit better
          ),
          const SizedBox(height: 1), // Reduced from 2
          Text(
            value,
            style: theme.textTheme.titleSmall?.copyWith( // Changed from titleMedium
              color: effectiveColor,
              fontWeight: FontWeight.bold,
            ),
          ),
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: effectiveColor,
            ),
            overflow: TextOverflow.ellipsis, // Prevent text overflow
          ),
        ],
      ),
    );
  }

  /// Open filter and sort bottom sheet
  void _openFilterSheet(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      builder: (context) => _FilterSheet(
        currentTypeFilter: _typeFilter,
        currentStatusFilter: _statusFilter,
        currentSortOption: _sortOption,
        onApply: (type, status, sort) {
          setState(() {
            _typeFilter = type;
            _statusFilter = status;
            _sortOption = sort;
          });
          context.safePop<void>();
        },
      ),
    );
  }

  /// Apply filters and sorting to geofence list
  List<Geofence> _applyFilters(List<Geofence> geofences) {
    // Create a mutable copy to avoid "Cannot modify an unmodifiable list" error
    var filtered = List<Geofence>.from(geofences);

    // Apply search
    if (_searchQuery.isNotEmpty) {
      filtered = filtered.where((g) {
        return g.name.toLowerCase().contains(_searchQuery);
      }).toList();
    }

    // Apply type filter
    if (_typeFilter != GeofenceTypeFilter.all) {
      filtered = filtered.where((g) {
        return g.type == _typeFilter.name;
      }).toList();
    }

    // Apply status filter
    if (_statusFilter != GeofenceStatusFilter.all) {
      filtered = filtered.where((g) {
        return g.enabled == (_statusFilter == GeofenceStatusFilter.active);
      }).toList();
    }

    // Apply sorting
    switch (_sortOption) {
      case GeofenceSortOption.name:
        filtered.sort((a, b) => a.name.compareTo(b.name));
        break;
      case GeofenceSortOption.created:
        filtered.sort((a, b) => b.createdAt.compareTo(a.createdAt));
        break;
      case GeofenceSortOption.updated:
        filtered.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
        break;
    }

    return filtered;
  }

  /// Toggle geofence enabled state
  Future<void> _toggleGeofence(Geofence geofence, bool enabled) async {
    try {
      // Await repository initialization before updating
      final repo = await ref.read(geofenceRepositoryProvider.future);
      final updated = geofence.copyWith(enabled: enabled);
      await repo.updateGeofence(updated);

      // Invalidate providers to trigger immediate UI update
      ref.invalidate(geofencesProvider);
      ref.invalidate(geofenceStatsProvider);

      if (mounted) {
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
      if (mounted) {
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

  /// Format last event timestamp
  String _formatLastEvent(DateTime timestamp) {
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
      return DateFormat('MMM d').format(timestamp);
    }
  }

  /// Format duration
  String _formatDuration(Duration duration) {
    if (duration.inDays > 0) {
      return '${duration.inDays}d';
    } else if (duration.inHours > 0) {
      return '${duration.inHours}h';
    } else if (duration.inMinutes > 0) {
      return '${duration.inMinutes}m';
    } else {
      return '${duration.inSeconds}s';
    }
  }
}

// =============================================================================
// FILTER SHEET
// =============================================================================

/// Bottom sheet for filtering and sorting geofences
class _FilterSheet extends StatefulWidget {
  final GeofenceTypeFilter currentTypeFilter;
  final GeofenceStatusFilter currentStatusFilter;
  final GeofenceSortOption currentSortOption;
  final void Function(
    GeofenceTypeFilter type,
    GeofenceStatusFilter status,
    GeofenceSortOption sort,
  ) onApply;

  const _FilterSheet({
    required this.currentTypeFilter,
    required this.currentStatusFilter,
    required this.currentSortOption,
    required this.onApply,
  });

  @override
  State<_FilterSheet> createState() => _FilterSheetState();
}

class _FilterSheetState extends State<_FilterSheet> {
  late GeofenceTypeFilter _typeFilter;
  late GeofenceStatusFilter _statusFilter;
  late GeofenceSortOption _sortOption;

  @override
  void initState() {
    super.initState();
    _typeFilter = widget.currentTypeFilter;
    _statusFilter = widget.currentStatusFilter;
    _sortOption = widget.currentSortOption;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Filter & Sort',
                style: theme.textTheme.titleLarge,
              ),
              TextButton(
                onPressed: () {
                  setState(() {
                    _typeFilter = GeofenceTypeFilter.all;
                    _statusFilter = GeofenceStatusFilter.all;
                    _sortOption = GeofenceSortOption.name;
                  });
                },
                child: const Text('Reset'),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Type filter
          Text(
            'Type',
            style: theme.textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          SegmentedButton<GeofenceTypeFilter>(
            segments: const [
              ButtonSegment(
                value: GeofenceTypeFilter.all,
                label: Text('All'),
                icon: Icon(Icons.select_all),
              ),
              ButtonSegment(
                value: GeofenceTypeFilter.circle,
                label: Text('Circle'),
                icon: Icon(Icons.circle_outlined),
              ),
              ButtonSegment(
                value: GeofenceTypeFilter.polygon,
                label: Text('Polygon'),
                icon: Icon(Icons.polyline),
              ),
            ],
            selected: {_typeFilter},
            onSelectionChanged: (Set<GeofenceTypeFilter> selection) {
              setState(() {
                _typeFilter = selection.first;
              });
            },
          ),
          const SizedBox(height: 16),

          // Status filter
          Text(
            'Status',
            style: theme.textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          SegmentedButton<GeofenceStatusFilter>(
            segments: const [
              ButtonSegment(
                value: GeofenceStatusFilter.all,
                label: Text('All'),
                icon: Icon(Icons.select_all),
              ),
              ButtonSegment(
                value: GeofenceStatusFilter.active,
                label: Text('Active'),
                icon: Icon(Icons.check_circle),
              ),
              ButtonSegment(
                value: GeofenceStatusFilter.inactive,
                label: Text('Inactive'),
                icon: Icon(Icons.pause_circle),
              ),
            ],
            selected: {_statusFilter},
            onSelectionChanged: (Set<GeofenceStatusFilter> selection) {
              setState(() {
                _statusFilter = selection.first;
              });
            },
          ),
          const SizedBox(height: 16),

          // Sort option
          Text(
            'Sort By',
            style: theme.textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          SegmentedButton<GeofenceSortOption>(
            segments: const [
              ButtonSegment(
                value: GeofenceSortOption.name,
                label: Text('Name'),
                icon: Icon(Icons.sort_by_alpha),
              ),
              ButtonSegment(
                value: GeofenceSortOption.created,
                label: Text('Created'),
                icon: Icon(Icons.add_circle_outline),
              ),
              ButtonSegment(
                value: GeofenceSortOption.updated,
                label: Text('Updated'),
                icon: Icon(Icons.update),
              ),
            ],
            selected: {_sortOption},
            onSelectionChanged: (Set<GeofenceSortOption> selection) {
              setState(() {
                _sortOption = selection.first;
              });
            },
          ),
          const SizedBox(height: 24),

          // Apply button
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: () {
                widget.onApply(_typeFilter, _statusFilter, _sortOption);
              },
              child: const Text('Apply'),
            ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

// =============================================================================
// FILTER ENUMS
// =============================================================================

/// Geofence type filter options
enum GeofenceTypeFilter {
  all,
  circle,
  polygon,
}

/// Geofence status filter options
enum GeofenceStatusFilter {
  all,
  active,
  inactive,
}

/// Geofence sort options
enum GeofenceSortOption {
  name,
  created,
  updated,
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
        // Geofence list
        GoRoute(
          path: 'geofences',
          builder: (context, state) => const GeofenceListPage(),
          routes: [
            // Geofence creation
            GoRoute(
              path: 'create',
              builder: (context, state) => const GeofenceCreatePage(),
            ),
            // Geofence details
            GoRoute(
              path: ':id',
              builder: (context, state) {
                final id = state.pathParameters['id']!;
                return GeofenceDetailPage(geofenceId: id);
              },
              routes: [
                // Geofence edit
                GoRoute(
                  path: 'edit',
                  builder: (context, state) {
                    final id = state.pathParameters['id']!;
                    return GeofenceEditPage(geofenceId: id);
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
// USAGE EXAMPLE
// =============================================================================

/*
/// Example: Navigate to geofence list
class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'GPS Tracker',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.blue,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      routerConfig: router,
    );
  }
}

/// Example: Navigate programmatically
void navigateToGeofences(BuildContext context) {
  context.safeGo('/geofences');
}

/// Example: Navigate with named route
void navigateToGeofenceDetail(BuildContext context, String geofenceId) {
  context.safePush<void>('/geofences/$geofenceId');
}

/// Example: Navigate to create
void navigateToGeofenceCreate(BuildContext context) {
  context.safePush<void>('/geofences/create');
}
*/
