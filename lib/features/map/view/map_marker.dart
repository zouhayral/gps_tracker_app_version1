import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:my_app_gps/core/logging/rebuild_logger.dart';
import 'package:my_app_gps/core/map/modern_marker_flutter_map.dart';
import 'package:my_app_gps/features/map/data/granular_providers.dart';

class MapMarkerWidget extends ConsumerWidget {
  const MapMarkerWidget({
    required this.deviceId,
    required this.isSelected,
    this.zoomLevel = 12.0,
    this.fallbackName,
    this.fallbackSpeed,
    this.fallbackEngineOn,
    super.key,
  });
  final int deviceId;
  final bool isSelected;
  final double zoomLevel;
  // Fallbacks sourced from MapMarkerData.meta while providers warm up
  final String? fallbackName;
  final double? fallbackSpeed;
  final bool? fallbackEngineOn;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Centralized post-frame logging
    ref.scheduleLogRebuild('Marker($deviceId)');

    // Read device and position if available; otherwise use fallbacks so
    // markers can render immediately from MapMarkerData without waiting
    // for per-device providers to populate.
    final device = ref.watch(deviceByIdProvider(deviceId));
    final position = ref.watch(positionByDeviceProvider(deviceId));

    final name = (device?['name']?.toString() ?? fallbackName ?? '').trim();

    // Determine online status (default to true if unknown to avoid hiding)
    final statusStr = (device?['status']?.toString() ?? '').toLowerCase();
    final online = statusStr.isEmpty ? true : statusStr == 'online';

    // Engine state with safe fallbacks
    bool asTrue(dynamic v) {
      if (v is bool) return v;
      if (v is num) return v != 0;
      final s = v?.toString().toLowerCase().trim();
      return s == 'true' || s == '1' || s == 'on' || s == 'yes';
    }

    final attrs = position?.attributes ?? const <String, dynamic>{};
    final engineOn = asTrue(device?['ignition']) ||
        asTrue(device?['engineOn']) ||
        asTrue(attrs['ignition']) ||
        asTrue(attrs['engineOn']) ||
        asTrue(attrs['engine_on']) ||
        (fallbackEngineOn ?? false);

    // Speed with fallback; moving if > 1 km/h
    final speed = position?.speed ?? fallbackSpeed ?? 0.0;
    final moving = speed > 1.0;

    // Render marker unconditionally; MapMarkerData already filtered invalid coords
    return ModernMarkerFlutterMapWidget(
      name: name,
      online: online,
      engineOn: engineOn,
      moving: moving,
      isSelected: isSelected,
      zoomLevel: zoomLevel,
      speed: speed,
    );
  }
}
