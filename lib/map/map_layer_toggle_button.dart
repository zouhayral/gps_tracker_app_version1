import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_app_gps/map/map_tile_source_provider.dart';
import 'package:my_app_gps/map/map_tile_providers.dart';

/// Floating action button to toggle between map tile sources
/// Shows current map type (Street/Satellite) and allows quick switching
class MapLayerToggleButton extends ConsumerWidget {
  const MapLayerToggleButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentSource = ref.watch(mapTileSourceProvider);
    final notifier = ref.read(mapTileSourceProvider.notifier);

    return FloatingActionButton.extended(
      onPressed: notifier.toggleSource,
      icon: Icon(_getIconForSource(currentSource)),
      label: Text(currentSource.name),
      tooltip: 'Switch map layer',
      heroTag: 'map_layer_toggle',
    );
  }

  IconData _getIconForSource(MapTileSource source) {
    switch (source.id) {
      case 'esri_sat':
        return Icons.satellite_alt;
      case 'osm':
      default:
        return Icons.map;
    }
  }
}

/// Compact icon-only toggle button for space-constrained layouts
class MapLayerToggleIconButton extends ConsumerWidget {
  const MapLayerToggleIconButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentSource = ref.watch(mapTileSourceProvider);
    final notifier = ref.read(mapTileSourceProvider.notifier);

    return IconButton(
      onPressed: notifier.toggleSource,
      icon: Icon(_getIconForSource(currentSource)),
      tooltip: 'Switch to ${_getNextSourceName(currentSource)}',
    );
  }

  IconData _getIconForSource(MapTileSource source) {
    switch (source.id) {
      case 'esri_sat':
        return Icons.satellite_alt;
      case 'osm':
      default:
        return Icons.map;
    }
  }

  String _getNextSourceName(MapTileSource current) {
    final currentIndex = MapTileProviders.all.indexOf(current);
    final nextIndex = (currentIndex + 1) % MapTileProviders.all.length;
    return MapTileProviders.all[nextIndex].name;
  }
}

/// Bottom sheet selector for choosing map tile source
/// Useful when there are more than 2 tile sources
class MapLayerSelector extends ConsumerWidget {
  const MapLayerSelector({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentSource = ref.watch(mapTileSourceProvider);
    final notifier = ref.read(mapTileSourceProvider.notifier);

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Text(
              'Map Layer',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          ...MapTileProviders.all.map((source) {
            final isSelected = source.id == currentSource.id;
            return ListTile(
              leading: Icon(
                _getIconForSource(source),
                color: isSelected ? Theme.of(context).primaryColor : null,
              ),
              title: Text(source.name),
              subtitle: Text(source.attribution),
              trailing: isSelected
                  ? Icon(Icons.check, color: Theme.of(context).primaryColor)
                  : null,
              selected: isSelected,
              onTap: () {
                notifier.setSource(source);
                Navigator.pop(context);
              },
            );
          }),
        ],
      ),
    );
  }

  IconData _getIconForSource(MapTileSource source) {
    switch (source.id) {
      case 'esri_sat':
        return Icons.satellite_alt;
      case 'osm':
      default:
        return Icons.map;
    }
  }

  /// Show the selector as a bottom sheet
  static void show(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      builder: (context) => const MapLayerSelector(),
    );
  }
}
