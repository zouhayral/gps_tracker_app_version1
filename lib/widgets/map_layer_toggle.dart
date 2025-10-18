import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:my_app_gps/map/map_tile_providers.dart';

class MapLayerToggleButton extends StatelessWidget {
  final MapTileSource current;
  final ValueChanged<MapTileSource> onChanged;

  const MapLayerToggleButton({
    required this.current, required this.onChanged, super.key,
  });

  IconData _iconFor(MapTileSource s) {
    // Satellite mode: show satellite icon
    if (s.id == MapTileProviders.esriSatellite.id) {
      return Icons.satellite_alt;
    }
    // Default: street map icon
    return Icons.map;
  }

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<MapTileSource>(
      tooltip: 'Map layer',
      icon: const Icon(Icons.layers),
      itemBuilder: (context) => MapTileProviders.all
          .map((s) => PopupMenuItem<MapTileSource>(
                value: s,
                child: Row(
                  children: [
                    Icon(_iconFor(s)),
                    const SizedBox(width: 8),
                    Expanded(child: Text(s.name)),
                    if (s.id == current.id)
                      const Padding(
                        padding: EdgeInsets.only(left: 8),
                        child: Icon(Icons.check, size: 18),
                      ),
                  ],
                ),
              ),)
          .toList(),
      onSelected: (source) {
        if (kDebugMode) {
          debugPrint('[TOGGLE] User switched to ${source.id} (${source.name})');
        }
        onChanged(source);
      },
    );
  }
}
