import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Manages marker icon preloading and caching for optimal performance
/// Reduces first-draw latency by loading all icon assets on initialization
/// Uses Flutter Material Icons instead of PNG assets
class MarkerIconManager {
  MarkerIconManager._();

  static final MarkerIconManager instance = MarkerIconManager._();

  final Map<String, ui.Image> _iconCache = {};
  bool _isInitialized = false;
  Completer<void>? _initCompleter;

  /// Preload all marker icons using Flutter Material Icons
  Future<void> preloadIcons() async {
    if (_isInitialized) return;
    if (_initCompleter != null) return _initCompleter!.future;

    _initCompleter = Completer<void>();

    try {
      final stopwatch = Stopwatch()..start();

      // Define icon configurations with Flutter Material Icons
      const iconsToLoad = [
        _IconConfig('marker_online', Icons.location_on, Colors.green, 64),
        _IconConfig('marker_offline', Icons.location_off, Colors.grey, 64),
        _IconConfig('marker_selected', Icons.my_location, Colors.blue, 64),
        _IconConfig('marker_moving', Icons.directions_car, Colors.orange, 64),
        _IconConfig('marker_stopped', Icons.pause_circle_filled, Colors.red, 64),
      ];

      // Load all icons in parallel
      final results = await Future.wait(
        iconsToLoad.map(_loadIcon),
      );

      // Count successes
      final loaded = results.where((r) => r != null).length;

      stopwatch.stop();

      if (kDebugMode) {
        debugPrint(
          '[MarkerIcons] Preloaded $loaded/${iconsToLoad.length} icons in ${stopwatch.elapsedMilliseconds}ms',
        );
      }

      _isInitialized = true;
      _initCompleter!.complete();
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[MarkerIcons] Error preloading icons: $e');
      }
      _initCompleter!.completeError(e);
    }
  }

  /// Load a single icon from Flutter Material Icon
  Future<ui.Image?> _loadIcon(_IconConfig config) async {
    try {
      // Create icon image from IconData
      final pictureRecorder = ui.PictureRecorder();
      final canvas = Canvas(pictureRecorder);
      
      // Draw the icon
      final textPainter = TextPainter(textDirection: ui.TextDirection.ltr);
      textPainter.text = TextSpan(
        text: String.fromCharCode(config.icon.codePoint),
        style: TextStyle(
          fontSize: config.size.toDouble(),
          fontFamily: config.icon.fontFamily,
          package: config.icon.fontPackage,
          color: config.color,
        ),
      );
      
      textPainter.layout();
      textPainter.paint(canvas, Offset.zero);
      
      // Convert to image
      final picture = pictureRecorder.endRecording();
      final image = await picture.toImage(config.size, config.size);
      
      _iconCache[config.key] = image;

      if (kDebugMode) {
        debugPrint('[MarkerIcons] ✓ Loaded ${config.key}');
      }

      return image;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[MarkerIcons] ✗ Failed to load ${config.key}: $e');
      }
      return null;
    }
  }

  /// Get a cached icon by key
  ui.Image? getIcon(String key) => _iconCache[key];

  /// Check if icons are loaded
  bool get isReady => _isInitialized;

  /// Get cache statistics
  Map<String, dynamic> getStats() {
    return {
      'loaded_icons': _iconCache.length,
      'is_ready': _isInitialized,
      'cached_keys': _iconCache.keys.toList(),
    };
  }

  /// Clear icon cache (for testing/memory management)
  void clear() {
    _iconCache.clear();
    _isInitialized = false;
    _initCompleter = null;
  }
}

/// Configuration for an icon to load
class _IconConfig {
  const _IconConfig(this.key, this.icon, this.color, this.size);

  final String key;
  final IconData icon;
  final Color color;
  final int size;
}

/// Widget to ensure icons are preloaded before building
class PreloadedMarkerIcons extends StatefulWidget {
  const PreloadedMarkerIcons({
    required this.child,
    this.onLoaded,
    super.key,
  });

  final Widget child;
  final VoidCallback? onLoaded;

  @override
  State<PreloadedMarkerIcons> createState() => _PreloadedMarkerIconsState();
}

class _PreloadedMarkerIconsState extends State<PreloadedMarkerIcons> {
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadIcons();
  }

  Future<void> _loadIcons() async {
    await MarkerIconManager.instance.preloadIcons();
    if (mounted) {
      setState(() => _isLoading = false);
      widget.onLoaded?.call();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Loading map icons...'),
          ],
        ),
      );
    }
    return widget.child;
  }
}
