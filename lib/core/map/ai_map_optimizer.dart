import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:my_app_gps/core/map/map_perf_monitor.dart';

/// AI-powered map performance optimizer
///
/// Analyzes real-time telemetry from MapPerfMonitor and automatically
/// applies optimization strategies to improve frame rate, zoom smoothness,
/// and rebuild efficiency.
///
/// Features:
/// - Automatic bottleneck detection
/// - Dynamic parameter tuning (prefetch batch size, debounce timers)
/// - Adaptive caching strategies
/// - Self-healing performance issues
/// - Configuration recommendations
///
/// Usage:
/// ```dart
/// final optimizer = AiMapOptimizer(monitor: mapPerfMonitor);
/// optimizer.startAutoOptimization();
/// 
/// // Get recommendations
/// final suggestions = optimizer.getRecommendations();
/// 
/// // Apply optimization
/// optimizer.applyOptimization(suggestions.first);
/// ```

class AiMapOptimizer {
  AiMapOptimizer({
    required this.monitor,
    this.onConfigChange,
  }) {
    _setupListener();
  }

  final MapPerfMonitor monitor;
  final void Function(MapOptimizationConfig)? onConfigChange;

  // Current configuration
  MapOptimizationConfig _config = MapOptimizationConfig.defaults();
  
  // Optimization history
  final List<OptimizationAction> _history = [];
  
  // Auto-optimization state
  bool _autoOptimizing = false;
  Timer? _analysisTimer;
  
  bool _disposed = false;

  /// Get current configuration
  MapOptimizationConfig get config => _config;

  /// Setup listener for monitor changes
  void _setupListener() {
    monitor.addListener(_onMonitorUpdate);
  }

  /// Handle monitor updates
  void _onMonitorUpdate() {
    if (!_autoOptimizing || _disposed) return;
    
    final report = monitor.getPerformanceReport();
    _analyzeAndOptimize(report);
  }

  /// Start automatic optimization
  void startAutoOptimization() {
    if (_autoOptimizing) return;
    
    _autoOptimizing = true;
    
    if (kDebugMode) {
      debugPrint('[AI_OPTIMIZER] 🤖 Auto-optimization started');
    }
    
    // Periodic deep analysis every 30 seconds
    _analysisTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (_disposed) return;
      _performDeepAnalysis();
    });
  }

  /// Stop automatic optimization
  void stopAutoOptimization() {
    _autoOptimizing = false;
    _analysisTimer?.cancel();
    
    if (kDebugMode) {
      debugPrint('[AI_OPTIMIZER] 🤖 Auto-optimization stopped');
    }
  }

  /// Analyze telemetry and apply optimizations
  void _analyzeAndOptimize(MapPerfReport report) {
    final recommendations = _generateRecommendations(report);
    
    if (recommendations.isEmpty) return;
    
    // Auto-apply safe optimizations
    for (final rec in recommendations) {
      if (rec.autoApply) {
        _applyRecommendation(rec);
      }
    }
  }

  /// Generate optimization recommendations
  List<OptimizationRecommendation> _generateRecommendations(
    MapPerfReport report,
  ) {
    final recommendations = <OptimizationRecommendation>[];

    // 1. Zoom performance
    if (report.avgZoomDuration > 500) {
      recommendations.add(
        OptimizationRecommendation(
          type: OptimizationType.zoomDebounce,
          severity: RecommendationSeverity.high,
          message: 'Zoom operations taking ${report.avgZoomDuration}ms (target: <300ms)',
          action: () => _enableZoomDebounce(300),
          autoApply: true,
          expectedImprovement: '40-60% faster zoom response',
        ),
      );
    }

    // 2. Frequent marker rebuilds
    if (report.avgMarkerRebuild > 100) {
      recommendations.add(
        OptimizationRecommendation(
          type: OptimizationType.markerCaching,
          severity: RecommendationSeverity.high,
          message: 'Marker rebuilds taking ${report.avgMarkerRebuild}ms (target: <50ms)',
          action: _enableMarkerBitmapCache,
          autoApply: true,
          expectedImprovement: 'Reduce rebuilds by 70-80%',
        ),
      );
    }

    // 3. Frame drops
    if (report.droppedFrameRate > 0.05) {
      recommendations.add(
        OptimizationRecommendation(
          type: OptimizationType.frameOptimization,
          severity: RecommendationSeverity.critical,
          message: '${(report.droppedFrameRate * 100).toStringAsFixed(1)}% frames dropped (target: <5%)',
          action: _reduceRenderLoad,
          autoApply: true,
          expectedImprovement: 'Restore 60fps smoothness',
        ),
      );
    }

    // 4. Slow tile loads
    if (report.avgTileLoad > 200) {
      recommendations.add(
        OptimizationRecommendation(
          type: OptimizationType.tilePrefetch,
          severity: RecommendationSeverity.medium,
          message: 'Tile loads averaging ${report.avgTileLoad}ms (target: <150ms)',
          action: _adjustTilePrefetch,
          autoApply: true,
          expectedImprovement: '30-40% faster tile loading',
        ),
      );
    }

    // 5. Memory pressure
    if (report.avgMemoryMB > 100) {
      recommendations.add(
        OptimizationRecommendation(
          type: OptimizationType.memoryOptimization,
          severity: RecommendationSeverity.medium,
          message: 'Memory usage at ${report.avgMemoryMB}MB (target: <80MB)',
          action: _reduceCacheSize,
          autoApply: false, // User confirmation needed
          expectedImprovement: 'Reduce memory by 20-30%',
        ),
      );
    }

    // 6. Bottleneck clustering
    final zoomBottlenecks = report.bottlenecks['zoom_slow'] ?? 0;
    if (zoomBottlenecks > 5) {
      recommendations.add(
        OptimizationRecommendation(
          type: OptimizationType.zoomOptimization,
          severity: RecommendationSeverity.high,
          message: '$zoomBottlenecks slow zoom events detected',
          action: _optimizeZoomBehavior,
          autoApply: true,
          expectedImprovement: 'Eliminate zoom stutters',
        ),
      );
    }

    return recommendations;
  }

  /// Get current recommendations
  List<OptimizationRecommendation> getRecommendations() {
    final report = monitor.getPerformanceReport();
    return _generateRecommendations(report);
  }

  /// Apply a recommendation
  void applyRecommendation(OptimizationRecommendation rec) {
    _applyRecommendation(rec);
  }

  /// Internal: Apply recommendation
  void _applyRecommendation(OptimizationRecommendation rec) {
    if (kDebugMode) {
      debugPrint('[AI_OPTIMIZER] 🔧 Applying: ${rec.message}');
    }

    rec.action();

    _history.add(
      OptimizationAction(
        timestamp: DateTime.now(),
        type: rec.type,
        description: rec.message,
        applied: true,
      ),
    );
  }

  /// Perform deep analysis (periodic)
  void _performDeepAnalysis() {
    final report = monitor.getPerformanceReport();
    
    if (kDebugMode) {
      debugPrint('[AI_OPTIMIZER] 📊 Deep Analysis:');
      debugPrint(report.toString());
    }

    // Generate comprehensive report
    final recommendations = _generateRecommendations(report);
    
    if (recommendations.isNotEmpty && kDebugMode) {
      debugPrint('[AI_OPTIMIZER] 💡 ${recommendations.length} recommendations:');
      for (final rec in recommendations) {
        debugPrint('  - [${rec.severity.name.toUpperCase()}] ${rec.message}');
        debugPrint('    Expected: ${rec.expectedImprovement}');
      }
    }
  }

  // === OPTIMIZATION ACTIONS ===

  /// Enable zoom debounce
  void _enableZoomDebounce(int milliseconds) {
    _config = _config.copyWith(
      zoomDebounceDuration: Duration(milliseconds: milliseconds),
    );
    
    if (kDebugMode) {
      debugPrint('[AI_OPTIMIZER] ✅ Enabled zoom debounce: ${milliseconds}ms');
    }
    
    onConfigChange?.call(_config);
  }

  /// Enable marker bitmap caching
  void _enableMarkerBitmapCache() {
    _config = _config.copyWith(
      useMarkerBitmapCache: true,
      markerCacheSize: 100,
    );
    
    if (kDebugMode) {
      debugPrint('[AI_OPTIMIZER] ✅ Enabled marker bitmap cache');
    }
    
    onConfigChange?.call(_config);
  }

  /// Reduce render load (switch to compact markers earlier)
  void _reduceRenderLoad() {
    _config = _config.copyWith(
      compactMarkerZoomThreshold: _config.compactMarkerZoomThreshold + 1,
      maxVisibleMarkers: (_config.maxVisibleMarkers * 0.8).toInt(),
    );
    
    if (kDebugMode) {
      debugPrint('[AI_OPTIMIZER] ✅ Reduced render load: compact threshold +1 zoom');
    }
    
    onConfigChange?.call(_config);
  }

  /// Adjust tile prefetch batch size
  void _adjustTilePrefetch() {
    // Reduce batch size if tiles are loading slowly
    final newBatchSize = (_config.tilePrefetchBatch * 0.5).toInt().clamp(2, 10);
    
    _config = _config.copyWith(
      tilePrefetchBatch: newBatchSize,
    );
    
    if (kDebugMode) {
      debugPrint('[AI_OPTIMIZER] ✅ Adjusted tile prefetch batch: $newBatchSize');
    }
    
    onConfigChange?.call(_config);
  }

  /// Reduce cache sizes
  void _reduceCacheSize() {
    _config = _config.copyWith(
      markerCacheSize: (_config.markerCacheSize * 0.7).toInt(),
      tileCacheSize: (_config.tileCacheSize * 0.7).toInt(),
    );
    
    if (kDebugMode) {
      debugPrint('[AI_OPTIMIZER] ✅ Reduced cache sizes by 30%');
    }
    
    onConfigChange?.call(_config);
  }

  /// Optimize zoom behavior
  void _optimizeZoomBehavior() {
    _config = _config.copyWith(
      zoomDebounceDuration: const Duration(milliseconds: 300),
      zoomAnimationDuration: const Duration(milliseconds: 200),
      disableMarkersWhileZooming: true,
    );
    
    if (kDebugMode) {
      debugPrint('[AI_OPTIMIZER] ✅ Optimized zoom behavior');
    }
    
    onConfigChange?.call(_config);
  }

  /// Get optimization history
  List<OptimizationAction> getHistory() => _history.toList();

  /// Dispose
  void dispose() {
    _disposed = true;
    _analysisTimer?.cancel();
    monitor.removeListener(_onMonitorUpdate);
  }
}

/// Map optimization configuration
class MapOptimizationConfig {
  const MapOptimizationConfig({
    required this.zoomDebounceDuration,
    required this.zoomAnimationDuration,
    required this.tilePrefetchBatch,
    required this.tileCacheSize,
    required this.useMarkerBitmapCache,
    required this.markerCacheSize,
    required this.compactMarkerZoomThreshold,
    required this.maxVisibleMarkers,
    required this.disableMarkersWhileZooming,
  });

  final Duration zoomDebounceDuration;
  final Duration zoomAnimationDuration;
  final int tilePrefetchBatch;
  final int tileCacheSize;
  final bool useMarkerBitmapCache;
  final int markerCacheSize;
  final double compactMarkerZoomThreshold;
  final int maxVisibleMarkers;
  final bool disableMarkersWhileZooming;

  factory MapOptimizationConfig.defaults() {
    return const MapOptimizationConfig(
      zoomDebounceDuration: Duration(milliseconds: 150),
      zoomAnimationDuration: Duration(milliseconds: 300),
      tilePrefetchBatch: 6,
      tileCacheSize: 200,
      useMarkerBitmapCache: false,
      markerCacheSize: 50,
      compactMarkerZoomThreshold: 10,
      maxVisibleMarkers: 100,
      disableMarkersWhileZooming: false,
    );
  }

  MapOptimizationConfig copyWith({
    Duration? zoomDebounceDuration,
    Duration? zoomAnimationDuration,
    int? tilePrefetchBatch,
    int? tileCacheSize,
    bool? useMarkerBitmapCache,
    int? markerCacheSize,
    double? compactMarkerZoomThreshold,
    int? maxVisibleMarkers,
    bool? disableMarkersWhileZooming,
  }) {
    return MapOptimizationConfig(
      zoomDebounceDuration: zoomDebounceDuration ?? this.zoomDebounceDuration,
      zoomAnimationDuration: zoomAnimationDuration ?? this.zoomAnimationDuration,
      tilePrefetchBatch: tilePrefetchBatch ?? this.tilePrefetchBatch,
      tileCacheSize: tileCacheSize ?? this.tileCacheSize,
      useMarkerBitmapCache: useMarkerBitmapCache ?? this.useMarkerBitmapCache,
      markerCacheSize: markerCacheSize ?? this.markerCacheSize,
      compactMarkerZoomThreshold: compactMarkerZoomThreshold ?? this.compactMarkerZoomThreshold,
      maxVisibleMarkers: maxVisibleMarkers ?? this.maxVisibleMarkers,
      disableMarkersWhileZooming: disableMarkersWhileZooming ?? this.disableMarkersWhileZooming,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'zoomDebounce': zoomDebounceDuration.inMilliseconds,
      'zoomAnimation': zoomAnimationDuration.inMilliseconds,
      'tilePrefetchBatch': tilePrefetchBatch,
      'tileCacheSize': tileCacheSize,
      'useMarkerBitmapCache': useMarkerBitmapCache,
      'markerCacheSize': markerCacheSize,
      'compactMarkerZoomThreshold': compactMarkerZoomThreshold,
      'maxVisibleMarkers': maxVisibleMarkers,
      'disableMarkersWhileZooming': disableMarkersWhileZooming,
    };
  }
}

/// Optimization recommendation
class OptimizationRecommendation {
  const OptimizationRecommendation({
    required this.type,
    required this.severity,
    required this.message,
    required this.action,
    required this.autoApply,
    required this.expectedImprovement,
  });

  final OptimizationType type;
  final RecommendationSeverity severity;
  final String message;
  final void Function() action;
  final bool autoApply;
  final String expectedImprovement;
}

/// Optimization types
enum OptimizationType {
  zoomDebounce,
  zoomOptimization,
  markerCaching,
  tilePrefetch,
  frameOptimization,
  memoryOptimization,
}

/// Recommendation severity
enum RecommendationSeverity {
  low,
  medium,
  high,
  critical,
}

/// Applied optimization action
class OptimizationAction {
  OptimizationAction({
    required this.timestamp,
    required this.type,
    required this.description,
    required this.applied,
  });

  final DateTime timestamp;
  final OptimizationType type;
  final String description;
  final bool applied;
}
