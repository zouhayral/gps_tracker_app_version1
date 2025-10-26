/// 🎯 ADAPTIVE RENDER MODE & MAP LOD OPTIMIZATION
/// 
/// Dynamically scales visual/detail cost based on live frame timings.
/// When FPS dips, temporarily:
/// - Reduce marker density (cluster/decimate)
/// - Simplify polylines
/// - Throttle tile/marker refresh cadence
/// - Downscale heavy icon assets
/// Then restore full fidelity when FPS recovers.

import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:my_app_gps/perf/bitmap_pool.dart';
import 'package:my_app_gps/perf/marker_widget_pool.dart';

/// Callback for FPS updates
typedef FpsListener = void Function(double fps);

/// 🎯 Frame Timings → Rolling FPS Monitor
/// 
/// Tracks frame performance over a rolling time window and calculates
/// average FPS based on build + raster durations.
/// 
/// Usage:
/// ```dart
/// final monitor = FpsMonitor(
///   window: const Duration(seconds: 2),
///   onFps: (fps) {
///     debugPrint('Current FPS: $fps');
///   },
/// )..start();
/// ```
class FpsMonitor {
  FpsMonitor({
    this.window = const Duration(seconds: 2),
    this.onFps,
  });

  final Duration window;
  final FpsListener? onFps;

  final _samples = <FrameTiming>[];
  bool _started = false;
  double _lastFps = 60.0;

  /// Start monitoring frame timings
  void start() {
    if (_started) return;
    _started = true;
    SchedulerBinding.instance.addTimingsCallback(_onTimings);
    if (kDebugMode) {
      debugPrint('[FpsMonitor] 🚀 Started monitoring (window: ${window.inSeconds}s)');
    }
  }

  /// Stop monitoring and clear samples
  void stop() {
    if (!_started) return;
    _started = false;
    SchedulerBinding.instance.removeTimingsCallback(_onTimings);
    _samples.clear();
    if (kDebugMode) {
      debugPrint('[FpsMonitor] 🛑 Stopped monitoring');
    }
  }

  void _onTimings(List<FrameTiming> timings) {
    _samples.addAll(timings);

    // Remove samples outside the rolling window
    // Note: FrameTiming doesn't provide absolute timestamps, so we keep a fixed window of samples
    final maxSamples = (window.inSeconds * 60).ceil(); // Assume ~60 FPS max
    if (_samples.length > maxSamples) {
      _samples.removeRange(0, _samples.length - maxSamples);
    }

    if (_samples.isEmpty) return;

    // Calculate average frame duration (build + raster)
    final avgMicros = _samples
            .map((t) =>
                t.buildDuration.inMicroseconds +
                t.rasterDuration.inMicroseconds)
            .fold<int>(0, (a, b) => a + b) /
        _samples.length;

    // Convert to FPS, capped at 120
    final fps = avgMicros <= 0 ? 120.0 : min(120.0, 1e6 / avgMicros);

    // Avoid chatty updates - only notify on significant changes (±2 FPS)
    if ((fps - _lastFps).abs() >= 2.0) {
      _lastFps = fps;
      onFps?.call(fps);
    }
  }

  /// Get current FPS (last calculated value)
  double get currentFps => _lastFps;

  /// Check if monitoring is active
  bool get isActive => _started;
}

// ============================================================================
// 🎯 ADAPTIVE LOD CONTROLLER
// ============================================================================

/// Render quality modes based on frame performance
enum RenderMode {
  /// Full fidelity - unlimited markers, no simplification
  high,

  /// Medium quality - moderate marker cap, light simplification
  medium,

  /// Low quality - aggressive culling, heavy simplification
  low;

  /// User-friendly description
  String get description => switch (this) {
        RenderMode.high => 'High Quality (Full Detail)',
        RenderMode.medium => 'Medium Quality (Balanced)',
        RenderMode.low => 'Low Quality (Performance)',
      };
}

/// Level of Detail (LOD) configuration
/// 
/// Defines thresholds and limits for each render mode transition.
class LodConfig {
  const LodConfig({
    required this.dropFpsLow,
    required this.raiseFpsHigh,
    required this.markerCapLow,
    required this.markerCapMedium,
    required this.polySimplifyLow,
    required this.polySimplifyMedium,
    required this.markerUpdateIntervalLow,
    required this.tileThrottleLowMs,
  });

  /// FPS threshold to drop from Medium/High → Lower quality
  final double dropFpsLow; // e.g., 50

  /// FPS threshold to raise from Low/Medium → Higher quality
  final double raiseFpsHigh; // e.g., 58

  /// Maximum markers on-screen in Low mode
  final int markerCapLow; // e.g., 400

  /// Maximum markers on-screen in Medium mode
  final int markerCapMedium; // e.g., 900

  /// Douglas-Peucker epsilon for polyline simplification in Low mode
  final double polySimplifyLow; // meters or pixels

  /// Douglas-Peucker epsilon for polyline simplification in Medium mode
  final double polySimplifyMedium;

  /// Minimum interval between marker rebuilds in Low mode
  final Duration markerUpdateIntervalLow; // e.g., 120ms

  /// Minimum milliseconds between camera/tile refresh in Low mode
  final int tileThrottleLowMs; // e.g., 150ms

  /// Recommended default configuration for typical devices
  static const LodConfig standard = LodConfig(
    dropFpsLow: 50.0,
    raiseFpsHigh: 58.0,
    markerCapLow: 400,
    markerCapMedium: 900,
    polySimplifyLow: 3.0,
    polySimplifyMedium: 1.5,
    markerUpdateIntervalLow: Duration(milliseconds: 120),
    tileThrottleLowMs: 150,
  );

  /// Aggressive configuration for low-end devices
  static const LodConfig lowEnd = LodConfig(
    dropFpsLow: 45.0,
    raiseFpsHigh: 55.0,
    markerCapLow: 250,
    markerCapMedium: 600,
    polySimplifyLow: 5.0,
    polySimplifyMedium: 2.5,
    markerUpdateIntervalLow: Duration(milliseconds: 200),
    tileThrottleLowMs: 250,
  );

  /// Conservative configuration for high-end devices
  static const LodConfig highEnd = LodConfig(
    dropFpsLow: 55.0,
    raiseFpsHigh: 58.0,
    markerCapLow: 600,
    markerCapMedium: 1200,
    polySimplifyLow: 2.0,
    polySimplifyMedium: 1.0,
    markerUpdateIntervalLow: Duration(milliseconds: 80),
    tileThrottleLowMs: 100,
  );
}

/// 🎯 Adaptive LOD Controller
/// 
/// Dynamically adjusts render quality based on FPS measurements.
/// Implements hysteresis to prevent rapid mode switching.
/// 
/// Usage:
/// ```dart
/// final controller = AdaptiveLodController(LodConfig.standard);
/// 
/// // In FPS callback:
/// controller.updateByFps(currentFps);
/// 
/// // Apply limits:
/// final maxMarkers = controller.markerCap();
/// final simplifyEpsilon = controller.polySimplifyEps();
/// ```
class AdaptiveLodController with ChangeNotifier {
  AdaptiveLodController(this.config);

  final LodConfig config;

  RenderMode _mode = RenderMode.high;
  RenderMode get mode => _mode;

  int _modeChangeCount = 0;
  int get modeChangeCount => _modeChangeCount;

  /// Update render mode based on current FPS
  /// 
  /// Implements hysteresis to prevent thrashing:
  /// - High → Medium requires sustained low FPS
  /// - Medium → Low requires even lower FPS
  /// - Low → Medium requires recovery above raise threshold
  /// - Medium → High requires further recovery
  void updateByFps(double fps) {
    final previousMode = _mode;

    switch (_mode) {
      case RenderMode.high:
        if (fps < config.dropFpsLow) {
          _mode = RenderMode.medium;
        }
        break;

      case RenderMode.medium:
        if (fps < config.dropFpsLow - 5) {
          _mode = RenderMode.low;
        } else if (fps > config.raiseFpsHigh) {
          _mode = RenderMode.high;
        }
        break;

      case RenderMode.low:
        if (fps > config.raiseFpsHigh + 2) {
          _mode = RenderMode.medium;
        }
        break;
    }

    if (_mode != previousMode) {
      _modeChangeCount++;
      if (kDebugMode) {
        debugPrint(
          '[AdaptiveLOD] 🔄 Mode changed: ${previousMode.name} → ${_mode.name} '
          '(FPS: ${fps.toStringAsFixed(1)})',
        );
      }
      
      // Reconfigure pools for new mode
      configurePools();
      
      notifyListeners();
    }
  }

  /// Get maximum marker count for current mode
  int markerCap() => switch (_mode) {
        RenderMode.high => 1 << 31, // practically unlimited (2.1 billion)
        RenderMode.medium => config.markerCapMedium,
        RenderMode.low => config.markerCapLow,
      };

  /// Get polyline simplification epsilon for current mode
  double polySimplifyEps() => switch (_mode) {
        RenderMode.high => 0.0, // no simplification
        RenderMode.medium => config.polySimplifyMedium,
        RenderMode.low => config.polySimplifyLow,
      };

  /// Get marker update interval for current mode
  Duration markerUpdateInterval() => switch (_mode) {
        RenderMode.high => Duration.zero, // no throttling
        RenderMode.medium => const Duration(milliseconds: 16), // 60 FPS
        RenderMode.low => config.markerUpdateIntervalLow,
      };

  /// Get tile/camera refresh throttle in milliseconds
  int tileThrottleMs() => switch (_mode) {
        RenderMode.high => 0, // no throttling
        RenderMode.medium => 30, // ~33 FPS
        RenderMode.low => config.tileThrottleLowMs,
      };

  /// Configure pooling systems based on current LOD mode
  void configurePools() {
    // Configure marker widget pool based on mode
    final maxMarkersPerTier = switch (_mode) {
      RenderMode.high => 500,   // Allow more pooled widgets in high mode
      RenderMode.medium => 300, // Standard pool size
      RenderMode.low => 150,    // Reduce pool to save memory
    };
    MarkerPoolManager.configure(maxPerTier: maxMarkersPerTier);

    // Configure bitmap pool based on mode
    final bitmapPoolConfig = switch (_mode) {
      RenderMode.high => (maxEntries: 100, maxSizeBytes: 30 * 1024 * 1024), // 30 MB
      RenderMode.medium => (maxEntries: 50, maxSizeBytes: 20 * 1024 * 1024), // 20 MB
      RenderMode.low => (maxEntries: 30, maxSizeBytes: 10 * 1024 * 1024),    // 10 MB
    };
    BitmapPoolManager.configure(
      maxEntries: bitmapPoolConfig.maxEntries,
      maxSizeBytes: bitmapPoolConfig.maxSizeBytes,
    );

    if (kDebugMode) {
      debugPrint(
        '[AdaptiveLOD] ⚙️ Configured pools for ${_mode.name} mode: '
        'markers=$maxMarkersPerTier/tier, bitmaps=${bitmapPoolConfig.maxEntries} entries',
      );
    }
  }

  /// Check if in performance mode (Medium or Low)
  bool get isPerformanceMode =>
      _mode == RenderMode.medium || _mode == RenderMode.low;

  /// Check if in aggressive performance mode (Low)
  bool get isAggressiveMode => _mode == RenderMode.low;

  /// Force a specific render mode (for testing/debugging)
  void forceMode(RenderMode mode) {
    if (_mode != mode) {
      final previousMode = _mode;
      _mode = mode;
      _modeChangeCount++;
      if (kDebugMode) {
        debugPrint(
          '[AdaptiveLOD] 🔧 Forced mode: ${previousMode.name} → ${_mode.name}',
        );
      }
      
      // Reconfigure pools for new mode
      configurePools();
      
      notifyListeners();
    }
  }

  /// Reset to high quality mode
  void reset() {
    forceMode(RenderMode.high);
  }
}

// ============================================================================
// 🎯 FPS-AWARE VALUE NOTIFIER
// ============================================================================

/// ValueNotifier that tracks FPS alongside the value
/// Useful for UI overlays showing both data and performance
class FpsAwareNotifier<T> extends ValueNotifier<T> {
  FpsAwareNotifier(super.value);

  double _fps = 60.0;
  double get fps => _fps;

  void updateWithFps(T newValue, double newFps) {
    value = newValue;
    _fps = newFps;
  }
}
