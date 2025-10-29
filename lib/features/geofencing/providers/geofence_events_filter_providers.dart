import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Filter state for geofence events page
class GeofenceEventsFilterState {
  final Set<String> selectedEventTypes;
  final Set<String> selectedStatuses;
  final String? selectedDevice;
  final DateTimeRange? dateRange;
  final String sortBy;
  final bool sortAscending;

  const GeofenceEventsFilterState({
    required this.selectedEventTypes,
    required this.selectedStatuses,
    this.selectedDevice,
    this.dateRange,
    required this.sortBy,
    required this.sortAscending,
  });

  GeofenceEventsFilterState copyWith({
    Set<String>? selectedEventTypes,
    Set<String>? selectedStatuses,
    String? selectedDevice,
    DateTimeRange? dateRange,
    String? sortBy,
    bool? sortAscending,
    bool clearDevice = false,
    bool clearDateRange = false,
  }) {
    return GeofenceEventsFilterState(
      selectedEventTypes: selectedEventTypes ?? this.selectedEventTypes,
      selectedStatuses: selectedStatuses ?? this.selectedStatuses,
      selectedDevice: clearDevice ? null : (selectedDevice ?? this.selectedDevice),
      dateRange: clearDateRange ? null : (dateRange ?? this.dateRange),
      sortBy: sortBy ?? this.sortBy,
      sortAscending: sortAscending ?? this.sortAscending,
    );
  }

  /// Check if any filters are active
  bool hasActiveFilters() {
    return selectedEventTypes.length < 3 ||
        selectedStatuses.length < 2 ||
        selectedDevice != null ||
        dateRange != null;
  }

  /// Reset to default filters
  static GeofenceEventsFilterState defaults() {
    return const GeofenceEventsFilterState(
      selectedEventTypes: {'entry', 'exit', 'dwell'},
      selectedStatuses: {'pending', 'acknowledged'},
      selectedDevice: null,
      dateRange: null,
      sortBy: 'timestamp',
      sortAscending: false,
    );
  }
}

/// StateNotifier for managing filter state
class GeofenceEventsFilterNotifier
    extends StateNotifier<GeofenceEventsFilterState> {
  GeofenceEventsFilterNotifier()
      : super(GeofenceEventsFilterState.defaults());

  /// Toggle event type selection
  void toggleEventType(String type) {
    final types = Set<String>.from(state.selectedEventTypes);
    if (types.contains(type)) {
      types.remove(type);
      // Keep at least one type selected
      if (types.isEmpty) {
        types.addAll({'entry', 'exit', 'dwell'});
      }
    } else {
      types.add(type);
    }
    state = state.copyWith(selectedEventTypes: types);
  }

  /// Toggle status selection
  void toggleStatus(String status) {
    final statuses = Set<String>.from(state.selectedStatuses);
    if (statuses.contains(status)) {
      statuses.remove(status);
      // Keep at least one status selected
      if (statuses.isEmpty) {
        statuses.addAll({'pending', 'acknowledged', 'archived'});
      }
    } else {
      statuses.add(status);
    }
    state = state.copyWith(selectedStatuses: statuses);
  }

  /// Set selected device
  void setDevice(String? deviceId) {
    state = state.copyWith(
      selectedDevice: deviceId,
      clearDevice: deviceId == null,
    );
  }

  /// Set date range
  void setDateRange(DateTimeRange? range) {
    state = state.copyWith(
      dateRange: range,
      clearDateRange: range == null,
    );
  }

  /// Set sort criteria
  void setSortBy(String sortBy) {
    if (state.sortBy == sortBy) {
      // Toggle ascending/descending
      state = state.copyWith(sortAscending: !state.sortAscending);
    } else {
      // New sort field, default to descending (newest first)
      state = state.copyWith(sortBy: sortBy, sortAscending: false);
    }
  }

  /// Clear all filters
  void clearAll() {
    state = GeofenceEventsFilterState.defaults();
  }

  /// Remove specific event type from selection
  void removeEventType(String type) {
    final types = Set<String>.from(state.selectedEventTypes);
    types.remove(type);
    if (types.isEmpty) {
      types.addAll({'entry', 'exit', 'dwell'});
    }
    state = state.copyWith(selectedEventTypes: types);
  }

  /// Remove specific status from selection
  void removeStatus(String status) {
    final statuses = Set<String>.from(state.selectedStatuses);
    statuses.remove(status);
    if (statuses.isEmpty) {
      statuses.addAll({'pending', 'acknowledged', 'archived'});
    }
    state = state.copyWith(selectedStatuses: statuses);
  }

  /// Clear device filter
  void clearDevice() {
    state = state.copyWith(clearDevice: true);
  }

  /// Clear date range filter
  void clearDateRange() {
    state = state.copyWith(clearDateRange: true);
  }
}

/// Provider for geofence events filter state
final geofenceEventsFilterProvider =
    StateNotifierProvider.autoDispose<GeofenceEventsFilterNotifier,
        GeofenceEventsFilterState>(
  (ref) => GeofenceEventsFilterNotifier(),
);
