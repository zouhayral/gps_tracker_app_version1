import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../core/map_adapter.dart';

class FlutterMapAdapter extends StatefulWidget implements MapAdapter {
  const FlutterMapAdapter({
    super.key,
    required this.markers,
    required this.cameraFit,
    this.onMarkerTap,
    this.onMapTap,
  });

  final List<MapMarkerData> markers;
  final MapCameraFit cameraFit;
  final void Function(String markerId)? onMarkerTap;
  final VoidCallback? onMapTap;

  @override
  State<FlutterMapAdapter> createState() => FlutterMapAdapterState();
}

class FlutterMapAdapterState extends State<FlutterMapAdapter> {
  final mapController = MapController();

  @override
  void didUpdateWidget(covariant FlutterMapAdapter oldWidget) {
    super.didUpdateWidget(oldWidget);
    _maybeFit();
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeFit());
  }

  void _maybeFit() {
    final fit = widget.cameraFit;
    if (fit.boundsPoints != null && fit.boundsPoints!.isNotEmpty) {
      final bounds = LatLngBounds.fromPoints(fit.boundsPoints!);
      final center = bounds.center;
      final zoom = fitZoomForBounds(bounds, paddingFactor: 1.15);
      _animatedMove(center, zoom);
    } else if (fit.center != null) {
      _animatedMove(fit.center!, mapController.camera.zoom);
    }
  }

  double fitZoomForBounds(LatLngBounds b, {double paddingFactor = 1.0}) {
    // Very naive fit; refine later with size info & padding.
    final latDiff = (b.north - b.south).abs().clamp(0.0001, 180.0);
    final lngDiff = (b.east - b.west).abs().clamp(0.0001, 360.0);
    final maxDiff = latDiff > lngDiff ? latDiff : lngDiff;
    double base;
    if (maxDiff < 0.01) base = 16;
    else if (maxDiff < 0.05) base = 14;
    else if (maxDiff < 0.1) base = 13;
    else if (maxDiff < 0.5) base = 11;
    else if (maxDiff < 1) base = 10;
    else if (maxDiff < 5) base = 8;
    else base = 4;
    // Apply padding factor (zoom out slightly >1.0)
    return base - (paddingFactor > 1.02 ? 1 : 0);
  }

  // Public method (access via GlobalKey) to move camera to a specific point.
  void moveTo(LatLng target, {double zoom = 16}) {
    _animatedMove(target, zoom);
  }

  void _animatedMove(LatLng dest, double zoom) {
    // Flutter_map has not full tween built-in pre v7; emulate with a short Timer-based step or just jump.
    // For simplicity, use move (instant) now; placeholder for smoother animation via CameraFit/ease.
    mapController.move(dest, zoom);
  }

  @override
  Widget build(BuildContext context) {
    return FlutterMap(
      mapController: mapController,
      options: MapOptions(
        initialCenter: const LatLng(0,0),
        initialZoom: 2,
        onTap: (_, __) => widget.onMapTap?.call(),
      ),
      children: [
        TileLayer(
          // Use canonical single-host URL per OSM operations guidance (avoid {s} subdomains).
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'my_app_gps',
          maxZoom: 19,
        ),
        MarkerLayer(
          markers: [
            for (final m in widget.markers)
              Marker(
                point: m.position,
                width: 32,
                height: 32,
                child: GestureDetector(
                  onTap: () => widget.onMarkerTap?.call(m.id),
                  child: _MarkerIcon(data: m),
                ),
              )
          ],
        ),
        Positioned(
          right: 8,
          bottom: 8,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(6),
            ),
            child: const Text(
              '© OpenStreetMap contributors',
              style: TextStyle(color: Colors.white, fontSize: 11),
            ),
          ),
        ),
      ],
    );
  }
}

class _MarkerIcon extends StatelessWidget {
  const _MarkerIcon({required this.data});
  final MapMarkerData data;
  @override
  Widget build(BuildContext context) {
    return AnimatedScale(
      duration: const Duration(milliseconds: 200),
      scale: data.isSelected ? 1.2 : 1.0,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
            decoration: BoxDecoration(
              color: data.isSelected ? Colors.green : Colors.blue,
              shape: BoxShape.circle,
              boxShadow: const [BoxShadow(color: Colors.black38, blurRadius: 4)],
            ),
            width: 24,
            height: 24,
            child: const Icon(Icons.location_on, size: 18, color: Colors.white),
          ),
          if (data.heading != null)
            Transform.rotate(
              angle: (data.heading! * 3.1415926535 / 180),
              child: const Icon(Icons.navigation, size: 14, color: Colors.white70),
            )
        ],
      ),
    );
  }
}
