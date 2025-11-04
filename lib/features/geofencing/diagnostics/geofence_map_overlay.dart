import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';
import 'package:my_app_gps/features/geofencing/providers/geofence_providers.dart';
import 'package:my_app_gps/features/map/data/position_model.dart';
import 'package:my_app_gps/features/map/providers/map_state_providers.dart';

/// Debug toggle for the mini-map inside geofence overlay
const bool _showGeofenceMiniMap = true;

/// Diagnostics-only: ID of the event to highlight on the mini-map.
/// When non-null, the corresponding event marker will pulse briefly.
final geofenceHighlightEventIdProvider = StateProvider.autoDispose<String?>((ref) => null);

class GeofenceEventMarker {
  final String id;
  final LatLng location;
  final String type; // enter | exit | dwell
  final DateTime time;
  const GeofenceEventMarker(this.id, this.location, this.type, this.time);
}

class GeofenceMiniMap extends ConsumerWidget {
  const GeofenceMiniMap({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!kDebugMode || !_showGeofenceMiniMap) return const SizedBox.shrink();

    // Current device position (selected device preferred)
    final selectedId = ref.watch(selectedDeviceIdProvider);
    Position? pos;
    if (selectedId != null) {
      pos = ref.watch(positionByDeviceIdProvider(selectedId));
    }
    pos ??= _fallbackPosition(ref);

    // Geofences (for authenticated user)
    final fencesAsync = ref.watch(geofencesProvider);
    final fences = fencesAsync.value ?? const [];

    // Health for recent event highlighting
    final health = ref.watch(geofenceHealthProvider).value;

    // Recent events (rolling <= 10)
    final eventsAsync = ref.watch(geofenceEventsProvider);
    final eventMarkers = <GeofenceEventMarker>[];
    final highlightedId = ref.watch(geofenceHighlightEventIdProvider);
    if (eventsAsync.hasValue) {
      final events = eventsAsync.value!;
      final lastTen = events.take(10);
      for (final e in lastTen) {
        eventMarkers.add(
          GeofenceEventMarker(
            e.id,
            LatLng(e.latitude, e.longitude),
            e.eventType,
            e.timestamp,
          ),
        );
      }
    }

    final center = pos != null
        ? LatLng(pos.latitude, pos.longitude)
        : (eventMarkers.isNotEmpty ? eventMarkers.first.location : const LatLng(0, 0));

    return SizedBox(
      width: 180,
      height: 180,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Stack(
          children: [
            FlutterMap(
              options: MapOptions(
                initialCenter: center,
                initialZoom: 14.5,
                interactionOptions: const InteractionOptions(flags: InteractiveFlag.none),
              ),
              children: [
                // Low-distraction OSM tiles
                TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'my_app_gps.debug.overlay',
                ),
                // Geofence circles (only circle type fences)
                if (fences.isNotEmpty)
                  CircleLayer(
                    circles: [
                      for (final g in fences)
                        if (g.type == 'circle' && g.centerLat != null && g.centerLng != null && (g.radius ?? 0) > 0)
                          CircleMarker(
                            point: LatLng(g.centerLat!, g.centerLng!),
                            // Try to render in meters when supported; fallback is pixel radius
                            useRadiusInMeter: true,
                            radius: (g.radius ?? 0).toDouble().clamp(10.0, 5000.0),
                            color: Colors.green.withOpacity(0.18),
                            borderStrokeWidth: 1.0,
                            borderColor: Colors.greenAccent.withOpacity(0.8),
                          ),
                    ],
                  ),
                // Event markers (last few), newest with pulse highlight
                if (eventMarkers.isNotEmpty)
                  MarkerLayer(
                    markers: [
                      for (final m in eventMarkers)
                        Marker(
                          width: 20,
                          height: 20,
                          point: m.location,
                          child: _EventDot(
                            type: m.type,
                            // Highlight explicitly selected event or treat very recent as pulsing
                            isRecent: highlightedId == m.id || _isRecent(m.time, base: health?.lastEventTime),
                          ),
                        ),
                    ],
                  ),
                // Current device blue dot
                if (pos != null)
                  MarkerLayer(
                    markers: [
                      Marker(
                        width: 16,
                        height: 16,
                        point: LatLng(pos.latitude, pos.longitude),
                        child: Container(
                          decoration: BoxDecoration(
                            color: Colors.blueAccent,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.white, width: 2),
                          ),
                        ),
                      ),
                    ],
                  ),
              ],
            ),
            // Optional: tap to expand full-screen debug map (simple modal)
            Positioned.fill(
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () => _openFullscreen(context, ref, center),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Position? _fallbackPosition(WidgetRef ref) {
    // Use any first available position from all positions
    final all = ref.read(allPositionsOptimizedProvider).values;
    for (final p in all) {
      if (p != null) return p;
    }
    // As a last resort, return null
    return null;
  }

  bool _isRecent(DateTime time, {DateTime? base}) {
    final now = DateTime.now();
    final d = now.difference(time);
    if (d.inSeconds <= 5) return true; // recent within 5s
    if (base != null) {
      final delta = (time.millisecondsSinceEpoch - base.millisecondsSinceEpoch).abs();
      return delta <= 2000; // within 2s of the latest event
    }
    return false;
  }

  void _openFullscreen(BuildContext context, WidgetRef ref, LatLng center) {
    showDialog<void>(
      context: context,
      builder: (_) => Dialog(
        insetPadding: const EdgeInsets.all(12),
        backgroundColor: Colors.black87,
        child: SizedBox(
          width: math.min(MediaQuery.of(context).size.width * 0.9, 520),
          height: math.min(MediaQuery.of(context).size.height * 0.8, 520),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: GeofenceMiniMap(key: UniqueKey()),
          ),
        ),
      ),
    );
  }
}

class _EventDot extends StatefulWidget {
  const _EventDot({required this.type, required this.isRecent});
  final String type;
  final bool isRecent;

  @override
  State<_EventDot> createState() => _EventDotState();
}

class _EventDotState extends State<_EventDot> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final baseColor = (widget.type.toLowerCase() == 'enter')
        ? Colors.greenAccent
        : (widget.type.toLowerCase() == 'exit')
            ? Colors.redAccent
            : Colors.orangeAccent;

    if (!widget.isRecent) {
      return Container(
        decoration: BoxDecoration(
          color: baseColor.withOpacity(0.7),
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: 1.5),
        ),
      );
    }

    return FadeTransition(
      opacity: Tween<double>(begin: 0.4, end: 1.0).animate(CurvedAnimation(parent: _c, curve: Curves.easeInOut)),
      child: Container(
        decoration: BoxDecoration(
          color: baseColor,
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: 1.5),
        ),
      ),
    );
  }
}
