import 'package:flutter/material.dart';
import 'package:flutter/widgets.dart';

/// Rebuild tracking for performance validation
/// 
/// Tracks widget rebuild counts to verify optimization effectiveness.
/// 
/// Usage:
/// ```dart
/// @override
/// Widget build(BuildContext context) {
///   RebuildTracker.instance.trackRebuild('MapPage');
///   return Scaffold(...);
/// }
/// ```
class RebuildTracker {
  RebuildTracker._();
  
  static final instance = RebuildTracker._();
  
  final Map<String, int> _rebuildCounts = {};
  final Map<String, DateTime> _lastRebuild = {};
  DateTime? _trackingStartTime;
  bool _isTracking = false;
  
  /// Start tracking rebuilds
  void start() {
    if (_isTracking) {
      debugPrint('[RebuildTracker] Already tracking');
      return;
    }
    
    _isTracking = true;
    _rebuildCounts.clear();
    _lastRebuild.clear();
    _trackingStartTime = DateTime.now();
    debugPrint('[RebuildTracker] ✅ Started tracking rebuilds');
  }
  
  /// Stop tracking rebuilds
  void stop() {
    if (!_isTracking) {
      debugPrint('[RebuildTracker] Not tracking');
      return;
    }
    
    _isTracking = false;
    debugPrint('[RebuildTracker] ⏹️  Stopped tracking');
  }
  
  /// Track a widget rebuild
  void trackRebuild(String widgetName) {
    if (!_isTracking) return;
    
    _rebuildCounts[widgetName] = (_rebuildCounts[widgetName] ?? 0) + 1;
    _lastRebuild[widgetName] = DateTime.now();
  }
  
  /// Get rebuild count for a widget
  int getCount(String widgetName) {
    return _rebuildCounts[widgetName] ?? 0;
  }
  
  /// Get all rebuild counts
  Map<String, int> getAllCounts() {
    return Map.unmodifiable(_rebuildCounts);
  }
  
  /// Print rebuild summary
  void printSummary() {
    if (_rebuildCounts.isEmpty) {
      debugPrint('[RebuildTracker] No rebuilds tracked');
      return;
    }
    
    final elapsed = _trackingStartTime != null
        ? DateTime.now().difference(_trackingStartTime!).inSeconds
        : 0;
    
    debugPrint('');
    debugPrint('╔═══════════════════════════════════════════════════════════╗');
    debugPrint('║           REBUILD TRACKER SUMMARY                         ║');
    debugPrint('╠═══════════════════════════════════════════════════════════╣');
    debugPrint('║ Tracking Duration: ${elapsed}s');
    debugPrint('╠═══════════════════════════════════════════════════════════╣');
    
    // Sort by rebuild count (descending)
    final sorted = _rebuildCounts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    
    for (final entry in sorted) {
      final count = entry.value;
      final rate = elapsed > 0 ? (count / elapsed).toStringAsFixed(1) : '0.0';
      final padding = ' ' * (35 - entry.key.length);
      debugPrint('║ ${entry.key}$padding $count rebuilds ($rate/s)');
    }
    
    debugPrint('╚═══════════════════════════════════════════════════════════╝');
    debugPrint('');
  }
  
  /// Print compact one-line summary
  void printCompact() {
    if (_rebuildCounts.isEmpty) {
      debugPrint('[RebuildTracker] No rebuilds');
      return;
    }
    
    final total = _rebuildCounts.values.reduce((a, b) => a + b);
    final widgetCount = _rebuildCounts.length;
    debugPrint('[RebuildTracker] Total: $total rebuilds across $widgetCount widgets');
  }
  
  /// Reset tracking data
  void reset() {
    _rebuildCounts.clear();
    _lastRebuild.clear();
    _trackingStartTime = null;
    debugPrint('[RebuildTracker] Reset');
  }
  
  /// Check if a widget is rebuilding too frequently
  bool isRebuildingTooOften(String widgetName, {int threshold = 10}) {
    final count = getCount(widgetName);
    final lastTime = _lastRebuild[widgetName];
    
    if (lastTime == null || _trackingStartTime == null) return false;
    
    final elapsed = lastTime.difference(_trackingStartTime!).inSeconds;
    if (elapsed < 1) return false; // Too early to tell
    
    final rate = count / elapsed;
    return rate > threshold;
  }
}

/// Widget wrapper that automatically tracks rebuilds
/// 
/// Usage:
/// ```dart
/// class MyWidget extends StatelessWidget {
///   @override
///   Widget build(BuildContext context) {
///     return TrackedWidget(
///       name: 'MyWidget',
///       child: Container(...),
///     );
///   }
/// }
/// ```
class TrackedWidget extends StatelessWidget {
  const TrackedWidget({
    required this.name,
    required this.child,
    Key? key,
  }) : super(key: key);

  final String name;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    RebuildTracker.instance.trackRebuild(name);
    return child;
  }
}

/// Global flag to enable rebuild logging
/// 
/// Set to true in development builds to see widget rebuild logs
bool debugPrintRebuildDirtyWidgets = false;

/// Enable detailed rebuild logging
void enableRebuildLogging() {
  debugPrintRebuildDirtyWidgets = true;
  debugPrint('[RebuildTracker] ✅ Rebuild logging enabled');
  debugPrint('[RebuildTracker] Set debugPrintRebuildDirtyWidgets = true');
}

/// Disable rebuild logging
void disableRebuildLogging() {
  debugPrintRebuildDirtyWidgets = false;
  debugPrint('[RebuildTracker] Rebuild logging disabled');
}
