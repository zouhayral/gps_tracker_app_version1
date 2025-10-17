import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';
import 'package:my_app_gps/features/map/data/position_model.dart';
import 'package:my_app_gps/services/device_update_service.dart';

// ============================================================================
// Granular State Providers - Use .select() to minimize rebuilds
// ============================================================================

/// Map camera center position
final mapCenterProvider = StateProvider<LatLng>(
  (ref) => const LatLng(33.5731, -7.5898),
); // Default: Casablanca

/// Map zoom level
final mapZoomProvider = StateProvider<double>((ref) => 13.0);

/// Single selected device ID
final selectedDeviceIdProvider = StateProvider<int?>((ref) => null);

/// Multiple selection mode
final multiSelectionModeProvider = StateProvider<bool>((ref) => false);

/// Selected device IDs (for multi-selection)
final selectedDeviceIdsProvider = StateProvider<Set<int>>((ref) => {});

/// Map filter configuration
final mapFilterProvider = StateProvider<MapFilter>((ref) => const MapFilter());

/// Map filter model
class MapFilter {
  final bool showOnlineOnly;
  final bool showMovingOnly;
  final double minSpeed;
  final Set<int> hiddenDeviceIds;

  const MapFilter({
    this.showOnlineOnly = false,
    this.showMovingOnly = false,
    this.minSpeed = 0.0,
    this.hiddenDeviceIds = const {},
  });

  MapFilter copyWith({
    bool? showOnlineOnly,
    bool? showMovingOnly,
    double? minSpeed,
    Set<int>? hiddenDeviceIds,
  }) {
    return MapFilter(
      showOnlineOnly: showOnlineOnly ?? this.showOnlineOnly,
      showMovingOnly: showMovingOnly ?? this.showMovingOnly,
      minSpeed: minSpeed ?? this.minSpeed,
      hiddenDeviceIds: hiddenDeviceIds ?? this.hiddenDeviceIds,
    );
  }
}

// ============================================================================
// Computed Providers - Rebuild only when dependencies change
// ============================================================================

/// All positions from the background service
final allPositionsProvider = Provider<Map<int, Position>>((ref) {
  return ref.watch(positionsNotifierProvider).value;
});

/// Filtered positions based on current filter settings
/// Only rebuilds when filters or raw position data changes
final filteredPositionsProvider = Provider<Map<int, Position>>((ref) {
  final allPositions = ref.watch(allPositionsProvider);
  final filter = ref.watch(mapFilterProvider);

  // No filtering needed - return all positions
  if (!filter.showOnlineOnly &&
      !filter.showMovingOnly &&
      filter.hiddenDeviceIds.isEmpty) {
    return allPositions;
  }

  final now = DateTime.now();
  final filtered = <int, Position>{};

  for (final entry in allPositions.entries) {
    final position = entry.value;

    // Filter by online status (last update < 5 minutes)
    if (filter.showOnlineOnly) {
      final timeSinceUpdate = now.difference(position.deviceTime);
      if (timeSinceUpdate.inMinutes > 5) continue;
    }

    // Filter by movement
    if (filter.showMovingOnly) {
      if (position.speed < filter.minSpeed) {
        continue;
      }
    }

    // Filter by hidden devices
    if (filter.hiddenDeviceIds.contains(position.deviceId)) continue;

    filtered[entry.key] = position;
  }

  return filtered;
});

/// Count of visible markers (for UI display)
final visibleMarkerCountProvider = Provider<int>((ref) {
  return ref.watch(filteredPositionsProvider).length;
});

/// Single position by device ID - for detail views
/// Use .family to create a provider for each device ID
final positionByDeviceIdProvider =
    Provider.family<Position?, int>((ref, deviceId) {
  return ref.watch(filteredPositionsProvider)[deviceId];
});

/// Check if a specific device is selected
final isDeviceSelectedProvider = Provider.family<bool, int>((ref, deviceId) {
  final singleSelection = ref.watch(selectedDeviceIdProvider);
  final multiSelection = ref.watch(selectedDeviceIdsProvider);

  return singleSelection == deviceId || multiSelection.contains(deviceId);
});

/// Get all selected positions (for info panel)
final selectedPositionsProvider = Provider<List<Position>>((ref) {
  final positions = ref.watch(filteredPositionsProvider);
  final multiSelectionMode = ref.watch(multiSelectionModeProvider);

  if (multiSelectionMode) {
    final selectedIds = ref.watch(selectedDeviceIdsProvider);
    return selectedIds
        .map((id) => positions[id])
        .whereType<Position>()
        .toList();
  } else {
    final selectedId = ref.watch(selectedDeviceIdProvider);
    if (selectedId != null && positions.containsKey(selectedId)) {
      return [positions[selectedId]!];
    }
  }

  return [];
});

/// Online device count (devices updated in last 5 minutes)
final onlineDeviceCountProvider = Provider<int>((ref) {
  final allPositions = ref.watch(allPositionsProvider);
  final now = DateTime.now();

  return allPositions.values.where((position) {
    final timeSinceUpdate = now.difference(position.deviceTime);
    return timeSinceUpdate.inMinutes <= 5;
  }).length;
});

/// Moving device count (devices with speed > 0)
final movingDeviceCountProvider = Provider<int>((ref) {
  final allPositions = ref.watch(allPositionsProvider);

  return allPositions.values.where((position) {
    return position.speed > 0;
  }).length;
});
