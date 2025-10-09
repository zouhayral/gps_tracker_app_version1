import 'package:flutter/widgets.dart';
import 'package:latlong2/latlong.dart';

/// Abstract adapter to decouple map library from feature code.
abstract class MapAdapter extends Widget {
  const MapAdapter({super.key});
}

/// Basic marker data passed to adapter (device or playback point).
class MapMarkerData {
  final String id;
  final LatLng position;
  final double? heading;
  final bool isSelected;
  final Map<String, dynamic>? meta;
  const MapMarkerData({
    required this.id,
    required this.position,
    this.heading,
    this.isSelected = false,
    this.meta,
  });
}

/// Simple camera fit description (renamed to avoid clash with flutter_map's CameraFit).
class MapCameraFit {
  final LatLng? center;
  final List<LatLng>? boundsPoints; // if provided, center ignored
  const MapCameraFit({this.center, this.boundsPoints});
}
