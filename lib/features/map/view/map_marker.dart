import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import 'package:my_app_gps/core/logging/rebuild_logger.dart';
import 'package:my_app_gps/features/map/data/granular_providers.dart';
import 'package:my_app_gps/features/map/view/marker_assets.dart';

class MapMarkerWidget extends ConsumerWidget {
  const MapMarkerWidget({
    required this.deviceId,
    required this.isSelected,
    super.key,
  });
  final int deviceId;
  final bool isSelected;

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
    // Determine marker status: expect device['status'] values like 'online', 'offline', 'disconnected'.
    final statusStr = (device?['status']?.toString() ?? '').toLowerCase();
    MarkerStatus status;
    switch (statusStr) {
      case 'online':
        status = MarkerStatus.online;
      case 'offline':
        status = MarkerStatus.offline;
      case 'disconnected':
      case 'unknown':
        status = MarkerStatus.disconnected;
      default:
        status = MarkerStatus.online; // safe default
    }
    return _MarkerIcon(
      name: name,
      selected: isSelected,
      status: status,
      heading: position.course,
      speed: position.speed,
      latLng: LatLng(position.latitude, position.longitude),
    );
  }
}

class _MarkerIcon extends StatelessWidget {
  const _MarkerIcon({
    required this.name,
    required this.selected,
    required this.latLng,
    required this.status,
    this.heading,
    this.speed,
  });
  final String name;
  final bool selected;
  final MarkerStatus status;
  final double? heading;
  final double? speed;
  final LatLng latLng;

  @override
  Widget build(BuildContext context) {
    // Multi-property animation for smooth visual feedback
    return AnimatedScale(
      duration: const Duration(milliseconds: 150), // Fast response <100ms
      curve: Curves.easeOutCubic,
      scale: selected ? 1.4 : 1.0, // More prominent scaling
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        decoration: selected
            ? BoxDecoration(
                shape: BoxShape.circle,
                boxShadow: [
                  // Glowing effect for selected marker
                  BoxShadow(
                    color: const Color(0xFFA6CD27).withValues(alpha: 0.8),
                    blurRadius: 12,
                    spreadRadius: 2,
                  ),
                ],
              )
            : null,
        child: Stack(
          alignment: Alignment.center,
          children: [
            // Outer ring for selected state
            if (selected)
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: const Color(0xFFA6CD27),
                    width: 2.5,
                  ),
                ),
              ),
            // SVG first with PNG fallback handled internally, based on computed status
            ColorFiltered(
              colorFilter: selected
                  ? const ColorFilter.mode(
                      Color(0xFFA6CD27),
                      BlendMode.modulate,
                    )
                  : const ColorFilter.mode(
                      Colors.transparent,
                      BlendMode.multiply,
                    ),
              child: MarkerAssets.buildMarkerByStatus(status: status),
            ),
            if (heading != null)
              Transform.rotate(
                angle: heading! * 3.1415926535 / 180,
                child: Icon(
                  Icons.navigation,
                  size: 14,
                  color: selected
                      ? Colors.white
                      : Colors.black.withValues(alpha: 0.6),
                ),
              ),
            // Optional: small status/badge using vector Icons (fallback without flutter_svg)
            Positioned(
              bottom: 0,
              right: 0,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                decoration: BoxDecoration(
                  color: selected
                      ? const Color(0xFFA6CD27)
                      : Colors.black.withValues(alpha: 0.6),
                  shape: BoxShape.circle,
                ),
                padding: const EdgeInsets.all(2),
                child: Icon(
                  (speed ?? 0) > 1.0 ? Icons.bolt : Icons.battery_full,
                  size: 10,
                  color: Colors.white,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
