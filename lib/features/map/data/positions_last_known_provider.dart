import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_app_gps/core/database/dao/positions_dao.dart';
import 'package:my_app_gps/features/dashboard/controller/devices_notifier.dart';
import 'package:my_app_gps/features/map/data/position_model.dart';
import 'package:my_app_gps/services/positions_service.dart';

/// Last-known positions via REST (seeded by device.positionId).
/// - Rebuilds when devices list changes.
/// - Kept alive for 10 minutes after last listener to avoid refetch churn.
final positionsLastKnownProvider = AutoDisposeAsyncNotifierProvider<
    PositionsLastKnownNotifier, Map<int, Position>>(PositionsLastKnownNotifier.new);

class PositionsLastKnownNotifier
    extends AutoDisposeAsyncNotifier<Map<int, Position>> {
  Timer? _cacheTimer;

  @override
  Future<Map<int, Position>> build() async {
    if (kDebugMode) {
      // ignore: avoid_print
      print('[positionsLastKnown] init');
    }

    final keep = ref.keepAlive();
    ref.onCancel(() {
      _cacheTimer?.cancel();
      _cacheTimer = Timer(const Duration(minutes: 10), keep.close);
      if (kDebugMode) {
        // ignore: avoid_print
        print('[positionsLastKnown] onCancel → start 10m cache');
      }
    });
    ref.onResume(() {
      _cacheTimer?.cancel();
      _cacheTimer = null;
    });
    ref.onDispose(() {
      _cacheTimer?.cancel();
      _cacheTimer = null;
    });

    final devices = ref.watch(
      devicesNotifierProvider
          .select((a) => a.asData?.value ?? const <Map<String, dynamic>>[]),
    );
    if (kDebugMode) {
      // ignore: avoid_print
      print('[positionsLastKnown] Devices count: ${devices.length}');
    }
    if (devices.isEmpty) {
      if (kDebugMode) {
        // ignore: avoid_print
        print('[positionsLastKnown] No devices - returning empty map');
      }
      return <int, Position>{};
    }

    // Prefill from DAO (if available) to render immediately while REST fetch occurs
    var prefill = const <int, Position>{};
    try {
      final daoAsync = await ref.watch(positionsDaoProvider.future);
      prefill = await daoAsync.loadAll();
      if (prefill.isNotEmpty) {
        if (kDebugMode) {
          // ignore: avoid_print
          print('[positionsLastKnown] DAO prefill: ${prefill.length} positions');
        }
        // Emit prefill immediately
        state = AsyncData(Map<int, Position>.unmodifiable(prefill));
      }
    } catch (e) {
      if (kDebugMode) {
        // ignore: avoid_print
        print('[positionsLastKnown] DAO prefill error: $e');
      }
    }

    final service = ref.read(positionsServiceProvider);
    final map = await service.latestForDevices(devices);

    if (kDebugMode) {
      // ignore: avoid_print
      print('[positionsLastKnown] ✅ REST fetch complete: ${map.length} positions');
    }

    // After successful REST fetch, upsert into DAO and emit
    try {
      final dao = await ref.read(positionsDaoProvider.future);
      for (final p in map.values) {
        await dao.upsert(p);
      }
    } catch (_) {/* ignore DAO errors */}
    return map.isEmpty && prefill.isNotEmpty ? prefill : map;
  }
}
