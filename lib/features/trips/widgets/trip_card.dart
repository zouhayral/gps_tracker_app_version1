import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:my_app_gps/data/models/trip.dart';
import 'package:my_app_gps/l10n/app_localizations.dart';

/// Optimized TripCard widget for high-performance list rendering.
/// 
/// Key optimizations:
/// - Extracted as separate StatelessWidget for better widget recycling
/// - Wrapped in RepaintBoundary to isolate repaints
/// - Const constructors where possible to reduce allocations
/// - Simplified shadows (blur: 2) to reduce GPU load
/// - Removed gradients, using solid colors
/// - Reduced elevation from 4 to 2
/// - Body extracted to _TripCardBody subwidget for cleaner structure
class TripCard extends StatelessWidget {
  const TripCard({
    required this.trip,
    required this.deviceName,
    required this.onTap,
    super.key,
  });

  final Trip trip;
  final String deviceName;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    // RepaintBoundary isolates this card's repaints from parent/siblings
    // This prevents one card's animation from causing others to repaint
    return RepaintBoundary(
      child: Card(
        elevation: 2, // Reduced from 4 for less shadow rendering cost
        shadowColor: Colors.black26, // Simplified shadow color
        margin: const EdgeInsets.only(bottom: 12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(
            color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.2),
          ),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: _TripCardBody(
              trip: trip,
              deviceName: deviceName,
            ),
          ),
        ),
      ),
    );
  }
}

/// Internal body widget for TripCard.
/// Extracted to separate widget for cleaner code structure and potential
/// future optimization (e.g., selective rebuilds if trip data changes).
class _TripCardBody extends StatelessWidget {
  const _TripCardBody({
    required this.trip,
    required this.deviceName,
  });

  final Trip trip;
  final String deviceName;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    if (t == null) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        // Device name header
        _DeviceNameChip(deviceName: deviceName),
        const SizedBox(height: 8),
        
        // Date and navigation indicator row
        _DateRow(startTime: trip.startTime),
        const SizedBox(height: 8),
        
        // Time range
        _TimeRangeRow(
          startTime: trip.startTime,
          endTime: trip.endTime,
        ),
        const SizedBox(height: 10),

        // Trip statistics
        _TripStatsRow(trip: trip, t: t),
      ],
    );
  }
}

/// Device name chip widget.
class _DeviceNameChip extends StatelessWidget {
  const _DeviceNameChip({required this.deviceName});

  final String deviceName;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 8,
        vertical: 3,
      ),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.secondaryContainer,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.directions_car,
            size: 12,
            color: Theme.of(context).colorScheme.onSecondaryContainer,
          ),
          const SizedBox(width: 5),
          Text(
            deviceName,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSecondaryContainer,
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
          ),
        ],
      ),
    );
  }
}

/// Date display row with navigation indicator.
class _DateRow extends StatelessWidget {
  const _DateRow({required this.startTime});

  final DateTime startTime;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(
            horizontal: 10,
            vertical: 4,
          ),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.primaryContainer,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.calendar_today,
                size: 12,
                color: Theme.of(context).colorScheme.onPrimaryContainer,
              ),
              const SizedBox(width: 5),
              Text(
                DateFormat('MMM d').format(startTime),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onPrimaryContainer,
                      fontWeight: FontWeight.w600,
                      fontSize: 12,
                    ),
              ),
            ],
          ),
        ),
        const Spacer(),
        Icon(
          Icons.arrow_forward_ios,
          size: 14,
          color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.3),
        ),
      ],
    );
  }
}

/// Time range display row (start → end).
class _TimeRangeRow extends StatelessWidget {
  const _TimeRangeRow({
    required this.startTime,
    required this.endTime,
  });

  final DateTime startTime;
  final DateTime endTime;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(
          Icons.schedule,
          size: 14,
          color: Theme.of(context).colorScheme.primary,
        ),
        const SizedBox(width: 6),
        Text(
          DateFormat('HH:mm').format(startTime),
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: Icon(
            Icons.arrow_forward,
            size: 14,
            color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.4),
          ),
        ),
        Text(
          DateFormat('HH:mm').format(endTime),
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
        ),
      ],
    );
  }
}

/// Trip statistics row showing duration, distance, and average speed.
class _TripStatsRow extends StatelessWidget {
  const _TripStatsRow({
    required this.trip,
    required this.t,
  });

  final Trip trip;
  final AppLocalizations t;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _TripStatItem(
            icon: Icons.timer_outlined,
            value: _formatDuration(trip.duration),
            label: t.duration,
          ),
        ),
        Container(
          width: 1,
          height: 38,
          margin: const EdgeInsets.symmetric(horizontal: 8),
          color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.2),
        ),
        Expanded(
          child: _TripStatItem(
            icon: Icons.straighten,
            value: trip.formattedDistanceKm,
            label: t.distance,
          ),
        ),
        Container(
          width: 1,
          height: 38,
          margin: const EdgeInsets.symmetric(horizontal: 8),
          color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.2),
        ),
        Expanded(
          child: _TripStatItem(
            icon: Icons.speed,
            value: trip.formattedAvgSpeed,
            label: t.avgSpeed,
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

/// Individual trip statistic item (icon, value, label).
class _TripStatItem extends StatelessWidget {
  const _TripStatItem({
    required this.icon,
    required this.value,
    required this.label,
  });

  final IconData icon;
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          icon,
          size: 14,
          color: Theme.of(context).colorScheme.primary,
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.bold,
                fontSize: 12,
              ),
          textAlign: TextAlign.center,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 1),
        Text(
          label,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
                fontSize: 10,
              ),
          textAlign: TextAlign.center,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }
}
