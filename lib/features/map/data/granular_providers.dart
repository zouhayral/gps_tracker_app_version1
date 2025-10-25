import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_app_gps/core/providers/vehicle_providers.dart';
import 'package:my_app_gps/features/dashboard/controller/devices_notifier.dart';
import 'package:my_app_gps/features/map/data/position_model.dart';

// Optimized with .select() to limit rebuilds per device tile/marker
final deviceByIdProvider = Provider.family<Map<String, dynamic>?, int>((
  ref,
  id,
) {
  final devices = ref.watch(
    devicesNotifierProvider.select((a) => a.asData?.value),
  );
  if (devices == null) return null;
  for (final d in devices) {
    if (d['id'] == id) return d;
  }
  return null;
});

// 🎯 PRIORITY 1: Now uses optimized devicePositionStreamProvider
// Benefits: 99% fewer broadcasts, direct repository stream access
// Provides cache-first, WebSocket-updated position for a single device
final positionByDeviceProvider = Provider.family<Position?, int>((ref, id) {
  // devicePositionStreamProvider uses repository's per-device stream API
  final asyncPosition = ref.watch(devicePositionStreamProvider(id));
  // Extract value or return null if loading/error
  return asyncPosition.valueOrNull;
});
