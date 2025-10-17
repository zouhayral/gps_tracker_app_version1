import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Manages marker icon preloading and caching for optimal performance
/// Reduces first-draw latency by loading all icon assets on initialization
class MarkerIconManager {
  MarkerIconManager._();

  static final MarkerIconManager instance = MarkerIconManager._();

  final Map<String, ui.Image> _iconCache = {};
  bool _isInitialized = false;
  Completer<void>? _initCompleter;

  /// Preload all marker icons
  Future<void> preloadIcons() async {
    if (_isInitialized) return;
    if (_initCompleter != null) return _initCompleter!.future;

    _initCompleter = Completer<void>();

    try {
      final stopwatch = Stopwatch()..start();

      // Define icon configurations
      const iconsToLoad = [
        _IconConfig('marker_online', 'assets/icons/online.png', 64),
        _IconConfig('marker_offline', 'assets/icons/offline.png', 64),
        _IconConfig('marker_selected', 'assets/icons/selected.png', 64),
        _IconConfig('marker_moving', 'assets/icons/moving.png', 64),
        _IconConfig('marker_stopped', 'assets/icons/stopped.png', 64),
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

  /// Load a single icon
  Future<ui.Image?> _loadIcon(_IconConfig config) async {
    try {
      final data = await rootBundle.load(config.path);
      final bytes = data.buffer.asUint8List();
      final codec = await ui.instantiateImageCodec(
        bytes,
        targetWidth: config.size,
        targetHeight: config.size,
      );
      final frame = await codec.getNextFrame();
      _iconCache[config.key] = frame.image;

      if (kDebugMode) {
        debugPrint('[MarkerIcons] ✓ Loaded ${config.key}');
      }

      return frame.image;
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
  const _IconConfig(this.key, this.path, this.size);

  final String key;
  final String path;
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
