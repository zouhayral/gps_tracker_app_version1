/// Debug flags for map-core subsystem
///
/// Enables optional runtime assertions and diagnostics for concurrent safety,
/// memory management, and performance monitoring during development.
///
/// Production builds should keep all flags false for optimal performance.
library;

import 'package:flutter/foundation.dart';

/// Enable concurrent safety diagnostics and runtime assertions
///
/// When true, adds extra checks for:
/// - Race conditions in async operations
/// - Concurrent modifications during iteration
/// - Double notifyListeners() calls
/// - Overlapping camera animations
///
/// Performance impact: ~0.5ms per operation when enabled
/// Only effective in debug mode (automatically disabled in release)
const bool kEnableConcurrentDebug = false;

/// Enable memory leak detection for ValueNotifiers and subscriptions
///
/// When true, tracks allocation/disposal of:
/// - Device notifiers in VehicleDataRepository
/// - StreamSubscriptions and Timers
/// - Marker cache entries
///
/// Performance impact: ~0.2ms per allocation/disposal
const bool kEnableMemoryLeakDebug = false;

/// Enable verbose logging for map operations
///
/// When true, logs detailed information about:
/// - Camera movements and zoom operations
/// - Marker generation and caching
/// - WebSocket message processing
/// - REST fallback triggers
///
/// Performance impact: Minimal (logging is already guarded by kDebugMode)
const bool kEnableVerboseMapLogging = false;

/// Enable performance profiling for critical paths
///
/// When true, adds timing metrics for:
/// - Marker rendering and cache hits/misses
/// - Camera animation frame timing
/// - Repository snapshot updates
/// - LRU eviction operations
///
/// Performance impact: ~0.1ms per operation
const bool kEnableMapPerformanceProfiling = false;

/// Global toggle for FMTC debug overlay (runtime-toggleable)
///
/// Can be toggled at runtime via long-press on map in debug mode.
/// Automatically disabled in release builds.
class MapDebugFlags {
  MapDebugFlags._(); // Private constructor

  /// ValueNotifier for FMTC overlay visibility
  static final ValueNotifier<bool> showFmtcOverlay = ValueNotifier<bool>(false);

  /// Returns true if overlay should be visible
  static bool get isOverlayEnabled => !kReleaseMode && showFmtcOverlay.value;

  /// Toggle the overlay visibility (for tap gesture)
  static void toggleOverlay() {
    if (kReleaseMode) return;
    showFmtcOverlay.value = !showFmtcOverlay.value;
    if (kDebugMode) {
      debugPrint(
        '[MAP_DEBUG] FMTC overlay ${showFmtcOverlay.value ? "enabled" : "disabled"}',
      );
    }
  }

  /// Whether to show snapshot overlay during map loading
  static const bool showSnapshotOverlay = false;

  /// Whether to show rebuild tracking badges
  static const bool showRebuildOverlay = false;

  /// Toggle to enable frame timing summarizer logs
  static const bool enableFrameTiming = false;

  /// Toggle to enable PerformanceMetricsService (FPS/Jank logs, CSV, etc.)
  static const bool enablePerfMetrics = false;

  /// Toggle to use FleetMapTelemetryController (async-first) instead of devicesNotifierProvider
  static const bool useFMTCController = false;

  /// Toggle to show marker performance stats (cache efficiency, processing time)
  static const bool showMarkerPerformance = false;

  /// Toggle to enable tile prefetch and snapshot cache
  static const bool enablePrefetch = false;
}

/// Helper to check if concurrent debug is active
bool get isConcurrentDebugActive => kDebugMode && kEnableConcurrentDebug;

/// Helper to check if memory leak debug is active
bool get isMemoryLeakDebugActive => kDebugMode && kEnableMemoryLeakDebug;

/// Helper to check if verbose logging is active
bool get isVerboseLoggingActive => kDebugMode && kEnableVerboseMapLogging;

/// Helper to check if performance profiling is active
bool get isPerformanceProfilingActive =>
    kDebugMode && kEnableMapPerformanceProfiling;
