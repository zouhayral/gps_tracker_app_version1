import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_app_gps/features/geofencing/diagnostics/geofence_diagnostics.dart';
import 'package:my_app_gps/features/geofencing/providers/geofence_providers.dart';
import 'package:my_app_gps/features/geofencing/diagnostics/geofence_map_overlay.dart';
import 'package:my_app_gps/features/geofencing/diagnostics/geofence_event_timeline.dart';
import 'package:my_app_gps/features/geofencing/diagnostics/geofence_profiler_panel.dart';

/// Global debug flag to toggle overlay visibility
const bool _showGeofenceOverlay = true;
/// Debug toggle for timeline panel
const bool _showGeofenceTimeline = true;
/// Debug toggle for profiler panel
const bool _showGeofenceProfiler = true;

/// A floating overlay that shows live geofence monitoring health.
class GeofenceHealthOverlay extends ConsumerStatefulWidget {
  const GeofenceHealthOverlay({super.key});
  static OverlayEntry? _entry;

  /// Attach the overlay to the nearest Overlay in [context].
  /// Safe to call multiple times; it will attach only once.
  static void attach(BuildContext context) {
    if (!kDebugMode) return;
    if (!_showGeofenceOverlay) return;
    if (_entry != null) return;
    final overlay = Overlay.of(context);
    _entry = OverlayEntry(builder: (ctx) => const GeofenceHealthOverlay());
    overlay.insert(_entry!);
  }

  /// Remove the overlay if attached.
  static void detach() {
    _entry?.remove();
    _entry = null;
  }

  @override
  ConsumerState<GeofenceHealthOverlay> createState() => _GeofenceHealthOverlayState();
}

class _GeofenceHealthOverlayState extends ConsumerState<GeofenceHealthOverlay> {
  bool _minimized = false;

  @override
  Widget build(BuildContext context) {
    final healthAsync = ref.watch(geofenceHealthProvider);

  Widget content(GeofenceHealth h) {
      final monitoringText = h.isMonitoring ? '✅' : '❌';
      final monitoringColor = h.isMonitoring ? Colors.greenAccent : Colors.redAccent;

      return Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.6),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('🛰', style: TextStyle(color: Colors.white70, fontSize: 13)),
                const SizedBox(width: 6),
                const Text('Geofence Health', style: TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w600)),
                const SizedBox(width: 8),
                InkWell(
                  onTap: () => setState(() => _minimized = true),
                  child: const Icon(Icons.close, size: 14, color: Colors.white70),
                ),
              ],
            ),
            const SizedBox(height: 6),
            // Mini map above textual health card
            const GeofenceMiniMap(),
            const SizedBox(height: 8),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Monitoring: ', style: TextStyle(color: Colors.white70, fontSize: 12)),
                Text(monitoringText, style: TextStyle(color: monitoringColor, fontSize: 12)),
              ],
            ),
            Text('Active Fences: ${h.activeFences}', style: const TextStyle(color: Colors.cyanAccent, fontSize: 12)),
            Text('Last Pos: ${h.durationSinceLastPosition()}', style: const TextStyle(color: Colors.greenAccent, fontSize: 12)),
            Text(
              'Last Event: ${h.lastEventType ?? '-'} ${h.lastEventFenceName ?? ''}',
              style: const TextStyle(color: Colors.orangeAccent, fontSize: 12),
              overflow: TextOverflow.ellipsis,
            ),
            if (kDebugMode && _showGeofenceTimeline) ...[
              const SizedBox(height: 8),
              const GeofenceEventTimeline(),
            ],
            if (kDebugMode && _showGeofenceProfiler) ...[
              const SizedBox(height: 8),
              const GeofenceProfilerPanel(),
            ],
          ],
        ),
      );
    }
    Widget minimizedButton() {
      return FloatingActionButton.small(
        heroTag: 'geofence-health-overlay-toggle',
        onPressed: () => setState(() => _minimized = false),
        backgroundColor: Colors.black.withOpacity(0.6),
        shape: const CircleBorder(),
        child: const Text('🛰', style: TextStyle(fontSize: 16)),
      );
    }

    return IgnorePointer(
      ignoring: false,
      child: SafeArea(
        child: Stack(
          children: [
            Positioned(
              left: 12,
              bottom: 12,
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 150),
                child: _minimized
                    ? minimizedButton()
                    : SizedBox(
                        width: 260,
                        child: healthAsync.when(
                          data: (h) => content(h),
                          loading: () => Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: Colors.black.withOpacity(0.6),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const SizedBox(
                              width: 90,
                              height: 36,
                              child: Center(
                                child: CircularProgressIndicator(
                                  strokeWidth: 1.6,
                                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white70),
                                ),
                              ),
                            ),
                          ),
                          error: (e, _) => Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: Colors.black.withOpacity(0.6),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Text('Geofence Health: error', style: TextStyle(color: Colors.redAccent)),
                          ),
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
