import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_animations/flutter_map_animations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';
import 'package:my_app_gps/core/map/modern_marker_flutter_map.dart';
import 'package:my_app_gps/data/models/trip.dart';
import 'package:my_app_gps/features/trips/trip_playback_controls.dart';
import 'package:my_app_gps/l10n/app_localizations.dart';
import 'package:my_app_gps/map/map_tile_source_provider.dart';
import 'package:my_app_gps/map/tile_network_client.dart';
import 'package:my_app_gps/providers/trip_providers.dart';

class TripDetailsPage extends ConsumerStatefulWidget {
  const TripDetailsPage({required this.trip, super.key});
  final Trip trip;

  @override
  ConsumerState<TripDetailsPage> createState() => _TripDetailsPageState();
}

class _TripDetailsPageState extends ConsumerState<TripDetailsPage> with TickerProviderStateMixin {
  late final AnimatedMapController _animatedMapController;
  static const Duration _playbackDuration = Duration(seconds: 30);
  static const Duration _tick = Duration(milliseconds: 50); // 20 fps
  Timer? _timer;
  bool _didFit = false; // ensure we fit bounds only once per load
  bool _follow = true; // follow vehicle toggle
  int _lastCameraMoveTs = 0; // debounce camera animations

  @override
  void dispose() {
    _timer?.cancel();
    _animatedMapController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _animatedMapController = AnimatedMapController(vsync: this);
  }

  // Safely read current zoom; returns fallback if controller isn't attached yet
  double _safeZoom([double fallback = 12.0]) {
    try {
      return _animatedMapController.mapController.camera.zoom;
    } catch (_) {
      return fallback;
    }
  }

  void _ensureFitBounds(List<LatLng> pts) {
    if (pts.isEmpty) return;
    if (pts.length == 1) {
      try {
        _animatedMapController.mapController.move(pts.first, 16);
      } catch (_) {
        // Controller not attached yet; retry next frame
        WidgetsBinding.instance.addPostFrameCallback((_) => _ensureFitBounds(pts));
      }
      return;
    }
    final bounds = LatLngBounds.fromPoints(pts);
    try {
      _animatedMapController.mapController.fitCamera(
        CameraFit.bounds(bounds: bounds, padding: const EdgeInsets.all(32), maxZoom: 16),
      );
    } catch (_) {
      // Controller not attached yet; retry next frame
      WidgetsBinding.instance.addPostFrameCallback((_) => _ensureFitBounds(pts));
    }
  }

  void _moveCameraSmooth(LatLng target) {
    if (!_follow) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    // Debounce camera animations to avoid vibration and animation restarts
    if (now - _lastCameraMoveTs < 1200) return;
    _lastCameraMoveTs = now;
    try {
      _animatedMapController.animateTo(
        dest: target,
        zoom: _safeZoom(),
        curve: Curves.easeInOut,
        duration: const Duration(milliseconds: 1000),
      );
    } catch (_) {
      // If controller not ready yet, ignore; a later frame will retry via progress updates
    }
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

  void _onTogglePlay({required bool isPlaying}) {
    _timer?.cancel();
    if (!isPlaying) return;
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
    final t = AppLocalizations.of(context);

    // Brand colors
    const accent = Color(0xFF5C6B2F); // olive
    const bg = Color(0xFFF6F6E6); // light beige

    // No fullscreen overlay variable; we'll navigate to a separate page for fullscreen view

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: bg,
        foregroundColor: accent,
        title: Text(
          t?.tripDetails ?? 'Trip Details',
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ),
      body: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
            // Date range title
            Text(
              widget.trip.formattedDateRange,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: accent,
                  ),
            ),
            const SizedBox(height: 8),
            // Stats rows
            _TripStatRow(icon: Icons.route, label: t?.distance ?? 'Distance', value: widget.trip.formattedDistanceKm),
            _TripStatRow(icon: Icons.speed, label: t?.avgSpeed ?? 'Avg Speed', value: widget.trip.formattedAvgSpeed),
            _TripStatRow(icon: Icons.schedule, label: t?.startTime ?? 'Start Time', value: widget.trip.formattedStartTime),
            _TripStatRow(icon: Icons.flag, label: t?.endTime ?? 'End Time', value: widget.trip.formattedEndTime),
            const SizedBox(height: 20),

            // Map Card
            Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                boxShadow: const [
                  BoxShadow(color: Colors.black12, blurRadius: 8, offset: Offset(0, 4)),
                ],
              ),
              clipBehavior: Clip.antiAlias,
              child: SizedBox(
                height: 300,
                child: positionsAsync.when(
                  data: (positions) {
                    final pts = positions.map((e) => e.toLatLng).toList(growable: false);
                    // Ensure camera fits to route once when data arrives
                    if (!_didFit) {
                      WidgetsBinding.instance.addPostFrameCallback((_) => _ensureFitBounds(pts));
                      _didFit = true;
                    }

                    final current = _positionAtProgress(pts, playback.progress);
                    // Visible layers
                    const routeYellow = Color(0xFFFFC107); // bright yellow for visibility
                    final polyline = Polyline(points: pts, strokeWidth: 5, color: routeYellow);
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
                          width: 56,
                          height: 56,
                          child: ModernMarkerFlutterMapWidget(
                            name: '',
                            online: true,
                            engineOn: true,
                            moving: playback.isPlaying,
                            zoomLevel: _safeZoom(),
                          ),
                        ),
                      );
                      // Keep camera gently following current marker when playing using animated controller
                      if (playback.isPlaying) {
                        WidgetsBinding.instance.addPostFrameCallback((_) => _moveCameraSmooth(current));
                      }
                    }

                    // Build FlutterMap with base tiles + polyline + markers
                    final sep = tileSource.urlTemplate.contains('?') ? '&' : '?';
                    final url = '${tileSource.urlTemplate}${sep}_v=$ts';

                    return Stack(
                      children: [
                        RepaintBoundary(
                          child: FlutterMap(
                            mapController: _animatedMapController.mapController,
                            options: const MapOptions(
                              initialCenter: LatLng(0, 0),
                              initialZoom: 2,
                              maxZoom: 18,
                            ),
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
                            ],
                          ),
                        ),
                        // Fullscreen toggle (top-left)
                        Positioned(
                          left: 8,
                          top: 8,
                          child: Material(
                            color: Colors.white.withValues(alpha: 0.9),
                            shape: const CircleBorder(),
                            child: InkWell(
                              customBorder: const CircleBorder(),
                              onTap: () {
                                Navigator.of(context).push(
                                  MaterialPageRoute<void>(
                                    builder: (_) => TripMapFullscreenPage(trip: widget.trip),
                                  ),
                                );
                              },
                              child: const Padding(
                                padding: EdgeInsets.all(8),
                                child: Icon(Icons.fullscreen, color: Colors.black87),
                              ),
                            ),
                          ),
                        ),
                        // Attribution pill
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
                        // Follow toggle chip
                        Positioned(
                          right: 8,
                          top: 8,
                          child: Material(
                            color: accent.withValues(alpha: 0.92),
                            clipBehavior: Clip.antiAlias,
                            borderRadius: BorderRadius.circular(20),
                            child: InkWell(
                              onTap: () => setState(() => _follow = !_follow),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      _follow ? Icons.my_location : Icons.location_disabled,
                                      color: Colors.white,
                                      size: 18,
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      t?.follow ?? 'Follow',
                                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                  loading: () => const Center(child: CircularProgressIndicator()),
                  error: (Object e, StackTrace st) => Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text('Failed to load trip positions: $e'),
                  ),
                ),
              ),
            ),

            const SizedBox(height: 20),

            // Floating playback bar (capsule)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(50),
                boxShadow: const [
                  BoxShadow(color: Colors.black12, blurRadius: 8, offset: Offset(0, 3)),
                ],
              ),
              child: IconTheme(
                data: const IconThemeData(color: Colors.black87),
                child: SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                        activeTrackColor: accent,
                        inactiveTrackColor: accent.withValues(alpha: 0.3),
                        thumbColor: accent,
                      ),
                  child: TripPlaybackControls(
                    onTogglePlay: _onTogglePlay,
                    onSeek: _onSeek,
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

class TripMapFullscreenPage extends ConsumerStatefulWidget {
  const TripMapFullscreenPage({required this.trip, super.key});
  final Trip trip;

  @override
  ConsumerState<TripMapFullscreenPage> createState() => _TripMapFullscreenPageState();
}

class _TripMapFullscreenPageState extends ConsumerState<TripMapFullscreenPage> with TickerProviderStateMixin {
  late final AnimatedMapController _animatedMapController;
  bool _didFit = false;
  bool _follow = true;
  int _lastCameraMoveTs = 0;

  @override
  void initState() {
    super.initState();
    _animatedMapController = AnimatedMapController(vsync: this);
  }

  @override
  void dispose() {
    _animatedMapController.dispose();
    super.dispose();
  }

  void _ensureFitBounds(List<LatLng> pts) {
    if (pts.isEmpty) return;
    if (pts.length == 1) {
      try {
        _animatedMapController.mapController.move(pts.first, 16);
      } catch (_) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _ensureFitBounds(pts));
      }
      return;
    }
    final bounds = LatLngBounds.fromPoints(pts);
    try {
      _animatedMapController.mapController.fitCamera(
        CameraFit.bounds(bounds: bounds, padding: const EdgeInsets.all(32), maxZoom: 16),
      );
    } catch (_) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _ensureFitBounds(pts));
    }
  }

  void _moveCameraSmooth(LatLng target) {
    if (!_follow) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    if (now - _lastCameraMoveTs < 1200) return;
    _lastCameraMoveTs = now;
    try {
      _animatedMapController.animateTo(
        dest: target,
        zoom: _animatedMapController.mapController.camera.zoom,
        curve: Curves.easeInOut,
        duration: const Duration(milliseconds: 1000),
      );
    } catch (_) {
      // ignore; will retry on next frame via progress updates
    }
  }

  LatLng _lerp(LatLng a, LatLng b, double t) => LatLng(
        a.latitude + (b.latitude - a.latitude) * t,
        a.longitude + (b.longitude - a.longitude) * t,
      );

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

  @override
  Widget build(BuildContext context) {
    final playback = ref.watch(tripPlaybackProvider);
    final positionsAsync = ref.watch(tripPositionsProvider(widget.trip));
    final tileSource = ref.watch(mapTileSourceProvider);
    final ts = ref.read(mapTileSourceProvider.notifier).lastSwitchTimestamp;
    final t = AppLocalizations.of(context);
    const accent = Color(0xFF5C6B2F);

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: positionsAsync.when(
          data: (positions) {
            final pts = positions.map((e) => e.toLatLng).toList(growable: false);
            if (!_didFit) {
              WidgetsBinding.instance.addPostFrameCallback((_) => _ensureFitBounds(pts));
              _didFit = true;
            }
            final current = _positionAtProgress(pts, playback.progress);

            const routeYellow = Color(0xFFFFC107);
            final polyline = Polyline(points: pts, strokeWidth: 5, color: routeYellow);
            final markers = <Marker>[];
            if (pts.isNotEmpty) {
              markers.add(
                Marker(point: pts.first, width: 28, height: 28, child: const Icon(Icons.flag, color: Colors.green, size: 24)),
              );
              markers.add(
                Marker(point: pts.last, width: 28, height: 28, child: const Icon(Icons.flag, color: Colors.red, size: 24)),
              );
            }
            if (current != null) {
              double zoom;
              try {
                zoom = _animatedMapController.mapController.camera.zoom;
              } catch (_) {
                zoom = 12.0;
              }
              markers.add(
                Marker(
                  point: current,
                  width: 56,
                  height: 56,
                  child: ModernMarkerFlutterMapWidget(
                    name: '',
                    online: true,
                    engineOn: true,
                    moving: playback.isPlaying,
                    zoomLevel: zoom,
                  ),
                ),
              );
              if (playback.isPlaying) {
                WidgetsBinding.instance.addPostFrameCallback((_) => _moveCameraSmooth(current));
              }
            }

            final sep = tileSource.urlTemplate.contains('?') ? '&' : '?';
            final url = '${tileSource.urlTemplate}${sep}_v=$ts';

            return Stack(
              children: [
                RepaintBoundary(
                  child: FlutterMap(
                    mapController: _animatedMapController.mapController,
                    options: const MapOptions(initialCenter: LatLng(0, 0), initialZoom: 2, maxZoom: 18),
                    children: [
                      TileLayer(
                        key: ValueKey('trip_tiles_full_${tileSource.id}_${url.hashCode}_$ts'),
                        urlTemplate: url,
                        userAgentPackageName: TileNetworkClient.userAgent,
                        maxZoom: tileSource.maxZoom.toDouble(),
                        minZoom: tileSource.minZoom.toDouble(),
                      ),
                      PolylineLayer(polylines: [polyline]),
                      if (markers.isNotEmpty) MarkerLayer(markers: markers),
                    ],
                  ),
                ),
                // Exit button
                Positioned(
                  left: 12,
                  top: 12,
                  child: Material(
                    color: Colors.white.withValues(alpha: 0.95),
                    shape: const CircleBorder(),
                    child: InkWell(
                      customBorder: const CircleBorder(),
                      onTap: () => Navigator.of(context).pop(),
                      child: const Padding(
                        padding: EdgeInsets.all(10),
                        child: Icon(Icons.fullscreen_exit, color: Colors.black87),
                      ),
                    ),
                  ),
                ),
                // Follow chip
                Positioned(
                  right: 12,
                  top: 12,
                  child: Material(
                    color: accent.withValues(alpha: 0.92),
                    clipBehavior: Clip.antiAlias,
                    borderRadius: BorderRadius.circular(20),
                    child: InkWell(
                      onTap: () => setState(() => _follow = !_follow),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              _follow ? Icons.my_location : Icons.location_disabled,
                              color: Colors.white,
                              size: 18,
                            ),
                            const SizedBox(width: 6),
                            Text(t?.follow ?? 'Follow', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
          loading: () => const Center(child: CircularProgressIndicator(color: Colors.white)),
          error: (Object e, StackTrace st) => const Center(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Text('Failed to load trip positions', style: TextStyle(color: Colors.white)),
            ),
          ),
        ),
      ),
    );
  }
}

class _TripStatRow extends StatelessWidget {
  const _TripStatRow({required this.icon, required this.label, required this.value});
  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    const accent = Color(0xFF5C6B2F);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          const SizedBox(width: 2),
          Icon(icon, color: accent),
          const SizedBox(width: 10),
          Text('$label: ', style: const TextStyle(fontWeight: FontWeight.w600)),
          Text(value, style: const TextStyle(color: Colors.black54)),
        ],
      ),
    );
  }
}
