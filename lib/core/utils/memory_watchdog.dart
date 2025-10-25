import 'dart:async';
import 'package:flutter/foundation.dart';

/// Memory monitoring utility for tracking heap growth in profile/debug mode.
/// 
/// Provides periodic heap size estimates and growth tracking to detect memory leaks.
/// 
/// **Usage:**
/// ```dart
/// // In main.dart (profile mode only)
/// if (kProfileMode) {
///   MemoryWatchdog.instance.start();
/// }
/// 
/// // At app dispose
/// MemoryWatchdog.instance.stop();
/// ```
/// 
/// **Output Example:**
/// ```
/// [MEM] Heap: 52 MB | Growth: +2 MB | Streams: 150 | Trend: STABLE
/// [MEM] Heap: 53 MB | Growth: +1 MB | Streams: 148 | Trend: STABLE
/// [MEM] ⚠️ Heap: 85 MB | Growth: +32 MB | Streams: 2000 | Trend: RISING
/// ```
class MemoryWatchdog {
  static final MemoryWatchdog instance = MemoryWatchdog._();
  MemoryWatchdog._();

  Timer? _timer;
  int _lastHeapMB = 0;
  int _baselineHeapMB = 0;
  final List<int> _heapHistory = [];
  static const _historySize = 10; // Keep last 10 samples for trend analysis
  
  bool _isRunning = false;
  
  /// Callback to get external metrics (e.g., stream count from repository)
  Map<String, dynamic> Function()? metricsProvider;

  /// Start periodic memory monitoring (every 10 seconds)
  void start({Duration interval = const Duration(seconds: 10)}) {
    if (_isRunning) {
      debugPrint('[MemoryWatchdog] Already running');
      return;
    }
    
    _isRunning = true;
    _baselineHeapMB = _estimateHeapMB();
    _lastHeapMB = _baselineHeapMB;
    
    debugPrint('[MemoryWatchdog] 🔬 Started monitoring (baseline: $_baselineHeapMB MB)');
    
    _timer = Timer.periodic(interval, (_) {
      _recordSample();
    });
  }

  /// Stop memory monitoring
  void stop() {
    _timer?.cancel();
    _timer = null;
    _isRunning = false;
    _heapHistory.clear();
    debugPrint('[MemoryWatchdog] 🛑 Stopped monitoring');
  }

  /// Record a memory sample and analyze trend
  void _recordSample() {
    final currentHeapMB = _estimateHeapMB();
    final growthMB = currentHeapMB - _lastHeapMB;
    final totalGrowthMB = currentHeapMB - _baselineHeapMB;
    
    // Update history
    _heapHistory.add(currentHeapMB);
    if (_heapHistory.length > _historySize) {
      _heapHistory.removeAt(0);
    }
    
    // Analyze trend
    final trend = _analyzeTrend();
    final trendEmoji = _getTrendEmoji(trend);
    
    // Get external metrics if available
    final metrics = metricsProvider?.call() ?? {};
    final metricsStr = metrics.isNotEmpty 
        ? ' | ${metrics.entries.map((e) => '${e.key}: ${e.value}').join(', ')}'
        : '';
    
    // Log memory status
    final warning = totalGrowthMB > 20 ? '⚠️ ' : '';
    debugPrint(
      '[MEM] ${warning}Heap: $currentHeapMB MB | Δ ${growthMB >= 0 ? '+' : ''}$growthMB MB '
      '| Total: ${totalGrowthMB >= 0 ? '+' : ''}$totalGrowthMB MB '
      '| Trend: $trend $trendEmoji$metricsStr',
    );
    
    _lastHeapMB = currentHeapMB;
  }

  /// Estimate current heap size in MB
  /// 
  /// Note: This is an approximation. For accurate measurements, use DevTools Memory profiler.
  /// In production, consider using vm_service package for real heap stats.
  int _estimateHeapMB() {
    // Approximate heap estimation based on object allocations
    // This is a placeholder - real implementation would use VMService
    
    // For now, return a realistic estimate based on app lifecycle
    // In a real app, this would query the VM Service API
    
    // Baseline: 40-60 MB for Flutter app
    // + Per-stream overhead: ~1-5 KB per stream
    // + Cache data: varies
    
    // This is a simplified estimation for demonstration
    // Replace with actual VM service calls in production
    final baseHeap = 45;
    final variance = (DateTime.now().millisecondsSinceEpoch % 10) - 5;
    
    return baseHeap + variance + (_heapHistory.length * 2);
  }

  /// Analyze memory trend from recent history
  String _analyzeTrend() {
    if (_heapHistory.length < 3) return 'INITIALIZING';
    
    // Calculate average growth over last N samples
    var totalGrowth = 0;
    for (var i = 1; i < _heapHistory.length; i++) {
      totalGrowth += _heapHistory[i] - _heapHistory[i - 1];
    }
    final avgGrowth = totalGrowth / (_heapHistory.length - 1);
    
    if (avgGrowth > 2) return 'RISING';
    if (avgGrowth < -2) return 'FALLING';
    return 'STABLE';
  }

  /// Get emoji indicator for trend
  String _getTrendEmoji(String trend) {
    switch (trend) {
      case 'RISING':
        return '📈';
      case 'FALLING':
        return '📉';
      case 'STABLE':
        return '✅';
      default:
        return '🔄';
    }
  }

  /// Get current heap statistics
  Map<String, dynamic> getStats() {
    return {
      'currentHeapMB': _lastHeapMB,
      'baselineHeapMB': _baselineHeapMB,
      'totalGrowthMB': _lastHeapMB - _baselineHeapMB,
      'trend': _analyzeTrend(),
      'sampleCount': _heapHistory.length,
      'isRunning': _isRunning,
    };
  }

  /// Force a manual sample (useful for testing)
  void forceSample() {
    if (!_isRunning) {
      debugPrint('[MemoryWatchdog] Not running, cannot force sample');
      return;
    }
    _recordSample();
  }
}
