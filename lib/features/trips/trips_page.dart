import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:my_app_gps/app/app_router.dart';
import 'package:my_app_gps/data/models/trip.dart';
import 'package:my_app_gps/features/trips/trip_details_page.dart';
import 'package:my_app_gps/providers/trip_auto_refresh_registrar.dart';
import 'package:my_app_gps/providers/trip_providers.dart';

class TripsPage extends ConsumerStatefulWidget {
  const TripsPage({this.deviceId = 1, super.key});
  final int deviceId;

  @override
  ConsumerState<TripsPage> createState() => _TripsPageState();
}

class _TripsPageState extends ConsumerState<TripsPage> {
  late DateTime _from;
  late DateTime _to;
  late TripQuery _currentQuery;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _to = now;
    _from = now.subtract(const Duration(days: 1));
    _currentQuery = TripQuery(
      deviceId: widget.deviceId,
      from: _from,
      to: _to,
    );
  }

  @override
  Widget build(BuildContext context) {
    // Activate WS auto-refresh listener while page is alive
    ref.watch(tripAutoRefreshRegistrarProvider(widget.deviceId));
    // Use range-aware provider so the calendar selection drives the query
    final tripsAsync = ref.watch(tripsByDeviceProvider(_currentQuery));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Trips'),
        actions: [
          IconButton(
            icon: const Icon(Icons.insights),
            tooltip: 'Analytics',
            onPressed: () => context.push(AppRoutes.tripAnalytics),
          ),
          IconButton(
            icon: const Icon(Icons.date_range),
            onPressed: _pickRange,
            tooltip: 'Select date range',
          ),
        ],
      ),
      body: tripsAsync.when(
        data: (trips) => _buildList(context, trips),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, st) => _buildError(context, e),
      ),
    );
  }

  Widget _buildError(BuildContext context, Object error) {
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
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: () {
                ref.invalidate(tripsByDeviceProvider(_currentQuery));
              },
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickRange() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: now.subtract(const Duration(days: 365)),
      lastDate: now,
      initialDateRange: DateTimeRange(start: _from, end: _to),
    );
    if (picked != null) {
      setState(() {
        _from = DateTime(picked.start.year, picked.start.month, picked.start.day);
        _to = DateTime(picked.end.year, picked.end.month, picked.end.day, 23, 59, 59);
        // Update query to trigger provider refresh with new date range
        _currentQuery = TripQuery(
          deviceId: widget.deviceId,
          from: _from,
          to: _to,
        );
      });
    }
  }

  Widget _buildList(BuildContext context, List<Trip> trips) {
    if (trips.isEmpty) {
      return const Center(child: Text('No trips in selected range'));
    }
    return RefreshIndicator(
      onRefresh: () async {
        await ref.read(tripsByDeviceProvider(_currentQuery).notifier).refresh();
      },
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
        itemCount: trips.length,
        itemBuilder: (context, index) {
          final t = trips[index];
          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: ListTile(
              key: ValueKey('trip-${t.id}'),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: Theme.of(context).dividerColor)),
              title: Text(_formatRange(t.startTime, t.endTime)),
              subtitle: Text('${_formatDuration(t.duration)} • ${t.formattedDistanceKm} • ${t.formattedAvgSpeed} avg'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {
                Navigator.push<Widget>(
                  context,
                  MaterialPageRoute<Widget>(builder: (_) => TripDetailsPage(trip: t)),
                );
              },
            ),
          );
        },
      ),
    );
  }

  String _formatRange(DateTime a, DateTime b) {
    final df = DateFormat('MMM d, HH:mm');
    return '${df.format(a)} → ${df.format(b)}';
  }

  String _formatDuration(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60);
    if (h > 0) return '${h}h ${m}m';
    return '${m}m';
  }
}
