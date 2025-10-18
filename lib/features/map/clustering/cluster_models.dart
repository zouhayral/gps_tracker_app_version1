import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';

/// Input marker data for clustering computation
@immutable
class ClusterableMarker {
  final String id;
  final LatLng position;
  final Map<String, dynamic> metadata; // deviceId, name, status, etc.

  const ClusterableMarker({
    required this.id,
    required this.position,
    required this.metadata,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ClusterableMarker &&
          id == other.id &&
          position == other.position;

  @override
  int get hashCode => Object.hash(id, position);
}

/// Result of clustering computation
@immutable
class ClusterResult {
  /// Cluster ID (generated)
  final String clusterId;

  /// Is this a cluster (true) or individual marker (false)
  final bool isCluster;

  /// Position of cluster centroid or individual marker
  final LatLng position;

  /// Member markers in this cluster (empty for individual markers)
  final List<ClusterableMarker> members;

  /// Count of members (1 for individual markers)
  int get count => isCluster ? members.length : 1;

  const ClusterResult({
    required this.clusterId,
    required this.isCluster,
    required this.position,
    required this.members,
  });

  /// Create individual marker result (no clustering)
  factory ClusterResult.individual(ClusterableMarker marker) {
    return ClusterResult(
      clusterId: marker.id,
      isCluster: false,
      position: marker.position,
      members: [marker],
    );
  }

  /// Create cluster result
  factory ClusterResult.cluster({
    required String clusterId,
    required LatLng centroid,
    required List<ClusterableMarker> members,
  }) {
    return ClusterResult(
      clusterId: clusterId,
      isCluster: true,
      position: centroid,
      members: members,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ClusterResult &&
          clusterId == other.clusterId &&
          isCluster == other.isCluster &&
          members.length == other.members.length;

  @override
  int get hashCode => Object.hash(clusterId, isCluster, members.length);
}

/// Configuration for clustering computation
@immutable
class ClusterConfig {
  /// Minimum zoom level to enable clustering (disable at high zoom)
  final double minZoom;

  /// Maximum zoom level to enable clustering
  final double maxZoom;

  /// Pixel distance threshold at different zoom levels
  /// Map of zoom level to pixel distance
  final Map<int, double> pixelDistanceByZoom;

  /// Minimum markers required to form a cluster
  final int minClusterSize;

  /// Whether to use background isolate for computation
  final bool useIsolate;

  /// Marker count threshold to trigger isolate usage
  final int isolateThreshold;

  const ClusterConfig({
    this.minZoom = 1.0,
    this.maxZoom = 13.0,
    this.pixelDistanceByZoom = const {
      1: 120.0,
      3: 100.0,
      5: 80.0,
      7: 60.0,
      9: 50.0,
      11: 40.0,
      13: 30.0,
    },
    this.minClusterSize = 2,
    this.useIsolate = true,
    this.isolateThreshold = 800,
  });

  /// Get pixel distance threshold for a given zoom level
  double getPixelDistanceForZoom(double zoom) {
    final zoomInt = zoom.floor();

    // Find closest zoom level in map
    int? closestZoom;
    var minDiff = double.infinity;

    for (final z in pixelDistanceByZoom.keys) {
      final diff = (z - zoomInt).abs().toDouble();
      if (diff < minDiff) {
        minDiff = diff;
        closestZoom = z;
      }
    }

    return pixelDistanceByZoom[closestZoom] ?? 60.0;
  }

  /// Check if clustering should be enabled at this zoom level
  bool shouldClusterAtZoom(double zoom) {
    return zoom >= minZoom && zoom <= maxZoom;
  }
}

/// State for cluster provider
@immutable
class ClusterState {
  final List<ClusterResult> results;
  final bool isLoading;
  final String? error;
  final DateTime? lastComputed;
  final int markerCount;
  final int clusterCount;
  final bool usedIsolate;

  const ClusterState({
    required this.results,
    required this.markerCount, required this.clusterCount, this.isLoading = false,
    this.error,
    this.lastComputed,
    this.usedIsolate = false,
  });

  const ClusterState.initial()
      : results = const [],
        isLoading = false,
        error = null,
        lastComputed = null,
        markerCount = 0,
        clusterCount = 0,
        usedIsolate = false;

  ClusterState copyWith({
    List<ClusterResult>? results,
    bool? isLoading,
    String? error,
    DateTime? lastComputed,
    int? markerCount,
    int? clusterCount,
    bool? usedIsolate,
  }) {
    return ClusterState(
      results: results ?? this.results,
      isLoading: isLoading ?? this.isLoading,
      error: error ?? this.error,
      lastComputed: lastComputed ?? this.lastComputed,
      markerCount: markerCount ?? this.markerCount,
      clusterCount: clusterCount ?? this.clusterCount,
      usedIsolate: usedIsolate ?? this.usedIsolate,
    );
  }

  @override
  String toString() {
    return 'ClusterState(markers=$markerCount, clusters=$clusterCount, '
        'loading=$isLoading, isolate=$usedIsolate)';
  }
}
