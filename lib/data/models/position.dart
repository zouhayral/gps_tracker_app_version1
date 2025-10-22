import 'package:latlong2/latlong.dart';

class Position {
  const Position({required this.lat, required this.lon, required this.time});

  final double lat;
  final double lon;
  final DateTime time;

  LatLng get toLatLng => LatLng(lat, lon);

  factory Position.fromJson(Map<String, dynamic> json) {
    final lat = (json['latitude'] ?? json['lat']) as num? ?? 0;
    final lon = (json['longitude'] ?? json['lon']) as num? ?? 0;
    final t = (json['fixTime'] ?? json['time'])?.toString();
    final time =
        t != null ? DateTime.parse(t).toLocal() : DateTime.now().toLocal();
    return Position(lat: lat.toDouble(), lon: lon.toDouble(), time: time);
  }
}
