/// Tile prefetch profile configuration
///
/// Defines the parameters for adaptive tile prefetching:
/// - Zoom range (min/max)
/// - Geographic radius around center point
/// - Concurrency and throttling limits
/// - Fair-use caps to respect tile server policies
library;

import 'package:flutter/foundation.dart';

/// A prefetch profile defining tile download parameters
@immutable
class PrefetchProfile {
  /// Unique identifier for this profile
  final String id;

  /// Human-readable name
  final String name;

  /// Minimum zoom level to prefetch (inclusive)
  final int zoomMin;

  /// Maximum zoom level to prefetch (inclusive)
  final int zoomMax;

  /// Radius in kilometers around center point to prefetch
  final double radiusKm;

  /// Maximum concurrent tile downloads (default: 2-3 to respect servers)
  final int concurrency;

  /// Minimum delay between tile requests in milliseconds
  /// Includes random jitter (50-150ms) on top of this base
  final int throttleMs;

  /// Maximum tiles to download in a single prefetch run
  /// Protects against runaway downloads and respects fair-use
  final int maxTilesPerRun;

  /// Whether this profile is user-customizable
  final bool isCustom;

  const PrefetchProfile({
    required this.id,
    required this.name,
    required this.zoomMin,
    required this.zoomMax,
    required this.radiusKm,
    this.concurrency = 2,
    this.throttleMs = 100,
    this.maxTilesPerRun = 2000,
    this.isCustom = false,
  });

  /// Light profile: minimal prefetch for immediate area
  /// Use case: Quick offline backup of current view
  /// ~50-200 tiles (zoom 12-15, 2km radius)
  static const light = PrefetchProfile(
    id: 'light',
    name: 'Light',
    zoomMin: 12,
    zoomMax: 15,
    radiusKm: 2,
    maxTilesPerRun: 500,
  );

  /// Commute profile: moderate prefetch for typical routes
  /// Use case: Daily commute or known delivery zones
  /// ~500-1000 tiles (zoom 11-16, 5km radius)
  static const commute = PrefetchProfile(
    id: 'commute',
    name: 'Commute',
    zoomMin: 11,
    zoomMax: 16,
    radiusKm: 5,
    concurrency: 3,
    throttleMs: 80,
    maxTilesPerRun: 1500,
  );

  /// Heavy profile: comprehensive prefetch for extended areas
  /// Use case: Rural areas, extended offline operations
  /// ~1500-2000 tiles (zoom 10-17, 10km radius)
  static const heavy = PrefetchProfile(
    id: 'heavy',
    name: 'Heavy',
    zoomMin: 10,
    zoomMax: 17,
    radiusKm: 10,
    concurrency: 3,
    throttleMs: 120,
  );

  /// All built-in profiles
  static const builtInProfiles = [light, commute, heavy];

  /// Get profile by ID, falling back to Light if not found
  static PrefetchProfile fromId(String id) {
    return builtInProfiles.firstWhere(
      (p) => p.id == id,
      orElse: () => light,
    );
  }

  /// Create a custom profile with user-specified parameters
  factory PrefetchProfile.custom({
    required int zoomMin,
    required int zoomMax,
    required double radiusKm,
    int? concurrency,
    int? throttleMs,
    int? maxTilesPerRun,
  }) {
    // Clamp zoom to safe ranges
    final clampedZoomMin = zoomMin.clamp(8, 18);
    final clampedZoomMax = zoomMax.clamp(zoomMin, 18);
    final clampedRadius = radiusKm.clamp(0.5, 20.0);

    return PrefetchProfile(
      id: 'custom',
      name: 'Custom',
      zoomMin: clampedZoomMin,
      zoomMax: clampedZoomMax,
      radiusKm: clampedRadius,
      concurrency: concurrency ?? 2,
      throttleMs: throttleMs ?? 100,
      maxTilesPerRun: maxTilesPerRun ?? 2000,
      isCustom: true,
    );
  }

  /// Estimate total tiles for this profile at a given center point
  /// Rough approximation: tiles ≈ 4^zoom × (radius/earthRadius)^2
  int estimateTileCount() {
    var totalTiles = 0;
    for (var zoom = zoomMin; zoom <= zoomMax; zoom++) {
      // Approximate tiles per zoom level
      // At zoom N, each degree ≈ 2^N tiles
      // Rough estimate: tiles ≈ (radius_km / 40000) * 2^zoom * 4
      final tilesPerDegree = 1 << zoom;
      final degreesRadius = radiusKm / 111.0; // ~111km per degree
      final tilesInRadius = (degreesRadius * tilesPerDegree * 2).ceil();
      totalTiles += tilesInRadius * tilesInRadius;
    }
    return totalTiles.clamp(0, maxTilesPerRun);
  }

  /// Estimate download time in seconds (rough)
  /// Assumes ~100ms average per tile including network + processing
  int estimateDownloadSeconds() {
    final tiles = estimateTileCount();
    final avgTimePerTile = throttleMs + 50; // throttle + avg network time
    final totalMs = (tiles / concurrency) * avgTimePerTile;
    return (totalMs / 1000).ceil();
  }

  /// Copy with modified parameters
  PrefetchProfile copyWith({
    String? id,
    String? name,
    int? zoomMin,
    int? zoomMax,
    double? radiusKm,
    int? concurrency,
    int? throttleMs,
    int? maxTilesPerRun,
    bool? isCustom,
  }) {
    return PrefetchProfile(
      id: id ?? this.id,
      name: name ?? this.name,
      zoomMin: zoomMin ?? this.zoomMin,
      zoomMax: zoomMax ?? this.zoomMax,
      radiusKm: radiusKm ?? this.radiusKm,
      concurrency: concurrency ?? this.concurrency,
      throttleMs: throttleMs ?? this.throttleMs,
      maxTilesPerRun: maxTilesPerRun ?? this.maxTilesPerRun,
      isCustom: isCustom ?? this.isCustom,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PrefetchProfile &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          name == other.name &&
          zoomMin == other.zoomMin &&
          zoomMax == other.zoomMax &&
          radiusKm == other.radiusKm &&
          concurrency == other.concurrency &&
          throttleMs == other.throttleMs &&
          maxTilesPerRun == other.maxTilesPerRun &&
          isCustom == other.isCustom;

  @override
  int get hashCode =>
      Object.hash(
        id,
        name,
        zoomMin,
        zoomMax,
        radiusKm,
        concurrency,
        throttleMs,
        maxTilesPerRun,
        isCustom,
      );

  @override
  String toString() =>
      'PrefetchProfile($name: z$zoomMin-$zoomMax, ${radiusKm}km, '
      '~${estimateTileCount()} tiles, ${estimateDownloadSeconds()}s est)';
}
