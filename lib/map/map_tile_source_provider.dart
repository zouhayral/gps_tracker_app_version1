import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'map_tile_providers.dart';

/// Provider for managing the currently selected map tile source
/// Persists user selection using SharedPreferences
final mapTileSourceProvider =
    StateNotifierProvider<MapTileSourceNotifier, MapTileSource>(
  (ref) => MapTileSourceNotifier(),
);

/// Notifier that manages the selected map tile source
/// Automatically loads saved preference on init and persists changes
class MapTileSourceNotifier extends StateNotifier<MapTileSource> {
  static const _prefsKey = 'selected_map_source';
  
  // Track last switch timestamp to force aggressive rebuilds
  int _lastSwitchTimestamp = DateTime.now().millisecondsSinceEpoch;
  int get lastSwitchTimestamp => _lastSwitchTimestamp;

  MapTileSourceNotifier() : super(MapTileProviders.defaultSource) {
    _loadSavedSource();
  }

  /// Load previously saved tile source from SharedPreferences
  Future<void> _loadSavedSource() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedId = prefs.getString(_prefsKey);
      
      if (savedId != null) {
        final source = MapTileProviders.getById(savedId);
        if (source != null) {
          if (kDebugMode) {
            debugPrint('[PROVIDER] Loaded saved map source: ${source.id} (${source.name})');
          }
          state = source;
        } else {
          if (kDebugMode) {
            debugPrint('[PROVIDER] Saved ID not found: $savedId, using default');
          }
        }
      } else {
        if (kDebugMode) {
          debugPrint('[PROVIDER] No saved preference, using default: ${state.id}');
        }
      }
    } catch (e) {
      // If loading fails, keep default source
      if (kDebugMode) {
        debugPrint('[PROVIDER] Failed to load saved source: $e');
      }
    }
  }

  /// Set the active tile source and persist the choice
  Future<void> setSource(MapTileSource newSource) async {
    // Update timestamp to force FlutterMap rebuild with new key
    _lastSwitchTimestamp = DateTime.now().millisecondsSinceEpoch;
    
    if (kDebugMode) {
      debugPrint('[PROVIDER] 🔄 Updating map tile source to: ${newSource.id} (${newSource.name})');
      debugPrint('[PROVIDER] 🕐 Switch timestamp: $_lastSwitchTimestamp');
    }
    
    state = newSource;
    
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefsKey, newSource.id);
      if (kDebugMode) {
        debugPrint('[PROVIDER] ✅ Saved preference: ${newSource.id}');
      }
    } catch (e) {
      // Handle persistence error gracefully
      // State is still updated even if save fails
      if (kDebugMode) {
        debugPrint('[PROVIDER] ❌ Failed to save preference: $e');
      }
    }
    
    // NOTE: We don't clear FMTC cache here to preserve offline functionality
    // The timestamp-based keys in flutter_map_adapter.dart force fresh tile rendering
    if (kDebugMode) {
      debugPrint('[PROVIDER] 🎯 Timestamp-based keys will force immediate tile refresh');
    }
  }

  /// Toggle between available sources (useful for quick switch)
  Future<void> toggleSource() async {
    final currentIndex = MapTileProviders.all.indexOf(state);
    final nextIndex = (currentIndex + 1) % MapTileProviders.all.length;
    await setSource(MapTileProviders.all[nextIndex]);
  }

  /// Reset to default source (OpenStreetMap)
  Future<void> resetToDefault() async {
    await setSource(MapTileProviders.defaultSource);
  }
}
