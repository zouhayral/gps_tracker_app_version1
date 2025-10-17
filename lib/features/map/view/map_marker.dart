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
    super.key,
  });
  final int deviceId;
  final bool isSelected;
  final double zoomLevel;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Centralized post-frame logging
    ref.scheduleLogRebuild('Marker($deviceId)');
    final device = ref.watch(deviceByIdProvider(deviceId));
    final position = ref.watch(positionByDeviceProvider(deviceId));
    final hasPos = position != null &&
        position.latitude >= -90 &&
        position.latitude <= 90 &&
        position.longitude >= -180 &&
        position.longitude <= 180;
    if (!hasPos) return const SizedBox.shrink();
    
    final name = (device?['name']?.toString() ?? '').trim();
    
    // Determine marker status
    final statusStr = (device?['status']?.toString() ?? '').toLowerCase();
    final online = statusStr == 'online';
    
    // Extract engine state (check both device fields and position attributes)
    bool _asTrue(dynamic v) {
      if (v is bool) return v;
      if (v is num) return v != 0;
      final s = v?.toString().toLowerCase().trim();
      return s == 'true' || s == '1' || s == 'on' || s == 'yes';
    }
  final attrs = position.attributes;
    final engineOn = _asTrue(device?['ignition']) ||
        _asTrue(device?['engineOn']) ||
        _asTrue(attrs['ignition']) ||
        _asTrue(attrs['engineOn']) ||
        _asTrue(attrs['engine_on']);
    
    // Determine if moving (speed > 1 km/h)
    final speed = position.speed;
    final moving = speed > 1.0;
    
    // Use modern marker widget
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
