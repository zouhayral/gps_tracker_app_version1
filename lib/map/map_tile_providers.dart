/// Map tile providers for different base map layers
///
/// This module provides access to various tile sources including
/// OpenStreetMap and satellite imagery from Esri.
library;

class MapTileSource {
  /// Unique identifier for this tile source
  final String id;

  /// Human-readable name
  final String name;

  /// URL template for fetching tiles
  /// Use {z}, {x}, {y} placeholders for zoom, x-coordinate, y-coordinate
  final String urlTemplate;

  /// Optional overlay URL template for rendering an additional roads/labels layer
  /// When provided, renders as a semi-transparent layer over the base layer
  final String? overlayUrlTemplate;

  /// Opacity for overlay layer (0.0 to 1.0), default 0.5
  final double overlayOpacity;

  /// Attribution text required by the tile provider
  final String attribution;

  /// Maximum zoom level supported by this source (default: 19)
  final int maxZoom;

  /// Minimum zoom level supported by this source (default: 0)
  final int minZoom;

  const MapTileSource({
    required this.id,
    required this.name,
    required this.urlTemplate,
    required this.attribution,
    this.overlayUrlTemplate,
    this.overlayOpacity = 0.5,
    this.maxZoom = 19,
    this.minZoom = 0,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MapTileSource &&
          runtimeType == other.runtimeType &&
          id == other.id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'MapTileSource($id: $name)';
}

/// Collection of available map tile providers
class MapTileProviders {
  MapTileProviders._(); // Private constructor to prevent instantiation

  /// OpenStreetMap base layer
  /// Free and open-source street map
  static const openStreetMap = MapTileSource(
    id: 'osm',
    name: 'OpenStreetMap',
    // Use a community mirror suitable for app traffic (verify availability/policy)
    urlTemplate: 'https://a.tile.openstreetmap.fr/hot/{z}/{x}/{y}.png',
    attribution: '© OpenStreetMap contributors | Tiles: HOT OSM',
  );

  /// Esri World Imagery satellite layer
  /// High-resolution satellite and aerial imagery
  static const esriSatellite = MapTileSource(
    id: 'esri_sat',
    name: 'Esri Satellite',
    urlTemplate:
        'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}',
    attribution: '© Esri – Maxar – Earthstar Geographics',
  );

  /// All available tile sources
  static final List<MapTileSource> all = [
    openStreetMap,
    esriSatellite,
  ];

  /// Get a tile source by ID
  /// Returns null if no source with the given ID exists
  static MapTileSource? getById(String id) {
    try {
      return all.firstWhere((source) => source.id == id);
    } catch (_) {
      return null;
    }
  }

  /// Default tile source (OpenStreetMap)
  static const MapTileSource defaultSource = openStreetMap;
}
