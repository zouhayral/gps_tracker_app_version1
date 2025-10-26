import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';
import 'package:my_app_gps/data/models/geofence.dart';
import 'package:my_app_gps/features/geofencing/providers/geofence_providers.dart';

/// Geofence overlay widget for displaying geofences on the map
///
/// This widget renders all geofences (circles and polygons) on the map
/// with visual distinction for enabled/disabled states.
///
/// Features:
/// - Displays circle geofences with radius
/// - Displays polygon geofences with vertices
/// - Color-codes enabled (primary) vs disabled (gray)
/// - Semi-transparent fill for better visibility
/// - Border stroke for clear boundaries
///
/// Example:
/// ```dart
/// FlutterMap(
///   children: [
///     TileLayer(...),
///     GeofenceOverlayLayer(), // Add geofences
///     MarkerLayer(...),
///   ],
/// )
/// ```
class GeofenceOverlayLayer extends ConsumerWidget {
  const GeofenceOverlayLayer({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final geofencesAsync = ref.watch(geofencesProvider);
    
    return geofencesAsync.when(
      data: (geofences) {
        if (geofences.isEmpty) {
          return const SizedBox.shrink();
        }
        
        return _buildGeofenceLayers(context, geofences);
      },
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
    );
  }

  Widget _buildGeofenceLayers(BuildContext context, List<Geofence> geofences) {
    final circles = <CircleMarker>[];
    final polygons = <Polygon>[];
    
    for (final geofence in geofences) {
      final color = geofence.enabled 
          ? Colors.orange 
          : Colors.grey;
      
      if (geofence.type == 'circle' && _isValidCircle(geofence)) {
        circles.add(_buildCircle(geofence, color));
      } else if (geofence.type == 'polygon' && _isValidPolygon(geofence)) {
        polygons.add(_buildPolygon(geofence, color));
      }
    }
    
    return Stack(
      children: [
        // Circle layer
        if (circles.isNotEmpty)
          CircleLayer(circles: circles),
        
        // Polygon layer
        if (polygons.isNotEmpty)
          PolygonLayer(polygons: polygons),
      ],
    );
  }

  /// Build circle marker from geofence
  CircleMarker _buildCircle(Geofence geofence, Color color) {
    return CircleMarker(
      point: LatLng(geofence.centerLat!, geofence.centerLng!),
      radius: geofence.radius!,
      useRadiusInMeter: true,
      color: color.withOpacity(0.3),
      borderStrokeWidth: 3,
      borderColor: color.withOpacity(0.9),
    );
  }

  /// Build polygon from geofence
  Polygon _buildPolygon(Geofence geofence, Color color) {
    final vertices = geofence.vertices!
        .map((v) => LatLng(v.latitude, v.longitude))
        .toList();
    
    return Polygon(
      points: vertices,
      color: color.withOpacity(0.3),
      borderStrokeWidth: 3,
      borderColor: color.withOpacity(0.9),
    );
  }

  /// Validate circle geofence data
  bool _isValidCircle(Geofence geofence) {
    return geofence.centerLat != null &&
        geofence.centerLng != null &&
        geofence.radius != null &&
        geofence.radius! > 0 &&
        geofence.centerLat!.abs() <= 90 &&
        geofence.centerLng!.abs() <= 180;
  }

  /// Validate polygon geofence data
  bool _isValidPolygon(Geofence geofence) {
    return geofence.vertices != null &&
        geofence.vertices!.length >= 3 &&
        geofence.vertices!.every((v) =>
            v.latitude.abs() <= 90 && v.longitude.abs() <= 180);
  }
}
