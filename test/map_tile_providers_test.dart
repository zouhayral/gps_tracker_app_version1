import 'package:flutter_test/flutter_test.dart';
import 'package:my_app_gps/map/map_tile_providers.dart';

void main() {
  group('MapTileProviders', () {
    test('provides OpenStreetMap source', () {
      expect(MapTileProviders.openStreetMap.id, 'osm');
      expect(MapTileProviders.openStreetMap.name, 'OpenStreetMap');
      // Accept either the primary OSM hostname or the HOT mirror used in app
      final url = MapTileProviders.openStreetMap.urlTemplate;
      expect(
        url.contains('openstreetmap.org') ||
            url.contains('openstreetmap.fr'),
        isTrue,
      );
    });

    test('provides Esri Satellite source', () {
      expect(MapTileProviders.esriSatellite.id, 'esri_sat');
      expect(MapTileProviders.esriSatellite.name, 'Esri Satellite');
      expect(
        MapTileProviders.esriSatellite.urlTemplate,
        contains('arcgisonline.com'),
      );
    });

    test('all sources list contains expected providers', () {
      // We currently ship 2 providers (OSM, Esri Satellite)
      expect(MapTileProviders.all.length, equals(2));
      expect(MapTileProviders.all, contains(MapTileProviders.openStreetMap));
      expect(MapTileProviders.all, contains(MapTileProviders.esriSatellite));
    });

    test('getById returns correct source', () {
      final osmSource = MapTileProviders.getById('osm');
      expect(osmSource, MapTileProviders.openStreetMap);

      final esriSource = MapTileProviders.getById('esri_sat');
      expect(esriSource, MapTileProviders.esriSatellite);
    });

    test('getById returns null for unknown id', () {
      final unknownSource = MapTileProviders.getById('unknown');
      expect(unknownSource, isNull);
    });

    test('defaultSource is OpenStreetMap', () {
      expect(MapTileProviders.defaultSource, MapTileProviders.openStreetMap);
    });

    test('MapTileSource equality works correctly', () {
      const source1 = MapTileSource(
        id: 'test',
        name: 'Test',
        urlTemplate: 'https://test.com/{z}/{x}/{y}.png',
        attribution: 'Test',
      );

      const source2 = MapTileSource(
        id: 'test',
        name: 'Test Different Name',
        urlTemplate: 'https://different.com/{z}/{x}/{y}.png',
        attribution: 'Different',
      );

      const source3 = MapTileSource(
        id: 'different',
        name: 'Test',
        urlTemplate: 'https://test.com/{z}/{x}/{y}.png',
        attribution: 'Test',
      );

      expect(source1, source2); // Same id
      expect(source1, isNot(source3)); // Different id
    });
  });
}
