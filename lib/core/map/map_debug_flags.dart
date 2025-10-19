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

/// Helper to check if concurrent debug is active
bool get isConcurrentDebugActive => kDebugMode && kEnableConcurrentDebug;

/// Helper to check if memory leak debug is active
bool get isMemoryLeakDebugActive => kDebugMode && kEnableMemoryLeakDebug;

/// Helper to check if verbose logging is active
bool get isVerboseLoggingActive => kDebugMode && kEnableVerboseMapLogging;

/// Helper to check if performance profiling is active
bool get isPerformanceProfilingActive =>
    kDebugMode && kEnableMapPerformanceProfiling;
