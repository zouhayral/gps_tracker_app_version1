import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:my_app_gps/features/map/clustering/cluster_engine.dart';
import 'package:my_app_gps/features/map/clustering/cluster_models.dart';

void main() {
  test('ClusterEngine returns individuals when below minClusterSize', () {
    final engine = ClusterEngine(config: const ClusterConfig(minClusterSize: 3));
    final markers = [
      const ClusterableMarker(id: 'a', position: LatLng(0, 0), metadata: {}),
      const ClusterableMarker(id: 'b', position: LatLng(0.0001, 0.0001), metadata: {}),
    ];
    final viewport = LatLngBounds(const LatLng(-1, -1), const LatLng(1, 1));
    final results = engine.compute(markers: markers, zoom: 10, viewport: viewport);
    expect(results.where((r) => r.isCluster).length, 0);
    expect(results.length, 2);
  });

  test('ClusterEngine forms clusters when enough nearby markers', () {
    final engine = ClusterEngine(config: const ClusterConfig(minClusterSize: 2));
    final markers = [
      const ClusterableMarker(id: 'a', position: LatLng(0, 0), metadata: {}),
      const ClusterableMarker(id: 'b', position: LatLng(0.00005, 0.00005), metadata: {}),
      const ClusterableMarker(id: 'c', position: LatLng(30, 30), metadata: {}),
    ];
    final viewport = LatLngBounds(const LatLng(-90, -180), const LatLng(90, 180));
    final results = engine.compute(markers: markers, zoom: 12, viewport: viewport);
    final clusters = results.where((r) => r.isCluster).toList();
    expect(clusters.length, 1);
    expect(clusters.first.count, 2);
  });
}
