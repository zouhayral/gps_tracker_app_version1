import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_app_gps/features/map/data/position_model.dart';

/// Abstraction for persistence to enable test fakes.
abstract class PositionsDaoBase {
  Future<void> upsert(Position p);
  Future<Position?> latestByDevice(int deviceId);
  Future<Map<int, Position>> loadAll();
}

// Forward-declared provider, bound in platform impls
late final FutureProvider<PositionsDaoBase> positionsDaoProvider;
