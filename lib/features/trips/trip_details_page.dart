import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';
import 'package:my_app_gps/data/models/trip.dart';
import 'package:my_app_gps/features/trips/trip_playback_controls.dart';
import 'package:my_app_gps/map/map_tile_source_provider.dart';
import 'package:my_app_gps/map/tile_network_client.dart';
import 'package:my_app_gps/providers/trip_providers.dart';

class TripDetailsPage extends ConsumerStatefulWidget {
  const TripDetailsPage({required this.trip, super.key});
  final Trip trip;

  @override
  ConsumerState<TripDetailsPage> createState() => _TripDetailsPageState();
}

class _TripDetailsPageState extends ConsumerState<TripDetailsPage> {
  final MapController _mapController = MapController();
  static const Duration _playbackDuration = Duration(seconds: 30);
  static const Duration _tick = Duration(milliseconds: 50); // 20 fps
  Timer? _timer;

  @override
  void dispose() {
    _timer?.cancel();
    _mapController.dispose();
    super.dispose();
  }

  void _ensureFitBounds(List<LatLng> pts) {
    if (pts.isEmpty) return;
    if (pts.length == 1) {
      _mapController.move(pts.first, 16);
      return;
    }
    final bounds = LatLngBounds.fromPoints(pts);
    _mapController.fitCamera(
      CameraFit.bounds(bounds: bounds, padding: const EdgeInsets.all(32), maxZoom: 16),
    );
  }

  // Linear interpolation between two LatLngs
  LatLng _lerp(LatLng a, LatLng b, double t) {
    return LatLng(
      a.latitude + (b.latitude - a.latitude) * t,
      a.longitude + (b.longitude - a.longitude) * t,
    );
  }

  LatLng? _positionAtProgress(List<LatLng> pts, double progress) {
    if (pts.isEmpty) return null;
    if (pts.length == 1) return pts.first;
    final p = progress.clamp(0.0, 1.0);
    final lastIdx = pts.length - 1;
    final f = p * lastIdx;
    final i = f.floor();
    final i2 = (i + 1).clamp(0, lastIdx);
    final t = (f - i).clamp(0.0, 1.0);
    return _lerp(pts[i], pts[i2], t);
  }

  void _onTogglePlay(bool play) {
    _timer?.cancel();
    if (!play) return;
    final notifier = ref.read(tripPlaybackProvider.notifier);
    _timer = Timer.periodic(_tick, (_) {
      final st = ref.read(tripPlaybackProvider);
      final next = (st.progress + _tick.inMilliseconds / _playbackDuration.inMilliseconds).clamp(0.0, 1.0);
      notifier.seek(next);
      if (next >= 1.0) {
        notifier.pause();
        _timer?.cancel();
      }
    });
  }

  void _onSeek(double progress) {
    // Map animation handled in build via current progress
  }

  @override
  Widget build(BuildContext context) {
    final positionsAsync = ref.watch(tripPositionsProvider(widget.trip));
    final playback = ref.watch(tripPlaybackProvider);
    final tileSource = ref.watch(mapTileSourceProvider);
    final ts = ref.read(mapTileSourceProvider.notifier).lastSwitchTimestamp;

    return Scaffold(
      appBar: AppBar(title: const Text('Trip details')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.trip.formattedDateRange,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text('Distance: ${widget.trip.formattedDistanceKm}'),
            Text('Avg speed: ${widget.trip.formattedAvgSpeed}'),
            Text('Max speed: ${widget.trip.formattedMaxSpeed}'),
            const SizedBox(height: 16),
            Expanded(
              child: Card(
                clipBehavior: Clip.antiAlias,
                child: positionsAsync.when(
                  data: (positions) {
                    final pts = positions.map((e) => e.toLatLng).toList(growable: false);
                    // Ensure camera fits to route once when data arrives
                    WidgetsBinding.instance.addPostFrameCallback((_) => _ensureFitBounds(pts));

                    final current = _positionAtProgress(pts, playback.progress);
                    // Visible layers
                    final polyline = Polyline(points: pts, strokeWidth: 4, color: Colors.blueAccent);
                    final markers = <Marker>[];
                    if (pts.isNotEmpty) {
                      markers.add(
                        Marker(
                          point: pts.first,
                          width: 28,
                          height: 28,
                          child: const Icon(Icons.flag, color: Colors.green, size: 24),
                        ),
                      );
                      markers.add(
                        Marker(
                          point: pts.last,
                          width: 28,
                          height: 28,
                          child: const Icon(Icons.flag, color: Colors.red, size: 24),
                        ),
                      );
                    }
                    if (current != null) {
                      markers.add(
                        Marker(
                          point: current,
                          child: const Icon(Icons.location_history, color: Colors.orange, size: 26),
                        ),
                      );
                      // Keep camera gently following current marker when playing
                      if (playback.isPlaying) {
                        _mapController.move(current, _mapController.camera.zoom);
                      }
                    }

                    // Build FlutterMap with base tiles + polyline + markers
                    final sep = tileSource.urlTemplate.contains('?') ? '&' : '?';
                    final url = '${tileSource.urlTemplate}${sep}_v=$ts';

                    return FlutterMap(
                      mapController: _mapController,
                      options: const MapOptions(maxZoom: 18),
                      children: [
                        TileLayer(
                          key: ValueKey('trip_tiles_${tileSource.id}_${url.hashCode}_$ts'),
                          urlTemplate: url,
                          userAgentPackageName: TileNetworkClient.userAgent,
                          maxZoom: tileSource.maxZoom.toDouble(),
                          minZoom: tileSource.minZoom.toDouble(),
                        ),
                        PolylineLayer(polylines: [polyline]),
                        if (markers.isNotEmpty) MarkerLayer(markers: markers),
                        Positioned(
                          right: 8,
                          bottom: 8,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.5),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              tileSource.attribution,
                              style: const TextStyle(color: Colors.white, fontSize: 11),
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                  loading: () => const Center(child: CircularProgressIndicator()),
                  error: (e, st) => Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text('Failed to load trip positions: $e'),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            TripPlaybackControls(
              onTogglePlay: _onTogglePlay,
              onSeek: _onSeek,
            ),
          ],
        ),
      ),
    );
  }
}
