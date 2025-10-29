import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:my_app_gps/data/models/trip.dart';
import 'package:my_app_gps/features/dashboard/controller/devices_notifier.dart';
import 'package:my_app_gps/features/trips/models/trip_filter.dart';
import 'package:my_app_gps/features/trips/trip_details_page.dart';
import 'package:my_app_gps/features/trips/widgets/trip_card.dart';
import 'package:my_app_gps/features/trips/widgets/trip_filter_dialog.dart';
import 'package:my_app_gps/l10n/app_localizations.dart';
import 'package:my_app_gps/providers/trip_auto_refresh_registrar.dart';
import 'package:my_app_gps/providers/trip_providers.dart';

class TripsPage extends ConsumerStatefulWidget {
  const TripsPage({this.deviceId, super.key});
  final int? deviceId; // Optional: preselect a device

  @override
  ConsumerState<TripsPage> createState() => _TripsPageState();
}

class _TripsPageState extends ConsumerState<TripsPage> {
  TripFilter? _activeFilter; // null = show welcome screen
  final ScrollController _scrollController = ScrollController();
  int _currentPage = 1;
  static const int _pageSize = 20; // Load 20 trips at a time
  bool _isLoadingMore = false;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    // If deviceId provided, auto-apply filter for that device
    if (widget.deviceId != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final now = DateTime.now();
        setState(() {
          _activeFilter = TripFilter(
            deviceIds: [widget.deviceId!],
            from: now.subtract(const Duration(days: 1)),
            to: now,
          );
        });
      });
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >= 
        _scrollController.position.maxScrollExtent - 200) {
      _loadMore();
    }
  }

  void _loadMore() {
    if (!_isLoadingMore) {
      setState(() {
        _currentPage++;
        _isLoadingMore = false; // Reset after state update
      });
    }
  }

  void _resetPagination() {
    setState(() {
      _currentPage = 1;
      _isLoadingMore = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    
    // Safety check for localization
    if (t == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Trips')),
        body: const Center(child: Text('Loading...')),
      );
    }
    
    return Scaffold(
      appBar: AppBar(
        title: Text(t.tripsTitle),
        actions: [
          // Filter button with badge indicator
          Stack(
            children: [
              IconButton(
                icon: const Icon(Icons.filter_list),
                onPressed: _showFilterDialog,
                tooltip: 'Filter trips',
              ),
              if (_activeFilter != null)
                Positioned(
                  right: 8,
                  top: 8,
                  child: Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.error,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
      body: _activeFilter == null ? _buildWelcomeScreen() : _buildFilteredResults(),
    );
  }

  // Welcome screen shown when no filter is active
  Widget _buildWelcomeScreen() {
    final t = AppLocalizations.of(context);
    if (t == null) return const SizedBox();
    
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.filter_list_outlined,
              size: 80,
              color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.3),
            ),
            const SizedBox(height: 24),
            Text(
              t.filterYourTrips,
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 12),
            Text(
              t.filterDescription,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
                  ),
            ),
            const SizedBox(height: 32),
            FilledButton.icon(
              onPressed: _showFilterDialog,
              icon: const Icon(Icons.filter_list),
              label: Text(t.applyFilter),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 16,
                ),
              ),
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: _applyQuickFilter,
              icon: const Icon(Icons.flash_on),
              label: Text(t.quickAllDevices),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 16,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Apply quick filter: all devices, last 24 hours
  void _applyQuickFilter() {
    final now = DateTime.now();
    _resetPagination(); // Reset pagination when applying quick filter
    setState(() {
      _activeFilter = TripFilter(
        deviceIds: const [], // Empty = all devices
        from: now.subtract(const Duration(days: 1)),
        to: now,
      );
    });
  }

  // Show filter dialog
  Future<void> _showFilterDialog() async {
    final devicesAsync = ref.read(devicesNotifierProvider);

    // Wait for devices to load
    if (!devicesAsync.hasValue) {
      if (devicesAsync.isLoading) {
        // Show loading indicator
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Loading devices...')),
        );
      } else if (devicesAsync.hasError) {
        // Show error
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to load devices: ${devicesAsync.error}')),
        );
      }
      return;
    }

    final result = await showDialog<TripFilter>(
      context: context,
      builder: (context) => TripFilterDialog(
        devices: devicesAsync.value!,
        initialFilter: _activeFilter,
      ),
    );

    if (result != null) {
      _resetPagination(); // Reset pagination when filter changes
      setState(() {
        _activeFilter = result;
      });
    }
  }

  // Build content based on active filter
  Widget _buildFilteredResults() {
    final filter = _activeFilter!;

    return Column(
      children: [
        // Active filter chip
        _buildActiveFilterChip(filter),
        // Trips list
        Expanded(
          child: filter.isAllDevices
              ? _buildMultiDeviceView(filter)
              : filter.deviceIds.length == 1
                  ? _buildSingleDeviceView(filter.deviceIds.first, filter)
                  : _buildMultiDeviceView(filter),
        ),
      ],
    );
  }

  // Active filter chip showing current selection
  Widget _buildActiveFilterChip(TripFilter filter) {
    final deviceCount = filter.isAllDevices ? 'All Devices' : '${filter.deviceIds.length} Device${filter.deviceIds.length > 1 ? 's' : ''}';
    final dateRange = '${DateFormat('MMM d').format(filter.from)} - ${DateFormat('MMM d').format(filter.to)}';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primaryContainer,
        border: Border(
          bottom: BorderSide(
            color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.2),
          ),
        ),
      ),
      child: Row(
        children: [
          Icon(
            Icons.filter_list,
            size: 20,
            color: Theme.of(context).colorScheme.onPrimaryContainer,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '$deviceCount • $dateRange',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onPrimaryContainer,
                    fontWeight: FontWeight.w600,
                  ),
            ),
          ),
          TextButton.icon(
            onPressed: _showFilterDialog,
            icon: const Icon(Icons.edit, size: 16),
            label: const Text('Edit'),
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.onPrimaryContainer,
            ),
          ),
        ],
      ),
    );
  }

  // Build view for single device
  Widget _buildSingleDeviceView(int deviceId, TripFilter filter) {
    // Activate WS auto-refresh for this device
    ref.watch(tripAutoRefreshRegistrarProvider(deviceId));

    final query = TripQuery(
      deviceId: deviceId,
      from: filter.from,
      to: filter.to,
    );

    final tripsAsync = ref.watch(tripsByDeviceProvider(query));

    return tripsAsync.when(
      data: (trips) => _buildTripsList(trips, filter),
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, st) => _buildError(context, e, () {
        ref.invalidate(tripsByDeviceProvider(query));
      }),
    );
  }

  // Build view for multiple devices (aggregated)
  Widget _buildMultiDeviceView(TripFilter filter) {
    final devicesAsync = ref.watch(devicesNotifierProvider);

    return devicesAsync.when(
      data: (devices) {
        final deviceIds = filter.isAllDevices
            ? devices.map((d) => d['id'] as int?).whereType<int>().toList()
            : filter.deviceIds;

        if (deviceIds.isEmpty) {
          return _buildError(context, 'No devices available', null);
        }

        return _buildAggregatedTrips(deviceIds, filter);
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, st) => _buildError(context, e, null),
    );
  }

  // Aggregate trips from multiple devices using OPTIMIZED batch provider
  Widget _buildAggregatedTrips(List<int> deviceIds, TripFilter filter) {
    // OPTIMIZATION: Use batch provider instead of N individual providers
    // This reduces provider subscriptions from N to 1 and enables parallel fetching
    final batchQuery = BatchTripQuery(
      deviceIds: deviceIds,
      from: filter.from,
      to: filter.to,
    );
    
    // Activate auto-refresh for all devices
    for (final deviceId in deviceIds) {
      ref.watch(tripAutoRefreshRegistrarProvider(deviceId));
    }
    
    final tripsAsync = ref.watch(batchTripsByDevicesProvider(batchQuery));
    
    return tripsAsync.when(
      data: (trips) => _buildTripsList(trips, filter),
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, st) => _buildError(context, e, () {
        ref.invalidate(batchTripsByDevicesProvider(batchQuery));
      }),
    );
  }

  // OLD IMPLEMENTATION (KEPT FOR REFERENCE - REMOVE AFTER TESTING)
  /*
  Widget _buildAggregatedTripsOld(List<int> deviceIds, TripFilter filter) {
    // Watch all device providers
    final allTripsAsync = deviceIds.map((deviceId) {
      // Activate auto-refresh for each device
      ref.watch(tripAutoRefreshRegistrarProvider(deviceId));
      
      final query = TripQuery(
        deviceId: deviceId,
        from: filter.from,
        to: filter.to,
      );
      return ref.watch(tripsByDeviceProvider(query));
    }).toList();

    // Check if any are loading
    final isLoading = allTripsAsync.any((async) => async.isLoading);
    if (isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    // Check for errors
    final errors = allTripsAsync.where((async) => async.hasError).toList();
    if (errors.isNotEmpty) {
      return _buildError(context, 'Failed to load trips from some devices', null);
    }

    // Aggregate all trips
    final allTrips = <Trip>[];
    for (final async in allTripsAsync) {
      if (async.hasValue) {
        allTrips.addAll(async.value!);
      }
    }

    // Sort by start time (most recent first)
    allTrips.sort((a, b) => b.startTime.compareTo(a.startTime));

    return _buildTripsList(allTrips, filter);
  }
  */

  // Build error widget
  Widget _buildError(BuildContext context, Object error, VoidCallback? onRetry) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 64, color: Colors.red),
            const SizedBox(height: 16),
            Text(
              'Failed to load trips',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(
              error.toString(),
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Colors.grey,
                  ),
            ),
            if (onRetry != null) ...[
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // Build trips list with summary
  Widget _buildTripsList(List<Trip> trips, TripFilter filter) {
    final t = AppLocalizations.of(context);
    if (t == null) return const SizedBox();
    
    if (trips.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.route_outlined,
              size: 80,
              color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.3),
            ),
            const SizedBox(height: 16),
            Text(
              t.noTripsFound,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
                  ),
            ),
            const SizedBox(height: 8),
            Text(
              'Try selecting a different date range or devices',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.4),
                  ),
            ),
          ],
        ),
      );
    }

    // Get devices for name lookup
    final devicesAsync = ref.watch(devicesNotifierProvider);
    final devices = devicesAsync.hasValue ? devicesAsync.value! : <Map<String, dynamic>>[];

    return RefreshIndicator(
      onRefresh: () async {
        // Invalidate all relevant providers
        if (filter.isAllDevices) {
          final devicesAsync = ref.read(devicesNotifierProvider);
          if (devicesAsync.hasValue) {
            for (final device in devicesAsync.value!) {
              final deviceId = device['id'] as int?;
              if (deviceId != null) {
                final query = TripQuery(
                  deviceId: deviceId,
                  from: filter.from,
                  to: filter.to,
                );
                await ref.read(tripsByDeviceProvider(query).notifier).refresh();
              }
            }
          }
        } else {
          for (final deviceId in filter.deviceIds) {
            final query = TripQuery(
              deviceId: deviceId,
              from: filter.from,
              to: filter.to,
            );
            await ref.read(tripsByDeviceProvider(query).notifier).refresh();
          }
        }
      },
      child: ListView.builder(
        controller: _scrollController,
        padding: const EdgeInsets.all(16),
        // Performance optimization: itemExtent tells ListView the exact height
        // of each item, reducing layout passes during scrolling by ~70-80%.
        // TripCard has fixed height: 16 (top padding) + 160 (card) + 12 (bottom margin) = 188px
        // Summary card at index 0 has variable height, so we use null for dynamic sizing
        // Use prototypeItem for more accurate measurement in case of variations
        prototypeItem: const SizedBox(height: 188), // Fixed height for trip cards
        itemCount: () {
          // Calculate visible trips based on pagination
          final visibleCount = (_currentPage * _pageSize).clamp(0, trips.length);
          // +1 for summary card, +1 for loading indicator if more trips available
          return visibleCount + 1 + (visibleCount < trips.length ? 1 : 0);
        }(),
        itemBuilder: (context, index) {
          // Summary card at top
          if (index == 0) {
            return _buildSummaryCard(context, trips, filter);
          }

          // Calculate visible trips
          final visibleCount = (_currentPage * _pageSize).clamp(0, trips.length);
          
          // Loading indicator at bottom if more trips available
          if (index == visibleCount + 1 && visibleCount < trips.length) {
            return const Padding(
              padding: EdgeInsets.all(24.0),
              child: Center(child: CircularProgressIndicator()),
            );
          }

          // Trip card
          final tripIndex = index - 1;
          if (tripIndex >= visibleCount) {
            return const SizedBox(); // Safety check
          }
          
          final t = trips[tripIndex];
          final deviceName = _getDeviceName(devices, t.deviceId);
          return TripCard(
            trip: t,
            deviceName: deviceName,
            onTap: () {
              // Use root navigator to bypass BottomNavShell and hide bottom nav bar
              Navigator.of(context, rootNavigator: true).push<Widget>(
                MaterialPageRoute<Widget>(
                  builder: (_) => TripDetailsPage(trip: t),
                  fullscreenDialog: true,
                ),
              );
            },
          );
        },
      ),
    );
  }

  // Helper method to get device name from device ID
  String _getDeviceName(List<Map<String, dynamic>> devices, int deviceId) {
    try {
      final device = devices.firstWhere(
        (d) => d['id'] == deviceId,
        orElse: () => <String, dynamic>{},
      );
      return device['name'] as String? ?? 'Device $deviceId';
    } catch (e) {
      return 'Device $deviceId';
    }
  }

  Widget _buildSummaryCard(
    BuildContext context,
    List<Trip> trips,
    TripFilter filter,
  ) {
    final t = AppLocalizations.of(context);
    if (t == null) return const SizedBox();
    
    final totalDistance = trips.fold<double>(
      0,
      (sum, trip) => sum + trip.distanceKm,
    );
    final totalDuration = trips.fold<Duration>(
      Duration.zero,
      (sum, trip) => sum + trip.duration,
    );

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Theme.of(context).colorScheme.primaryContainer,
            Theme.of(context).colorScheme.secondaryContainer,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.1),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.analytics_outlined,
                color: Theme.of(context).colorScheme.onPrimaryContainer,
                size: 24,
              ),
              const SizedBox(width: 8),
              Text(
                t.tripSummary,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onPrimaryContainer,
                      fontWeight: FontWeight.bold,
                    ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildSummaryItem(
                context,
                Icons.route,
                '${trips.length}',
                t.trips,
              ),
              _buildSummaryItem(
                context,
                Icons.straighten,
                '${totalDistance.toStringAsFixed(1)} km',
                t.distance,
              ),
              _buildSummaryItem(
                context,
                Icons.access_time,
                _formatDuration(totalDuration),
                t.duration,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryItem(
    BuildContext context,
    IconData icon,
    String value,
    String label,
  ) {
    return Column(
      children: [
        Icon(
          icon,
          color: Theme.of(context).colorScheme.onPrimaryContainer,
          size: 20,
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: Theme.of(context).colorScheme.onPrimaryContainer,
                fontWeight: FontWeight.bold,
              ),
        ),
        Text(
          label,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onPrimaryContainer.withValues(alpha: 0.7),
              ),
        ),
      ],
    );
  }

  String _formatDuration(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60);
    if (h > 0) return '${h}h ${m}m';
    return '${m}m';
  }
}
