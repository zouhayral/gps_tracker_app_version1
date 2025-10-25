import 'package:flutter/material.dart';

/// MarkerAssets provides commonly used marker icons using Flutter Material Icons.
/// No external assets needed - icons are rendered programmatically.
enum MarkerStatus { online, offline, disconnected }

class MarkerAssets {
  // Use Flutter Material Icons instead of SVG assets
  static const IconData onlineIcon = Icons.location_on;
  static const IconData offlineIcon = Icons.location_off;
  static const IconData disconnectedIcon = Icons.location_off_outlined;

  static const Color onlineColor = Colors.green;
  static const Color offlineColor = Colors.grey;
  static const Color disconnectedColor = Colors.red;

  /// Preload is no longer needed since Material Icons are built-in
  static Future<void> preload(BuildContext context) async {
    // No-op: Material Icons are always available
    // Kept for backward compatibility
  }

  /// Returns a widget rendering the online/offline marker using Material Icons
  static Widget buildMarkerByStatus({
    required MarkerStatus status,
    double size = 28,
  }) {
    switch (status) {
      case MarkerStatus.online:
        return Icon(
          onlineIcon,
          size: size,
          color: onlineColor,
          shadows: const [
            Shadow(
              color: Colors.black54,
              blurRadius: 4,
              offset: Offset(0, 2),
            ),
          ],
        );
      case MarkerStatus.offline:
        return Icon(
          offlineIcon,
          size: size,
          color: offlineColor,
          shadows: const [
            Shadow(
              color: Colors.black54,
              blurRadius: 4,
              offset: Offset(0, 2),
            ),
          ],
        );
      case MarkerStatus.disconnected:
        return Icon(
          disconnectedIcon,
          size: size,
          color: disconnectedColor,
          shadows: const [
            Shadow(
              color: Colors.black54,
              blurRadius: 4,
              offset: Offset(0, 2),
            ),
          ],
        );
    }
  }
}

/// Call this once after the first frame when a BuildContext is available.
/// No longer needed but kept for backward compatibility.
Future<void> precacheCommonMarkers(BuildContext context) async {
  await MarkerAssets.preload(context);
}
