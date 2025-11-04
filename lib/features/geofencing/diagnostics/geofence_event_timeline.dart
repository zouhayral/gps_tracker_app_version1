import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';
import 'package:my_app_gps/features/geofencing/diagnostics/geofence_map_overlay.dart' show geofenceHighlightEventIdProvider;
import 'package:my_app_gps/features/geofencing/providers/geofence_providers.dart';

/// Optional lightweight view model for display
class GeofenceEventView {
  final String id;
  final String fenceName;
  final String type; // enter | exit | dwell
  final DateTime time;
  final LatLng pos;
  const GeofenceEventView({
    required this.id,
    required this.fenceName,
    required this.type,
    required this.time,
    required this.pos,
  });
}

class GeofenceEventTimeline extends ConsumerStatefulWidget {
  const GeofenceEventTimeline({super.key});

  @override
  ConsumerState<GeofenceEventTimeline> createState() => _GeofenceEventTimelineState();
}

class _GeofenceEventTimelineState extends ConsumerState<GeofenceEventTimeline> {
  static const int _maxItems = 20;
  final ScrollController _controller = ScrollController();
  String? _lastTopId;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!kDebugMode) return const SizedBox.shrink();

    final eventsAsync = ref.watch(geofenceEventsProvider);

    return eventsAsync.when(
      data: (events) {
        // Newest-first ordering is provided by the repository
        final capped = events.take(_maxItems).toList(growable: false);
        final list = capped
            .map<GeofenceEventView>((e) => GeofenceEventView(
                  id: e.id,
                  fenceName: e.geofenceName,
                  type: e.eventType,
                  time: e.timestamp.toLocal(),
                  pos: LatLng(e.latitude, e.longitude),
                ))
            .toList(growable: false);

        // Auto-scroll to top when a new top event appears
        if (list.isNotEmpty && list.first.id != _lastTopId) {
          _lastTopId = list.first.id;
          if (_controller.hasClients) {
            // Use jumpTo for immediate sync; tiny list so no perf issue
            _controller.jumpTo(0);
          }
        }

        return Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.6),
            borderRadius: BorderRadius.circular(8),
          ),
          constraints: const BoxConstraints(maxHeight: 180),
          child: list.isEmpty
              ? const Center(
                  child: Text(
                    'No geofence events yet',
                    style: TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                )
              : ListView.builder(
                  controller: _controller,
                  itemCount: list.length,
                  itemBuilder: (context, i) {
                    final e = list[i];
                    final type = e.type.toLowerCase();
                    final Color color = type == 'enter'
                        ? Colors.greenAccent
                        : type == 'exit'
                            ? Colors.redAccent
                            : Colors.orangeAccent;

                    return InkWell(
                      onTap: i == 0
                          ? () {
                              // Highlight the latest event's marker on the mini-map (pulse)
                              ref.read(geofenceHighlightEventIdProvider.notifier).state = e.id;
                              // Auto-clear highlight after a moment
                              Future<void>.delayed(const Duration(milliseconds: 1500), () {
                                final notifier = ref.read(geofenceHighlightEventIdProvider.notifier);
                                if (notifier.mounted && notifier.state == e.id) {
                                  notifier.state = null;
                                }
                              });
                            }
                          : null,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4.0),
                        child: Row(
                          children: [
                            Icon(Icons.circle, size: 10, color: color),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                '${e.type.toUpperCase()} • ${e.fenceName}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(color: color, fontSize: 12),
                              ),
                            ),
                            Text(
                              // Use model's relative time semantics from GeofenceEvent if desired; here compute simple humanized
                              _formatAgo(e.time),
                              style: const TextStyle(color: Colors.white70, fontSize: 11),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        );
      },
      loading: () => Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.6),
          borderRadius: BorderRadius.circular(8),
        ),
        constraints: const BoxConstraints(maxHeight: 180),
        child: const Center(
          child: SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 1.6, valueColor: AlwaysStoppedAnimation<Color>(Colors.white70)),
          ),
        ),
      ),
      error: (e, _) => Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.6),
          borderRadius: BorderRadius.circular(8),
        ),
        constraints: const BoxConstraints(maxHeight: 180),
        child: const Text('Timeline error', style: TextStyle(color: Colors.redAccent, fontSize: 12)),
      ),
    );
  }

  String _formatAgo(DateTime time) {
    final now = DateTime.now();
    final diff = now.difference(time);
    if (diff.inSeconds < 60) return '${diff.inSeconds}s ago';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }
}
