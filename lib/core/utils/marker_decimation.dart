/// 🎯 MARKER DECIMATION & CLUSTERING
/// 
/// Spatial algorithms for reducing marker density while maintaining
/// representative coverage across the viewport.

import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';

/// Represents a screenspace point
class ScreenPoint {
  const ScreenPoint(this.x, this.y);
  final double x;
  final double y;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ScreenPoint &&
          runtimeType == other.runtimeType &&
          x == other.x &&
          y == other.y;

  @override
  int get hashCode => x.hashCode ^ y.hashCode;
}

/// Grid-based marker decimation
/// 
/// Divides screen space into a grid and keeps only one marker per cell.
/// Provides fast, spatially-aware culling that maintains coverage.
class MarkerDecimator {
  /// Decimate markers using grid-based spatial culling
  /// 
  /// [markers] - List of items with positions
  /// [positionGetter] - Function to extract LatLng from item
  /// [screenProjection] - Function to project LatLng to screen coordinates
  /// [maxCount] - Maximum markers to keep
  /// [cellSize] - Grid cell size in pixels (default: 32px)
  /// 
  /// Returns: Sublist of markers, spatially distributed
  static List<T> decimateByGrid<T>({
    required List<T> markers,
    required LatLng Function(T) positionGetter,
    required ScreenPoint Function(LatLng) screenProjection,
    required int maxCount,
    double cellSize = 32.0,
  }) {
    if (markers.length <= maxCount) return markers;

    final buckets = <_GridCell, T>{};

    // Fill grid buckets - first marker in each cell wins
    for (final marker in markers) {
      final latLng = positionGetter(marker);
      final screen = screenProjection(latLng);
      final cell = _GridCell(
        (screen.x / cellSize).floor(),
        (screen.y / cellSize).floor(),
      );

      // Keep first marker in bucket for consistency
      buckets.putIfAbsent(cell, () => marker);

      if (buckets.length >= maxCount) break;
    }

    final result = buckets.values.toList(growable: false);

    if (kDebugMode && markers.length > maxCount) {
      debugPrint(
        '[MarkerDecimator] 🎯 Grid decimation: ${markers.length} → ${result.length} '
        '(${((1 - result.length / markers.length) * 100).toStringAsFixed(1)}% reduction)',
      );
    }

    return result;
  }

  /// Decimate markers using distance-based clustering
  /// 
  /// Groups nearby markers and keeps a representative from each cluster.
  /// More accurate but slower than grid-based decimation.
  static List<T> decimateByDistance<T>({
    required List<T> markers,
    required LatLng Function(T) positionGetter,
    required int maxCount,
    double minDistanceMeters = 100.0,
  }) {
    if (markers.length <= maxCount) return markers;

    final distance = const Distance();
    final clusters = <List<T>>[];
    final processed = <bool>[];

    // Initialize processed flags
    for (var i = 0; i < markers.length; i++) {
      processed.add(false);
    }

    // Simple clustering: for each unprocessed marker, create a cluster
    // of all nearby markers
    for (var i = 0; i < markers.length; i++) {
      if (processed[i]) continue;

      final cluster = <T>[markers[i]];
      processed[i] = true;
      final centerPos = positionGetter(markers[i]);

      // Find nearby markers
      for (var j = i + 1; j < markers.length; j++) {
        if (processed[j]) continue;

        final pos = positionGetter(markers[j]);
        final dist = distance.distance(centerPos, pos);

        if (dist <= minDistanceMeters) {
          cluster.add(markers[j]);
          processed[j] = true;
        }
      }

      clusters.add(cluster);

      // Early exit if we have enough clusters
      if (clusters.length >= maxCount) break;
    }

    // Take first marker from each cluster (could be centroid in future)
    final result = clusters
        .map((cluster) => cluster.first)
        .take(maxCount)
        .toList(growable: false);

    if (kDebugMode && markers.length > maxCount) {
      debugPrint(
        '[MarkerDecimator] 🎯 Distance clustering: ${markers.length} → ${result.length} '
        '(${clusters.length} clusters, ${minDistanceMeters}m threshold)',
      );
    }

    return result;
  }

  /// Smart decimation that prefers important markers
  /// 
  /// Uses a priority function to keep the most important markers when culling.
  static List<T> decimateByPriority<T>({
    required List<T> markers,
    required double Function(T) priorityGetter,
    required int maxCount,
  }) {
    if (markers.length <= maxCount) return markers;

    // Sort by priority (descending) and take top N
    final sorted = List<T>.from(markers)
      ..sort((a, b) => priorityGetter(b).compareTo(priorityGetter(a)));

    final result = sorted.take(maxCount).toList(growable: false);

    if (kDebugMode) {
      final avgPriorityKept =
          result.map(priorityGetter).reduce((a, b) => a + b) / result.length;
      final avgPriorityAll =
          markers.map(priorityGetter).reduce((a, b) => a + b) / markers.length;
      debugPrint(
        '[MarkerDecimator] 🎯 Priority decimation: ${markers.length} → ${result.length} '
        '(avg priority: ${avgPriorityAll.toStringAsFixed(2)} → ${avgPriorityKept.toStringAsFixed(2)})',
      );
    }

    return result;
  }

  /// Hybrid decimation: Grid-based with priority weighting
  /// 
  /// Divides into grid cells, but chooses highest priority marker in each cell.
  static List<T> decimateHybrid<T>({
    required List<T> markers,
    required LatLng Function(T) positionGetter,
    required ScreenPoint Function(LatLng) screenProjection,
    required double Function(T) priorityGetter,
    required int maxCount,
    double cellSize = 32.0,
  }) {
    if (markers.length <= maxCount) return markers;

    final buckets = <_GridCell, T>{};

    // Fill grid buckets - keep highest priority marker in each cell
    for (final marker in markers) {
      final latLng = positionGetter(marker);
      final screen = screenProjection(latLng);
      final cell = _GridCell(
        (screen.x / cellSize).floor(),
        (screen.y / cellSize).floor(),
      );

      final existing = buckets[cell];
      if (existing == null ||
          priorityGetter(marker) > priorityGetter(existing)) {
        buckets[cell] = marker;
      }

      if (buckets.length >= maxCount * 1.2) {
        // Trim to target size
        break;
      }
    }

    // If we have more than needed, take top priority ones
    var result = buckets.values.toList();
    if (result.length > maxCount) {
      result.sort((a, b) => priorityGetter(b).compareTo(priorityGetter(a)));
      result = result.take(maxCount).toList(growable: false);
    }

    if (kDebugMode && markers.length > maxCount) {
      debugPrint(
        '[MarkerDecimator] 🎯 Hybrid decimation: ${markers.length} → ${result.length}',
      );
    }

    return result;
  }
}

/// Grid cell coordinate
class _GridCell {
  const _GridCell(this.x, this.y);
  final int x;
  final int y;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is _GridCell &&
          runtimeType == other.runtimeType &&
          x == other.x &&
          y == other.y;

  @override
  int get hashCode => x.hashCode ^ y.hashCode;
}

// ============================================================================
// 🎯 POLYLINE SIMPLIFICATION
// ============================================================================

/// Douglas-Peucker polyline simplification
/// 
/// Reduces polyline complexity while preserving shape.
/// Essential for maintaining performance with long trip tracks.
class PolylineSimplifier {
  /// Simplify polyline using Douglas-Peucker algorithm
  /// 
  /// [points] - Original polyline points
  /// [epsilon] - Tolerance in meters (larger = more aggressive simplification)
  /// 
  /// Returns: Simplified polyline with fewer points
  static List<LatLng> simplify(List<LatLng> points, double epsilon) {
    if (points.length <= 2 || epsilon <= 0) return points;

    final result = _douglasPeucker(points, epsilon);

    if (kDebugMode && points.length > result.length) {
      debugPrint(
        '[PolylineSimplifier] 📉 Simplified: ${points.length} → ${result.length} points '
        '(${((1 - result.length / points.length) * 100).toStringAsFixed(1)}% reduction, '
        'epsilon: ${epsilon}m)',
      );
    }

    return result;
  }

  /// Douglas-Peucker recursive implementation
  static List<LatLng> _douglasPeucker(List<LatLng> points, double epsilon) {
    if (points.length <= 2) return points;

    // Find point with maximum distance from line segment
    var maxDistance = 0.0;
    var maxIndex = 0;
    final start = points.first;
    final end = points.last;

    for (var i = 1; i < points.length - 1; i++) {
      final distance = _perpendicularDistance(points[i], start, end);
      if (distance > maxDistance) {
        maxDistance = distance;
        maxIndex = i;
      }
    }

    // If max distance is greater than epsilon, recursively simplify
    if (maxDistance > epsilon) {
      // Recursive call on both segments
      final left = _douglasPeucker(points.sublist(0, maxIndex + 1), epsilon);
      final right = _douglasPeucker(points.sublist(maxIndex), epsilon);

      // Combine results (removing duplicate middle point)
      return [...left.sublist(0, left.length - 1), ...right];
    } else {
      // All points are within epsilon, return just endpoints
      return [start, end];
    }
  }

  /// Calculate perpendicular distance from point to line segment
  static double _perpendicularDistance(
    LatLng point,
    LatLng lineStart,
    LatLng lineEnd,
  ) {
    const distance = Distance();

    // If line segment is a point, return distance to that point
    if (lineStart.latitude == lineEnd.latitude &&
        lineStart.longitude == lineEnd.longitude) {
      return distance.distance(point, lineStart);
    }

    // Calculate perpendicular distance using cross-track distance
    final distStartToEnd = distance.distance(lineStart, lineEnd);
    final distStartToPoint = distance.distance(lineStart, point);
    final distEndToPoint = distance.distance(lineEnd, point);

    // Use law of cosines to find perpendicular distance
    // This is an approximation suitable for small distances
    final s = (distStartToEnd + distStartToPoint + distEndToPoint) / 2;
    final area = math.sqrt(
      math.max(
        0,
        s * (s - distStartToEnd) * (s - distStartToPoint) * (s - distEndToPoint),
      ),
    );

    return 2 * area / distStartToEnd;
  }

  /// Batch simplify multiple polylines
  static Map<K, List<LatLng>> simplifyBatch<K>(
    Map<K, List<LatLng>> polylines,
    double epsilon,
  ) {
    if (epsilon <= 0) return polylines;

    final result = <K, List<LatLng>>{};
    var totalBefore = 0;
    var totalAfter = 0;

    for (final entry in polylines.entries) {
      totalBefore += entry.value.length;
      final simplified = simplify(entry.value, epsilon);
      totalAfter += simplified.length;
      result[entry.key] = simplified;
    }

    if (kDebugMode && totalBefore > totalAfter) {
      debugPrint(
        '[PolylineSimplifier] 📉 Batch simplified ${polylines.length} polylines: '
        '$totalBefore → $totalAfter points '
        '(${((1 - totalAfter / totalBefore) * 100).toStringAsFixed(1)}% reduction)',
      );
    }

    return result;
  }
}
