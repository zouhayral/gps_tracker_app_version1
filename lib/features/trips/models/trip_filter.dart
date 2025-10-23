import 'package:flutter/foundation.dart';

/// Filter configuration for trip search
@immutable
class TripFilter {
  const TripFilter({
    required this.deviceIds,
    required this.from,
    required this.to,
  });

  /// List of device IDs to filter by. Empty list means "All Devices"
  final List<int> deviceIds;
  
  /// Start date/time for the trip range
  final DateTime from;
  
  /// End date/time for the trip range
  final DateTime to;

  /// Returns true if specific devices are selected (not all)
  bool get hasDeviceFilter => deviceIds.isNotEmpty;
  
  /// Returns true if filtering by all devices
  bool get isAllDevices => deviceIds.isEmpty;

  /// Creates a copy with updated values
  TripFilter copyWith({
    List<int>? deviceIds,
    DateTime? from,
    DateTime? to,
  }) {
    return TripFilter(
      deviceIds: deviceIds ?? this.deviceIds,
      from: from ?? this.from,
      to: to ?? this.to,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is TripFilter &&
        _listEquals(other.deviceIds, deviceIds) &&
        other.from == from &&
        other.to == to;
  }

  @override
  int get hashCode => Object.hash(
        Object.hashAll(deviceIds),
        from,
        to,
      );

  bool _listEquals(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
