import 'package:flutter/material.dart';
import 'package:my_app_gps/features/map/data/position_model.dart';
import 'package:my_app_gps/l10n/app_localizations.dart';

/// Info box displaying detailed information for a single selected device
/// Shows engine status, speed, distance, location, and last update time
class MapDeviceInfoBox extends StatelessWidget {
  const MapDeviceInfoBox({
    required this.deviceId,
    required this.devices,
    required this.position,
    required this.statusResolver,
    required this.statusColorBuilder,
    required this.onClose,
    super.key,
    this.onFocus,
  });

  final int deviceId;
  final List<Map<String, dynamic>> devices;
  final Position? position;
  final String Function(Map<String, dynamic>?, Position?) statusResolver;
  final Color Function(String) statusColorBuilder;
  final VoidCallback onClose; // currently unused but reserved for close button
  final VoidCallback? onFocus;

  @override
  Widget build(BuildContext context) {
    // Get localization instance
    final t = AppLocalizations.of(context)!;
    
    assert(
      debugCheckHasDirectionality(context),
      'MapDeviceInfoBox requires Directionality above in the tree',
    );

    String relativeAge(DateTime? dt) {
      if (dt == null) return 'n/a';
      final diff = DateTime.now().difference(dt);
      if (diff.inSeconds < 60) return '${diff.inSeconds}s ago';
      if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
      if (diff.inHours < 24) return '${diff.inHours}h ago';
      final d = diff.inDays;
      if (d < 7) return '${d}d ago';
      return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
    }

    var name = 'Device $deviceId';
    for (final d in devices) {
      if (d['id'] == deviceId) {
        name = d['name']?.toString() ?? name;
        break;
      }
    }

    var deviceMap = const <String, dynamic>{};
    for (final d in devices) {
      if (d['id'] == deviceId) {
        deviceMap = d;
        break;
      }
    }

    final status = statusResolver(deviceMap, position);
    final statusColor = statusColorBuilder(status);
    final engineAttr = position?.attributes['ignition'];
    final engine = engineAttr is bool ? (engineAttr ? 'on' : 'off') : '_';
    final speed = position?.speed.toStringAsFixed(0) ?? '--';
    
    // Debug: Log all available data sources for distance
    debugPrint('[MapInfoBox] Checking distance for device $deviceId ($name):');
    debugPrint('[MapInfoBox]   Position attributes: ${position?.attributes}');
    debugPrint('[MapInfoBox]   Device attributes: ${deviceMap['attributes']}');
    debugPrint('[MapInfoBox]   Device odometer: ${deviceMap['odometer']}');
    
    // Try multiple sources for distance (in priority order):
    // IMPORTANT: Check each attribute individually and skip if it's 0 or null
    // Priority: totalDistance > distance > odometer (position) > device attributes > device odometer
    final posAttrs = position?.attributes ?? {};
    
    // Helper to safely get numeric value > 0
    num? getPositiveNum(dynamic value) {
      if (value is num && value > 0) return value;
      return null;
    }
    
    final distanceAttr = getPositiveNum(posAttrs['totalDistance']) ??
        getPositiveNum(posAttrs['distance']) ??
        getPositiveNum(posAttrs['odometer']);

    String distance;
    if (distanceAttr != null) {
      final km = distanceAttr / 1000;
      distance = km >= 0.1 ? km.toStringAsFixed(0) : '00';
      debugPrint('[MapInfoBox]   ✅ Found in position attributes: $distanceAttr m → $distance km');
    } else {
      // Check device-level attributes (Traccar stores totalDistance at device level)
      final deviceAttributes = deviceMap['attributes'];
      final deviceAttrDistance = deviceAttributes is Map
          ? (getPositiveNum(deviceAttributes['totalDistance']) ??
              getPositiveNum(deviceAttributes['distance']) ??
              getPositiveNum(deviceAttributes['odometer']))
          : null;

      if (deviceAttrDistance != null) {
        final km = deviceAttrDistance / 1000;
        distance = km >= 0.1 ? km.toStringAsFixed(0) : '00';
        debugPrint('[MapInfoBox]   ✅ Found in device attributes: $deviceAttrDistance m → $distance km');
      } else {
        // Check if device has odometer in main data
        final deviceOdometer = getPositiveNum(deviceMap['odometer']);
        if (deviceOdometer != null) {
          final km = deviceOdometer / 1000;
          distance = km >= 0.1 ? km.toStringAsFixed(0) : '00';
          debugPrint('[MapInfoBox]   ✅ Found in device odometer: $deviceOdometer m → $distance km');
        } else {
          distance = '00';
          debugPrint('[MapInfoBox]   ❌ No distance data found, showing: $distance km');
        }
      }
    }

    // Try to get coordinates from position, then fallback to device data
    final String lastLocation;
    final pos = position;
    if (pos != null) {
      final posAddress = pos.address;
      if (posAddress != null && posAddress.isNotEmpty) {
        lastLocation = posAddress;
      } else {
        lastLocation =
            '${pos.latitude.toStringAsFixed(5)}, ${pos.longitude.toStringAsFixed(5)}';
      }
    } else {
      // Fallback to device's stored lat/lon if no position
      final devLat = deviceMap['latitude'];
      final devLon = deviceMap['longitude'];
      if (devLat != null && devLon != null) {
        lastLocation = '$devLat, $devLon (stored)';
      } else {
        lastLocation = t.noLocationData;
      }
    }

    final deviceTime = position?.deviceTime.toLocal();
    final lastUpdateDt = (deviceMap['lastUpdateDt'] is DateTime)
        ? (deviceMap['lastUpdateDt'] as DateTime).toLocal()
        : deviceTime;
    final lastAge = relativeAge(lastUpdateDt);

    return Material(
      borderRadius: BorderRadius.circular(16),
      color: Colors.white,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFE0E0E0)),
        ),
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    name,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          color: statusColor,
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    t.engineAndMovement,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                          letterSpacing: .3,
                        ),
                  ),
                  const SizedBox(height: 4),
                  MapInfoLine(
                    icon: Icons.power_settings_new,
                    label: t.engine,
                    value: engine,
                    valueColor: engine == 'on' ? statusColor : null,
                  ),
                  MapInfoLine(
                    icon: Icons.speed,
                    label: t.speed,
                    value: speed == '--' ? '-- km/h' : '$speed km/h',
                  ),
                  MapInfoLine(
                    icon: Icons.route,
                    label: t.distance,
                    value: distance == '--' ? '-- km' : '$distance km',
                  ),
                  const SizedBox(height: 10),
                  Text(
                    t.lastLocation,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                          letterSpacing: .3,
                        ),
                  ),
                  const SizedBox(height: 4),
                  MapInfoLine(
                    icon: Icons.place_outlined,
                    label: t.coordinates,
                    value: lastLocation,
                    valueColor: lastLocation == t.noLocationData
                        ? Colors.orange
                        : null,
                  ),
                  MapInfoLine(
                    icon: Icons.update,
                    label: t.updated,
                    value: lastAge,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Info box for displaying summary stats when multiple devices are selected
/// Shows count of online/offline/unknown devices and lists up to 5 devices
class MapMultiSelectionInfoBox extends StatelessWidget {
  const MapMultiSelectionInfoBox({
    required this.selectedIds,
    required this.devices,
    required this.positions,
    required this.statusResolver,
    required this.statusColorBuilder,
    required this.onClear,
    super.key,
    this.onFocus,
  });

  final Set<int> selectedIds;
  final List<Map<String, dynamic>> devices;
  final Map<int, Position> positions;
  final String Function(Map<String, dynamic>?, Position?) statusResolver;
  final Color Function(String) statusColorBuilder;
  final VoidCallback onClear;
  final VoidCallback? onFocus;

  @override
  Widget build(BuildContext context) {
    // Get localization instance
    final t = AppLocalizations.of(context)!;
    
    assert(
      debugCheckHasDirectionality(context),
      'MapMultiSelectionInfoBox requires Directionality above in the tree',
    );

    final selectedDevices = devices
        .whereType<Map<String, dynamic>>()
        .where((d) => selectedIds.contains(d['id']))
        .toList();

    var online = 0;
    var offline = 0;
    var unknown = 0;

    for (final d in selectedDevices) {
      final s = statusResolver(d, positions[d['id']]);
      switch (s) {
        case 'online':
          online++;
        case 'offline':
          offline++;
        default:
          unknown++;
      }
    }

    final total = selectedDevices.length;
    final onlinePct = total == 0 ? 0 : (online / total * 100).round();

    return Material(
      borderRadius: BorderRadius.circular(16),
      color: Colors.white,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFE0E0E0)),
        ),
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Text(
                  '$total ${t.devicesSelected}',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 12,
              runSpacing: 8,
              children: [
                MapStatusStat(
                  label: t.online,
                  count: online,
                  color: statusColorBuilder('online'),
                ),
                MapStatusStat(
                  label: t.offline,
                  count: offline,
                  color: statusColorBuilder('offline'),
                ),
                MapStatusStat(
                  label: t.unknown,
                  count: unknown,
                  color: statusColorBuilder('unknown'),
                ),
                Text(
                  '${t.online}: $onlinePct%',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (selectedDevices.isNotEmpty)
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final d in selectedDevices.take(5))
                    MapInfoLine(
                      icon: Icons.device_hub,
                      label: d['name']?.toString() ?? t.device,
                      value: statusResolver(d, positions[d['id']]),
                      valueColor: statusColorBuilder(
                        statusResolver(d, positions[d['id']]),
                      ),
                    ),
                  if (selectedDevices.length > 5)
                    Text(
                      '+ ${selectedDevices.length - 5} ${t.more}...',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

/// Single line of information with icon, label, and value
/// Used within info boxes to display device attributes
class MapInfoLine extends StatelessWidget {
  const MapInfoLine({
    required this.icon,
    required this.label,
    required this.value,
    this.valueColor,
    super.key,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    final base = Theme.of(context).textTheme.bodySmall;
    final styleLabel = base?.copyWith(
      fontWeight: FontWeight.w500,
      color: Colors.grey[800],
    );
    final styleValue = base?.copyWith(
      fontWeight: FontWeight.w700,
      color: valueColor ?? Colors.black87,
    );

    return Padding(
      padding: const EdgeInsets.only(bottom: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 28,
            alignment: Alignment.centerLeft,
            child: Icon(icon, size: 18, color: valueColor ?? Colors.black87),
          ),
          const SizedBox(width: 2),
          Text('$label: ', style: styleLabel),
          Expanded(
            child: Text(
              value,
              style: styleValue ?? base,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

/// Colored badge showing device status count (e.g., "Online: 5")
/// Used in multi-selection info box to show summary statistics
class MapStatusStat extends StatelessWidget {
  const MapStatusStat({
    required this.label,
    required this.count,
    required this.color,
    super.key,
  });

  final String label;
  final int count;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          '$label: $count',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: color,
                fontWeight: FontWeight.w600,
              ),
        ),
      );
}
