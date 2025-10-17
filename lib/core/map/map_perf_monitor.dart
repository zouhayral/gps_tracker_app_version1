import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart';

/// Real-time performance monitoring for map operations
///
/// Tracks zoom gestures, rebuilds, tile loads, and marker rendering
/// to feed telemetry data to the AI optimization agent.
///
/// Features:
/// - Frame time tracking (detect 16ms budget violations)
/// - Zoom gesture duration monitoring
/// - Rebuild frequency detection
/// - Memory pressure tracking
/// - Automated bottleneck identification
///
/// Usage:
/// ```dart
/// final monitor = MapPerfMonitor();
/// 
/// // Track zoom
/// monitor.onZoomStart(12.0);
/// await doZoomOperation();
/// monitor.onZoomEnd(14.0);
/// 
/// // Track rebuilds
/// monitor.onRebuild('markers', Duration(milliseconds: 45));
/// 
/// // Get analysis
/// final report = monitor.getPerformanceReport();
/// ```

class MapPerfMonitor with ChangeNotifier {
  MapPerfMonitor() {
    _startPeriodicAnalysis();
  }

  // Zoom tracking
  final Stopwatch _zoomStopwatch = Stopwatch();
  double _lastZoom = 0;
  int _zoomEventCount = 0;
  final List<int> _zoomDurations = [];

  // Rebuild tracking
  final Map<String, List<int>> _rebuildTimes = {
    'markers': [],
    'tiles': [],
    'camera': [],
    'ui': [],
  };
  
  // Frame tracking
  final List<int> _frameTimes = [];
  int _droppedFrames = 0;
  static const int _targetFrameTime = 16; // 60fps = 16.67ms

  // Tile tracking
  int _tilesLoaded = 0;
  final List<int> _tileLoadDurations = [];

  // Memory tracking
  final List<double> _memorySnapshots = [];
  
  // Bottleneck detection
  final Map<String, int> _bottlenecks = {};
  
  // Performance history (last 60 seconds)
  final Queue<MapPerfSnapshot> _history = Queue();
  static const int _maxHistorySize = 60;
  
  Timer? _analysisTimer;
  
  bool _disposed = false;

  /// Track zoom gesture start
  void onZoomStart(double zoom) {
    _lastZoom = zoom;
    _zoomStopwatch.reset();
    _zoomStopwatch.start();
  }

  /// Track zoom gesture end
  void onZoomEnd(double zoom) {
    if (!_zoomStopwatch.isRunning) return;
    
    _zoomStopwatch.stop();
    final zoomDuration = _zoomStopwatch.elapsedMilliseconds;
    _zoomDurations.add(zoomDuration);
    _zoomEventCount++;
    
    if (kDebugMode) {
      debugPrint(
        '[AI_AGENT] Zoom ${_lastZoom.toStringAsFixed(1)} → '
        '${zoom.toStringAsFixed(1)} took ${zoomDuration}ms',
      );
    }
    
    // Detect bottleneck
    if (zoomDuration > 500) {
      _recordBottleneck('zoom_slow', zoomDuration);
    }
    
    _zoomStopwatch.reset();
    notifyListeners();
  }

  /// Track layer rebuild duration
  void onRebuild(String layer, Duration duration) {
    final ms = duration.inMilliseconds;
    
    if (_rebuildTimes.containsKey(layer)) {
      _rebuildTimes[layer]!.add(ms);
      
      // Keep only last 100 samples per layer
      if (_rebuildTimes[layer]!.length > 100) {
        _rebuildTimes[layer]!.removeAt(0);
      }
    }
    
    if (kDebugMode) {
      debugPrint('[AI_AGENT] $layer rebuilt in ${ms}ms');
    }
    
    // Detect frequent rebuilds (>3 per second = bottleneck)
    if (_rebuildTimes[layer]!.length > 3) {
      final recent = _rebuildTimes[layer]!.skip(
        _rebuildTimes[layer]!.length - 3,
      );
      final totalTime = recent.reduce((a, b) => a + b);
      if (totalTime < 1000) {
        _recordBottleneck('rebuild_frequent_$layer', totalTime);
      }
    }
    
    // Detect slow rebuilds
    if (ms > 100) {
      _recordBottleneck('rebuild_slow_$layer', ms);
    }
    
    notifyListeners();
  }

  /// Track frame render time
  void onFrame(Duration frameTime) {
    final ms = frameTime.inMilliseconds;
    _frameTimes.add(ms);
    
    // Keep only last 100 frames
    if (_frameTimes.length > 100) {
      _frameTimes.removeAt(0);
    }
    
    // Count dropped frames (>16ms = dropped)
    if (ms > _targetFrameTime) {
      _droppedFrames++;
      _recordBottleneck('frame_drop', ms);
    }
  }

  /// Track tile load completion
  void onTileLoaded(Duration loadTime) {
    _tilesLoaded++;
    final ms = loadTime.inMilliseconds;
    _tileLoadDurations.add(ms);
    
    // Keep only last 100 samples
    if (_tileLoadDurations.length > 100) {
      _tileLoadDurations.removeAt(0);
    }
    
    // Detect slow tile loads
    if (ms > 200) {
      _recordBottleneck('tile_slow', ms);
    }
  }

  /// Track memory usage (in MB)
  void onMemorySnapshot(double memoryMB) {
    _memorySnapshots.add(memoryMB);
    
    // Keep only last 60 snapshots
    if (_memorySnapshots.length > 60) {
      _memorySnapshots.removeAt(0);
    }
    
    // Detect memory pressure (>100MB)
    if (memoryMB > 100) {
      _recordBottleneck('memory_high', memoryMB.toInt());
    }
  }

  /// Record a bottleneck occurrence
  void _recordBottleneck(String type, int value) {
    _bottlenecks[type] = (_bottlenecks[type] ?? 0) + 1;
    
    if (kDebugMode && _bottlenecks[type]! >= 3) {
      debugPrint('[AI_AGENT] ⚠️  Bottleneck detected: $type (${_bottlenecks[type]} occurrences)');
    }
  }

  /// Get comprehensive performance report
  MapPerfReport getPerformanceReport() {
    return MapPerfReport(
      // Zoom metrics
      avgZoomDuration: _average(_zoomDurations),
      maxZoomDuration: _max(_zoomDurations),
      zoomEventCount: _zoomEventCount,
      
      // Rebuild metrics
      avgMarkerRebuild: _average(_rebuildTimes['markers']!),
      avgTileRebuild: _average(_rebuildTimes['tiles']!),
      avgCameraRebuild: _average(_rebuildTimes['camera']!),
      
      // Frame metrics
      avgFrameTime: _average(_frameTimes),
      maxFrameTime: _max(_frameTimes),
      droppedFrames: _droppedFrames,
      droppedFrameRate: _frameTimes.isEmpty 
          ? 0.0 
          : _droppedFrames / _frameTimes.length,
      
      // Tile metrics
      avgTileLoad: _average(_tileLoadDurations),
      maxTileLoad: _max(_tileLoadDurations),
      tilesLoaded: _tilesLoaded,
      
      // Memory metrics
      avgMemoryMB: _average(_memorySnapshots.map((e) => e.toInt()).toList()),
      maxMemoryMB: _max(_memorySnapshots.map((e) => e.toInt()).toList()).toDouble(),
      
      // Bottlenecks
      bottlenecks: Map.from(_bottlenecks),
      
      // Overall health score (0-100)
      healthScore: _calculateHealthScore(),
    );
  }

  /// Calculate overall health score (0-100)
  int _calculateHealthScore() {
    var score = 100;
    
    // Deduct for slow zooms (>300ms)
    final avgZoom = _average(_zoomDurations);
    if (avgZoom > 300) score -= 20;
    else if (avgZoom > 500) score -= 40;
    
    // Deduct for dropped frames (>5%)
    final dropRate = _frameTimes.isEmpty 
        ? 0.0 
        : _droppedFrames / _frameTimes.length;
    if (dropRate > 0.05) score -= 15;
    else if (dropRate > 0.10) score -= 30;
    
    // Deduct for slow rebuilds (>50ms)
    final avgRebuild = _average(_rebuildTimes['markers']!);
    if (avgRebuild > 50) score -= 10;
    else if (avgRebuild > 100) score -= 25;
    
    // Deduct for bottlenecks
    final totalBottlenecks = _bottlenecks.values.fold(0, (a, b) => a + b);
    if (totalBottlenecks > 10) score -= 20;
    else if (totalBottlenecks > 5) score -= 10;
    
    return score.clamp(0, 100);
  }

  /// Start periodic analysis (every 10 seconds)
  void _startPeriodicAnalysis() {
    _analysisTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      if (_disposed) return;
      
      final snapshot = MapPerfSnapshot(
        timestamp: DateTime.now(),
        report: getPerformanceReport(),
      );
      
      _history.add(snapshot);
      
      // Keep only last 60 seconds
      while (_history.length > _maxHistorySize) {
        _history.removeFirst();
      }
      
      // Notify listeners for AI agent
      notifyListeners();
    });
  }

  /// Get performance history
  List<MapPerfSnapshot> getHistory() => _history.toList();

  /// Reset all metrics
  void reset() {
    _zoomDurations.clear();
    _zoomEventCount = 0;
    _rebuildTimes.forEach((_, list) => list.clear());
    _frameTimes.clear();
    _droppedFrames = 0;
    _tileLoadDurations.clear();
    _tilesLoaded = 0;
    _memorySnapshots.clear();
    _bottlenecks.clear();
    _history.clear();
    notifyListeners();
  }

  /// Helper: Calculate average
  int _average(List<int> values) {
    if (values.isEmpty) return 0;
    return values.reduce((a, b) => a + b) ~/ values.length;
  }

  /// Helper: Get maximum
  int _max(List<int> values) {
    if (values.isEmpty) return 0;
    return values.reduce((a, b) => a > b ? a : b);
  }

  @override
  void dispose() {
    _disposed = true;
    _analysisTimer?.cancel();
    super.dispose();
  }
}

/// Performance report snapshot
class MapPerfReport {
  MapPerfReport({
    required this.avgZoomDuration,
    required this.maxZoomDuration,
    required this.zoomEventCount,
    required this.avgMarkerRebuild,
    required this.avgTileRebuild,
    required this.avgCameraRebuild,
    required this.avgFrameTime,
    required this.maxFrameTime,
    required this.droppedFrames,
    required this.droppedFrameRate,
    required this.avgTileLoad,
    required this.maxTileLoad,
    required this.tilesLoaded,
    required this.avgMemoryMB,
    required this.maxMemoryMB,
    required this.bottlenecks,
    required this.healthScore,
  });

  final int avgZoomDuration;
  final int maxZoomDuration;
  final int zoomEventCount;
  
  final int avgMarkerRebuild;
  final int avgTileRebuild;
  final int avgCameraRebuild;
  
  final int avgFrameTime;
  final int maxFrameTime;
  final int droppedFrames;
  final double droppedFrameRate;
  
  final int avgTileLoad;
  final int maxTileLoad;
  final int tilesLoaded;
  
  final int avgMemoryMB;
  final double maxMemoryMB;
  
  final Map<String, int> bottlenecks;
  final int healthScore;

  @override
  String toString() {
    return '''
MapPerfReport:
  Health Score: $healthScore/100
  Zoom: avg=${avgZoomDuration}ms max=${maxZoomDuration}ms count=$zoomEventCount
  Rebuilds: markers=${avgMarkerRebuild}ms tiles=${avgTileRebuild}ms camera=${avgCameraRebuild}ms
  Frames: avg=${avgFrameTime}ms max=${maxFrameTime}ms dropped=$droppedFrames (${(droppedFrameRate * 100).toStringAsFixed(1)}%)
  Tiles: avg=${avgTileLoad}ms max=${maxTileLoad}ms loaded=$tilesLoaded
  Memory: avg=${avgMemoryMB}MB max=${maxMemoryMB.toStringAsFixed(1)}MB
  Bottlenecks: ${bottlenecks.entries.map((e) => '${e.key}=${e.value}').join(', ')}
''';
  }

  /// Convert to JSON for AI agent
  Map<String, dynamic> toJson() {
    return {
      'healthScore': healthScore,
      'zoom': {
        'avgDuration': avgZoomDuration,
        'maxDuration': maxZoomDuration,
        'eventCount': zoomEventCount,
      },
      'rebuilds': {
        'markers': avgMarkerRebuild,
        'tiles': avgTileRebuild,
        'camera': avgCameraRebuild,
      },
      'frames': {
        'avgTime': avgFrameTime,
        'maxTime': maxFrameTime,
        'dropped': droppedFrames,
        'dropRate': droppedFrameRate,
      },
      'tiles': {
        'avgLoad': avgTileLoad,
        'maxLoad': maxTileLoad,
        'loaded': tilesLoaded,
      },
      'memory': {
        'avg': avgMemoryMB,
        'max': maxMemoryMB,
      },
      'bottlenecks': bottlenecks,
    };
  }
}

/// Performance snapshot with timestamp
class MapPerfSnapshot {
  MapPerfSnapshot({
    required this.timestamp,
    required this.report,
  });

  final DateTime timestamp;
  final MapPerfReport report;
}
