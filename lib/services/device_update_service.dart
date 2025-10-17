import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_app_gps/features/map/data/position_model.dart';

/// Background service that processes device updates off the main widget tree
/// Prevents UI rebuilds during WebSocket updates
class DeviceUpdateService {
  final ValueNotifier<Map<int, Position>> _positionsNotifier;
  final StreamController<DeviceUpdate> _updateController;
  Timer? _batchTimer;
  final List<DeviceUpdate> _pendingUpdates = [];

  DeviceUpdateService(this._positionsNotifier)
      : _updateController = StreamController<DeviceUpdate>.broadcast() {
    _listenToUpdates();
  }

  Stream<DeviceUpdate> get updates => _updateController.stream;

  void _listenToUpdates() {
    _updateController.stream.listen((update) {
      if (update.type == UpdateType.batch) {
        _processBatchUpdate(update);
      } else {
        _processUpdate(update);
      }
    });
  }

  void _processUpdate(DeviceUpdate update) {
    final currentPositions = Map<int, Position>.from(_positionsNotifier.value);

    switch (update.type) {
      case UpdateType.position:
        if (update.position != null) {
          currentPositions[update.deviceId] = update.position!;
        }
      case UpdateType.remove:
        currentPositions.remove(update.deviceId);
      case UpdateType.batch:
        // Handled in _processBatchUpdate
        break;
    }

    // Single notifier update - triggers marker layer rebuild only
    _positionsNotifier.value = currentPositions;
  }

  void _processBatchUpdate(DeviceUpdate update) {
    if (update.positions == null || update.positions!.isEmpty) return;

    final currentPositions = Map<int, Position>.from(_positionsNotifier.value);

    for (final position in update.positions!) {
      currentPositions[position.deviceId] = position;
    }

    _positionsNotifier.value = currentPositions;
  }

  /// Add a single position update
  void addUpdate(DeviceUpdate update) {
    _updateController.add(update);
  }

  /// Add multiple position updates as a batch (more efficient)
  void addBatchUpdates(List<Position> positions) {
    if (positions.isEmpty) return;
    _updateController.add(DeviceUpdate.batch(positions));
  }

  /// Queue updates and process them in batches (reduces overhead)
  void queueUpdate(DeviceUpdate update) {
    _pendingUpdates.add(update);

    _batchTimer?.cancel();
    _batchTimer = Timer(const Duration(milliseconds: 100), () {
      if (_pendingUpdates.isEmpty) return;

      final positions = _pendingUpdates
          .where((u) => u.position != null)
          .map((u) => u.position!)
          .toList();

      _pendingUpdates.clear();

      if (positions.isNotEmpty) {
        addBatchUpdates(positions);
      }
    });
  }

  void dispose() {
    _batchTimer?.cancel();
    _updateController.close();
  }
}

class DeviceUpdate {
  final int deviceId;
  final UpdateType type;
  final Position? position;
  final List<Position>? positions;

  const DeviceUpdate({
    required this.deviceId,
    required this.type,
    this.position,
    this.positions,
  });

  factory DeviceUpdate.position(Position position) {
    return DeviceUpdate(
      deviceId: position.deviceId,
      type: UpdateType.position,
      position: position,
    );
  }

  factory DeviceUpdate.remove(int deviceId) {
    return DeviceUpdate(
      deviceId: deviceId,
      type: UpdateType.remove,
    );
  }

  factory DeviceUpdate.batch(List<Position> positions) {
    return DeviceUpdate(
      deviceId: -1,
      type: UpdateType.batch,
      positions: positions,
    );
  }
}

enum UpdateType { position, remove, batch }

// ============================================================================
// Providers
// ============================================================================

/// ValueNotifier holding all device positions - used for efficient updates
final positionsNotifierProvider =
    Provider<ValueNotifier<Map<int, Position>>>((ref) {
  final notifier = ValueNotifier<Map<int, Position>>({});
  ref.onDispose(notifier.dispose);
  return notifier;
});

/// Background service that processes device updates
final deviceUpdateServiceProvider = Provider<DeviceUpdateService>((ref) {
  final positionsNotifier = ref.watch(positionsNotifierProvider);
  final service = DeviceUpdateService(positionsNotifier);

  ref.onDispose(service.dispose);

  return service;
});
