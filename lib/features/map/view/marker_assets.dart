import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// MarkerAssets preloads and caches commonly used marker images/icons to
/// prevent re-decoding on every marker rebuild.
enum MarkerStatus { online, offline, disconnected }

class MarkerAssets {
  // Prefer SVGs for scalability; only SVGs are used to keep builds small.
  static const String onlineSvg = 'assets/icons/marker_online.svg';
  static const String offlineSvg = 'assets/icons/marker_offline.svg';
  static const String disconnectedSvg = 'assets/icons/marker_disconnected.svg';
  static Future<void> preload(BuildContext context) async {
    // Precache SVGs using flutter_svg's precachePicture to reduce first-render jank.
    if (!context.mounted) return;
    Future<void> tryPrecacheSvg(String assetSvg) async {
      try {
        // Warm the asset bundle by loading bytes (this avoids the first-frame IO cost).
        await rootBundle.load(assetSvg);
      } catch (_) {
        // Ignore missing SVGs; SvgPicture.asset will show an error placeholder.
      }
    }

    await tryPrecacheSvg(onlineSvg);
    await tryPrecacheSvg(offlineSvg);
    await tryPrecacheSvg(disconnectedSvg);
  }

  /// Returns a widget rendering the online/offline marker, preferring SVG.
  static Widget buildMarkerByStatus(
      {required MarkerStatus status, double size = 28}) {
    switch (status) {
      case MarkerStatus.online:
        return SvgPicture.asset(
          onlineSvg,
          width: size,
          height: size,
          // Minimal placeholder to avoid layout shift while SVG is decoding.
          placeholderBuilder: (_) => const SizedBox.shrink(),
        );
      case MarkerStatus.offline:
        return SvgPicture.asset(
          offlineSvg,
          width: size,
          height: size,
          placeholderBuilder: (_) => const SizedBox.shrink(),
        );
      case MarkerStatus.disconnected:
        return SvgPicture.asset(
          disconnectedSvg,
          width: size,
          height: size,
          placeholderBuilder: (_) => const SizedBox.shrink(),
        );
    }
  }
}

/// Call this once after the first frame when a BuildContext is available.
Future<void> precacheCommonMarkers(BuildContext context) async {
  await MarkerAssets.preload(context);
}
