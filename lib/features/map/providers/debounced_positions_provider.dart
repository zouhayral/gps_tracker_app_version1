import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_app_gps/features/map/data/position_model.dart';
import 'package:my_app_gps/features/map/data/positions_last_known_provider.dart';

/// Debounced position updates provider (500-1000ms)
/// 
/// OPTIMIZATION: Prevents rapid-fire position updates from triggering
/// excessive map rebuilds. Coalesces position bursts into single updates.
/// 
/// Benefits:
/// - Reduces MapPage build() calls from ~10-50/sec to ~1-2/sec
/// - Batches WebSocket position updates at source
/// - Maintains responsive UI while reducing rebuild churn
/// 
/// Usage:
/// ```dart
/// final positions = ref.watch(debouncedPositionsProvider);
/// ```
final debouncedPositionsProvider = StreamProvider.autoDispose<Map<int, Position>>((ref) {
  // Watch the underlying position provider
  final positionsAsync = ref.watch(positionsLastKnownProvider);
  
  // Create a StreamController for debounced output
  final controller = StreamController<Map<int, Position>>();
  
  // Debounce configuration (adjustable based on performance needs)
  const debounceDuration = Duration(milliseconds: 800);
  Timer? debounceTimer;
  Map<int, Position>? pendingUpdate;
  
  // Clean up timer on dispose
  ref.onDispose(() {
    debounceTimer?.cancel();
    controller.close();
  });
  
  // Listen to position updates and debounce
  ref.listen<AsyncValue<Map<int, Position>>>(
    positionsLastKnownProvider,
    (previous, next) {
      next.whenData((positions) {
        // Store pending update
        pendingUpdate = positions;
        
        // Cancel existing timer
        debounceTimer?.cancel();
        
        // Start new debounce timer
        debounceTimer = Timer(debounceDuration, () {
          if (pendingUpdate != null && !controller.isClosed) {
            controller.add(pendingUpdate!);
            if (kDebugMode) {
              debugPrint(
                '[DEBOUNCE] Emitting ${pendingUpdate!.length} positions '
                'after ${debounceDuration.inMilliseconds}ms debounce',
              );
            }
          }
        });
      });
    },
    fireImmediately: true,
  );
  
  // Initial value for immediate render
  positionsAsync.whenData((positions) {
    if (!controller.isClosed) {
      controller.add(positions);
    }
  });
  
  return controller.stream;
});

/// Debounced per-device position provider
/// 
/// OPTIMIZATION: Provides debounced position updates for a single device.
/// Prevents rapid marker rebuilds when individual devices update frequently.
/// 
/// Usage:
/// ```dart
/// final position = ref.watch(debouncedPositionByDeviceProvider(deviceId));
/// ```
final debouncedPositionByDeviceProvider = StreamProvider.autoDispose.family<Position?, int>((ref, deviceId) {
  // Watch debounced positions map
  final positionsStream = ref.watch(debouncedPositionsProvider.stream);
  
  // Transform stream to extract single device position
  return positionsStream.map((positions) => positions[deviceId]);
});

/// Debounced positions for marker rendering
/// 
/// OPTIMIZATION: Higher-level provider that combines debounced positions
/// with device data for marker generation. Reduces marker layer rebuilds.
/// 
/// Usage in MapPage:
/// ```dart
/// final markerData = ref.watch(debouncedMarkerPositionsProvider);
/// ```
final debouncedMarkerPositionsProvider = Provider.autoDispose<Map<int, Position>>((ref) {
  // Watch the debounced stream provider
  final positionsAsync = ref.watch(debouncedPositionsProvider);
  
  // Return current value or empty map
  return positionsAsync.when(
    data: (positions) => positions,
    loading: () => <int, Position>{},
    error: (_, __) => <int, Position>{},
  );
});
