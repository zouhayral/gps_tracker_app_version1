import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:my_app_gps/core/map/modern_marker_painter.dart';

/// Widget wrapper for modern markers in flutter_map
///
/// This widget renders the modern marker using CustomPaint, which flutter_map
/// can then use as a marker child. It automatically determines the marker size
/// based on zoom level and selection state.
///
/// Usage:
/// ```dart
/// Marker(
///   point: LatLng(lat, lng),
///   child: ModernMarkerFlutterMapWidget(
///     name: 'Vehicle 1',
///     online: true,
///     engineOn: true,
///     moving: true,
///     isSelected: false,
///     zoomLevel: 12.0,
///   ),
/// )
/// ```

class ModernMarkerFlutterMapWidget extends StatelessWidget {
  const ModernMarkerFlutterMapWidget({
    required this.name,
    required this.online,
    required this.engineOn,
    required this.moving,
    this.isSelected = false,
    this.zoomLevel = 12.0,
    this.speed,
    super.key,
  });

  final String name;
  final bool online;
  final bool engineOn;
  final bool moving;
  final bool isSelected;
  final double zoomLevel;
  final double? speed;

  /// Determine if we should use compact layout based on zoom level
  bool get _useCompact {
    // Use compact markers at lower zoom levels (more zoomed out)
    // At zoom 10 and below, use compact
    // At zoom 13 and above, use full
    // Between 10-13, transition based on selection
    if (zoomLevel <= 10.0) return true;
    if (zoomLevel >= 13.0) return false;
    
    // In transition zone, selected markers stay full
    return !isSelected;
  }

  /// Get marker size based on compact mode
  MarkerSize get _markerSize => _useCompact ? MarkerSize.compact : MarkerSize.full;

  @override
  Widget build(BuildContext context) {
    final size = _markerSize;
    
    // Add selection scaling
    final scale = isSelected ? 1.2 : 1.0;
    
    return Transform.scale(
      scale: scale,
      child: SizedBox(
        width: size.width,
        height: size.height,
        child: CustomPaint(
          painter: ModernMarkerPainter(
            name: name,
            online: online,
            engineOn: engineOn,
            moving: moving,
            compact: _useCompact,
            speed: speed,
          ),
        ),
      ),
    );
  }
}

/// Pre-rendered bitmap marker for better performance
///
/// This is an alternative approach that pre-renders the marker to an image
/// bitmap and caches it. This can be more efficient when there are many markers
/// on screen, as it avoids re-painting every frame.
///
/// Usage:
/// ```dart
/// // In your state:
/// ui.Image? _markerImage;
/// 
/// // In initState or when marker state changes:
/// _markerImage = await ModernMarkerBitmapWidget.generateImage(
///   name: 'Vehicle 1',
///   online: true,
///   engineOn: true,
///   moving: true,
/// );
/// 
/// // In build:
/// Marker(
///   point: LatLng(lat, lng),
///   child: ModernMarkerBitmapWidget(image: _markerImage),
/// )
/// ```

class ModernMarkerBitmapWidget extends StatelessWidget {
  const ModernMarkerBitmapWidget({
    required this.image,
    this.isSelected = false,
    super.key,
  });

  final ui.Image? image;
  final bool isSelected;

  @override
  Widget build(BuildContext context) {
    if (image == null) {
      return const SizedBox.shrink();
    }

    final scale = isSelected ? 1.2 : 1.0;

    return Transform.scale(
      scale: scale,
      child: SizedBox(
        width: image!.width.toDouble(),
        height: image!.height.toDouble(),
        child: CustomPaint(
          painter: _BitmapPainter(image: image!),
        ),
      ),
    );
  }

  /// Generate marker image (for pre-rendering)
  static Future<ui.Image> generateImage({
    required String name,
    required bool online,
    required bool engineOn,
    required bool moving,
    bool compact = false,
    double? speed,
    double pixelRatio = 2.0,
  }) async {
    final size = compact ? MarkerSize.compact : MarkerSize.full;
    
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);

    final painter = ModernMarkerPainter(
      name: name,
      online: online,
      engineOn: engineOn,
      moving: moving,
      compact: compact,
      speed: speed,
    );

    painter.paint(canvas, Size(size.width, size.height));

    final picture = recorder.endRecording();
    final image = await picture.toImage(
      (size.width * pixelRatio).toInt(),
      (size.height * pixelRatio).toInt(),
    );

    return image;
  }
}

/// Bitmap painter for pre-rendered markers
class _BitmapPainter extends CustomPainter {
  _BitmapPainter({required this.image});

  final ui.Image image;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawImage(image, Offset.zero, Paint());
  }

  @override
  bool shouldRepaint(_BitmapPainter oldDelegate) {
    return oldDelegate.image != image;
  }
}
