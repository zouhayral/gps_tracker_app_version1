import 'package:flutter/foundation.dart';

/// Monitors marker update performance and efficiency
class MarkerPerformanceMonitor {
  MarkerPerformanceMonitor._();

  static final MarkerPerformanceMonitor instance = MarkerPerformanceMonitor._();

  final List<_MarkerUpdateMetric> _metrics = [];
  final int _maxMetrics = 100;

  DateTime? _lastUpdate;
  int _totalUpdates = 0;
  int _totalCreated = 0;
  int _totalReused = 0;
  int _totalRemoved = 0;

  /// Record a marker update
  void recordUpdate({
    required int markerCount,
    required int created,
    required int reused,
    required int removed,
    required Duration processingTime,
  }) {
    final now = DateTime.now();
    final metric = _MarkerUpdateMetric(
      timestamp: now,
      markerCount: markerCount,
      created: created,
      reused: reused,
      removed: removed,
      processingTime: processingTime,
      timeSinceLastUpdate:
          _lastUpdate != null ? now.difference(_lastUpdate!) : null,
    );

    _metrics.add(metric);
    if (_metrics.length > _maxMetrics) {
      _metrics.removeAt(0);
    }

    _lastUpdate = now;
    _totalUpdates++;
    _totalCreated += created;
    _totalReused += reused;
    _totalRemoved += removed;

    if (kDebugMode && _totalUpdates % 10 == 0) {
      _printStats();
    }
  }

  /// Get current statistics
  MarkerPerformanceStats getStats() {
    if (_metrics.isEmpty) {
      return const MarkerPerformanceStats(
        averageProcessingMs: 0,
        averageUpdateFrequencyMs: 0,
        averageReuseRate: 0,
        totalUpdates: 0,
        totalCreated: 0,
        totalReused: 0,
        totalRemoved: 0,
        peakProcessingMs: 0,
        minProcessingMs: 0,
      );
    }

    final processingTimes =
        _metrics.map((m) => m.processingTime.inMilliseconds).toList();
    final updateFrequencies = _metrics
        .where((m) => m.timeSinceLastUpdate != null)
        .map((m) => m.timeSinceLastUpdate!.inMilliseconds)
        .toList();

    final avgProcessing = processingTimes.isEmpty
        ? 0.0
        : processingTimes.reduce((a, b) => a + b) / processingTimes.length;

    final avgFrequency = updateFrequencies.isEmpty
        ? 0.0
        : updateFrequencies.reduce((a, b) => a + b) / updateFrequencies.length;

    final totalOperations = _totalCreated + _totalReused;
    final reuseRate =
        totalOperations == 0 ? 0.0 : _totalReused / totalOperations;

    return MarkerPerformanceStats(
      averageProcessingMs: avgProcessing,
      averageUpdateFrequencyMs: avgFrequency,
      averageReuseRate: reuseRate,
      totalUpdates: _totalUpdates,
      totalCreated: _totalCreated,
      totalReused: _totalReused,
      totalRemoved: _totalRemoved,
      peakProcessingMs: processingTimes.isEmpty
          ? 0
          : processingTimes.reduce((a, b) => a > b ? a : b),
      minProcessingMs: processingTimes.isEmpty
          ? 0
          : processingTimes.reduce((a, b) => a < b ? a : b),
    );
  }

  /// Print statistics to debug console
  void _printStats() {
    final stats = getStats();
    debugPrint('[MarkerPerf] '
        'Updates: ${stats.totalUpdates}, '
        'Avg Process: ${stats.averageProcessingMs.toStringAsFixed(1)}ms, '
        'Reuse Rate: ${(stats.averageReuseRate * 100).toStringAsFixed(1)}%, '
        'Update Freq: ${stats.averageUpdateFrequencyMs.toStringAsFixed(0)}ms');
  }

  /// Reset all metrics
  void reset() {
    _metrics.clear();
    _lastUpdate = null;
    _totalUpdates = 0;
    _totalCreated = 0;
    _totalReused = 0;
    _totalRemoved = 0;
  }

  /// Check if performance meets targets
  bool meetsPerformanceTargets() {
    final stats = getStats();
    return stats.averageProcessingMs < 16 && // < 1 frame at 60fps
        stats.averageReuseRate > 0.7; // > 70% reuse rate
  }
}

/// Metric for a single marker update
class _MarkerUpdateMetric {
  const _MarkerUpdateMetric({
    required this.timestamp,
    required this.markerCount,
    required this.created,
    required this.reused,
    required this.removed,
    required this.processingTime,
    this.timeSinceLastUpdate,
  });

  final DateTime timestamp;
  final int markerCount;
  final int created;
  final int reused;
  final int removed;
  final Duration processingTime;
  final Duration? timeSinceLastUpdate;
}

/// Aggregated performance statistics
class MarkerPerformanceStats {
  const MarkerPerformanceStats({
    required this.averageProcessingMs,
    required this.averageUpdateFrequencyMs,
    required this.averageReuseRate,
    required this.totalUpdates,
    required this.totalCreated,
    required this.totalReused,
    required this.totalRemoved,
    required this.peakProcessingMs,
    required this.minProcessingMs,
  });

  final double averageProcessingMs;
  final double averageUpdateFrequencyMs;
  final double averageReuseRate;
  final int totalUpdates;
  final int totalCreated;
  final int totalReused;
  final int totalRemoved;
  final int peakProcessingMs;
  final int minProcessingMs;

  @override
  String toString() => '''
MarkerPerformanceStats:
  Total Updates: $totalUpdates
  Avg Processing: ${averageProcessingMs.toStringAsFixed(2)}ms
  Peak Processing: ${peakProcessingMs}ms
  Min Processing: ${minProcessingMs}ms
  Avg Update Frequency: ${averageUpdateFrequencyMs.toStringAsFixed(0)}ms
  Reuse Rate: ${(averageReuseRate * 100).toStringAsFixed(1)}%
  Total Created: $totalCreated
  Total Reused: $totalReused
  Total Removed: $totalRemoved
''';
}
