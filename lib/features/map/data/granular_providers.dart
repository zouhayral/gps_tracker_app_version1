import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_app_gps/features/dashboard/controller/devices_notifier.dart';
import 'package:my_app_gps/features/map/data/position_model.dart';
import 'package:my_app_gps/features/map/data/positions_last_known_provider.dart';
import 'package:my_app_gps/features/map/data/positions_live_provider.dart';

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

// Optimized with .select() to watch only a single position from the live map
final positionByDeviceProvider = Provider.family<Position?, int>((ref, id) {
  // Prefer live socket value for this id
  final liveMap = ref.watch(
    positionsLiveProvider.select((v) => v.asData?.value),
  );
  final live = liveMap == null ? null : liveMap[id];
  if (live != null) return live;
  // Fallback to last-known from REST
  final last = ref.watch(
    positionsLastKnownProvider.select((v) => v.asData?.value[id]),
  );
  return last;
});
