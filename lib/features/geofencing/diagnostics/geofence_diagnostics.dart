import 'package:intl/intl.dart';

/// Snapshot of geofence monitoring health for diagnostics overlays.
class GeofenceHealth {
  final bool isMonitoring;
  final int activeFences;
  final DateTime? lastPositionTime;
  final DateTime? lastEventTime;
  final String? lastEventType; // "enter" | "exit" | "dwell"
  final String? lastEventFenceName;

  const GeofenceHealth({
    required this.isMonitoring,
    required this.activeFences,
    this.lastPositionTime,
    this.lastEventTime,
    this.lastEventType,
    this.lastEventFenceName,
  });

  /// Human-friendly duration since last event (e.g., "5s", "2m", "3h", or "-")
  String durationSinceLastEvent() => _formatSince(lastEventTime);

  /// Human-friendly duration since last processed position
  String durationSinceLastPosition() => _formatSince(lastPositionTime);

  static String _formatSince(DateTime? t) {
    if (t == null) return '-';
    final now = DateTime.now();
    final diff = now.difference(t);
    if (diff.inSeconds < 60) return '${diff.inSeconds}s';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m';
    if (diff.inHours < 24) return '${diff.inHours}h';
    return DateFormat('MM-dd HH:mm').format(t);
  }
}
