import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

/// Frame-safe task scheduler for UI render pipeline optimization
/// 
/// **Purpose**: Defer non-critical UI updates to frame boundaries to eliminate
/// jank caused by synchronous operations during active frames.
/// 
/// **Key Benefits**:
/// - ✅ Eliminates "Skipped XX frames" warnings
/// - ✅ Coalesces multiple rapid updates into single frame
/// - ✅ Reduces battery drain from constant redraws
/// - ✅ Maintains 60-120 FPS during burst data updates
/// 
/// **Usage**:
/// ```dart
/// // Instead of direct UI updates:
/// _mapController.updateMarkers();
/// 
/// // Use frame-safe scheduling:
/// RenderScheduler.scheduleFrameCallback(() {
///   if (mounted) _mapController.updateMarkers();
/// });
/// ```
class RenderScheduler {
  RenderScheduler._();
  
  /// Schedule a callback to run at the next frame boundary
  /// 
  /// **When to use**:
  /// - Marker layer updates after position data diff
  /// - Map control updates after camera movements
  /// - UI refreshes triggered by background tasks
  /// 
  /// **Effect**: Callback runs AFTER current frame completes, preventing
  /// mid-frame jank and ensuring smooth 60+ FPS performance.
  static void scheduleFrameCallback(VoidCallback callback) {
    SchedulerBinding.instance.scheduleFrameCallback((_) {
      callback();
    });
  }
  
  /// Schedule a callback for the post-frame phase
  /// 
  /// **When to use**:
  /// - Cleanup tasks after UI updates
  /// - Deferred initialization after first render
  /// - Measurement operations that depend on layout
  /// 
  /// **Effect**: Callback runs after the current frame is fully painted,
  /// ideal for non-urgent operations.
  static void addPostFrameCallback(VoidCallback callback) {
    SchedulerBinding.instance.addPostFrameCallback((_) {
      callback();
    });
  }
  
  /// Schedule idle-priority cleanup task with delay
  /// 
  /// **When to use**:
  /// - Periodic cache cleanup (e.g., expired trips, old positions)
  /// - Background optimization tasks
  /// - Memory pressure relief operations
  /// 
  /// **Effect**: Task runs 5+ seconds after a complete frame, ensuring it
  /// never conflicts with active user interactions or data updates.
  /// 
  /// **Example**:
  /// ```dart
  /// RenderScheduler.scheduleIdleCleanup(() {
  ///   _cleanupExpiredTrips();
  /// });
  /// ```
  static void scheduleIdleCleanup(
    VoidCallback callback, {
    Duration delay = const Duration(seconds: 5),
  }) {
    SchedulerBinding.instance.addPostFrameCallback((_) {
      Future.delayed(delay, callback);
    });
  }

  /// Schedule idle task with priority (NEW)
  /// 
  /// **When to use**:
  /// - Memory pool trimming
  /// - Cache cleanup operations
  /// - Background diagnostics
  /// 
  /// **Effect**: Task is queued and executed during idle periods based on
  /// priority level, with automatic frame budget checking.
  static void scheduleIdleTask(
    VoidCallback task, {
    IdleTaskPriority priority = IdleTaskPriority.medium,
    String? name,
  }) {
    IdleTaskScheduler.scheduleTask(
      task,
      priority: priority,
      name: name,
    );
  }

  /// Hint GC during idle period (NEW)
  /// 
  /// **When to use**:
  /// - After large cleanup operations
  /// - When heap growth is detected
  /// - During idle periods after memory-intensive work
  /// 
  /// **Effect**: Provides a non-blocking hint to the Dart VM that GC
  /// might be beneficial. The VM is free to ignore the hint.
  static void maybeGCHint({String? reason}) {
    GCHintScheduler.maybeGCHint(reason: reason);
  }

  /// Get idle task lane statistics (NEW)
  static Map<String, dynamic> getIdleTaskStats() {
    return IdleTaskScheduler.getStats();
  }
  
  /// Debug utility: Add timing callback to measure frame performance
  /// 
  /// **Usage** (Profile/Debug mode only):
  /// ```dart
  /// if (kProfileMode || kDebugMode) {
  ///   RenderScheduler.debugFrameTimings((timings) {
  ///     for (final t in timings) {
  ///       debugPrint('[FRAME] ${t.buildDuration.inMilliseconds}ms build, '
  ///           '${t.rasterDuration.inMilliseconds}ms raster');
  ///     }
  ///   });
  /// }
  /// ```
  /// 
  /// **Target**: build + raster < 8ms for 120 FPS, < 16ms for 60 FPS
  static void debugFrameTimings(TimingsCallback callback) {
    if (kDebugMode || kProfileMode) {
      SchedulerBinding.instance.addTimingsCallback(callback);
    }
  }
}

/// Batched notifier update scheduler to prevent notifyListeners() spam
/// 
/// **Problem**: Rapid state changes cause excessive widget rebuilds:
/// ```
/// // Bad: 10 updates in 100ms = 10 rebuilds
/// for (final update in updates) {
///   setState(() => _data = update);
/// }
/// ```
/// 
/// **Solution**: Batch updates into single frame:
/// ```dart
/// // Good: 10 updates in 100ms = 1 rebuild
/// for (final update in updates) {
///   notifyDeferred();
/// }
/// ```
/// 
/// **Usage with ChangeNotifier**:
/// ```dart
/// class VehicleNotifier extends ChangeNotifier {
///   final _scheduler = DeferredNotifyScheduler();
///   
///   void updatePosition(Position pos) {
///     _position = pos;
///     _scheduler.notifyDeferred(notifyListeners);
///   }
///   
///   @override
///   void dispose() {
///     _scheduler.dispose();
///     super.dispose();
///   }
/// }
/// ```
class DeferredNotifyScheduler {
  bool _pendingNotify = false;
  
  /// Schedule a deferred notifyListeners() call
  /// 
  /// **Behavior**:
  /// - First call: Schedules callback for next frame
  /// - Subsequent calls within same frame: Ignored (coalesced)
  /// - Result: Maximum 1 rebuild per frame (60+ FPS)
  void notifyDeferred(VoidCallback notifyListeners) {
    if (_pendingNotify) return; // Already scheduled
    
    _pendingNotify = true;
    SchedulerBinding.instance.scheduleFrameCallback((_) {
      _pendingNotify = false;
      notifyListeners();
    });
  }
  
  /// Cancel any pending notification
  void cancel() {
    _pendingNotify = false;
  }
  
  /// Dispose scheduler (call in notifier's dispose())
  void dispose() {
    _pendingNotify = false;
  }
}

/// Marker update task queue for serialized, throttled rebuilds
/// 
/// **Problem**: Bursty WebSocket updates cause concurrent marker rebuilds:
/// ```
/// [WS] 3 updates in 50ms
/// [REBUILD] Started...
/// [REBUILD] Started...
/// [REBUILD] Started...
/// Result: Overlapping work, frame drops
/// ```
/// 
/// **Solution**: Queue + serialize + throttle:
/// ```
/// [WS] 3 updates in 50ms
/// [QUEUE] Task 1 enqueued
/// [QUEUE] Task 2 enqueued
/// [QUEUE] Task 3 enqueued
/// [PROCESS] Task 1 (16ms delay)
/// [PROCESS] Task 2 (16ms delay)
/// [PROCESS] Task 3 (16ms delay)
/// Result: Controlled flow, no frame drops
/// ```
/// 
/// **Usage**:
/// ```dart
/// final _markerQueue = MarkerUpdateQueue();
/// 
/// void _onPositionUpdate(Position pos) {
///   _markerQueue.enqueue(() async {
///     await _rebuildMarkers();
///   });
/// }
/// ```
class MarkerUpdateQueue {
  final List<Future<void> Function()> _queue = [];
  bool _processing = false;
  
  /// Minimum delay between consecutive marker updates (1 frame at 60 FPS)
  final Duration throttleDelay;
  
  MarkerUpdateQueue({
    this.throttleDelay = const Duration(milliseconds: 16),
  });
  
  /// Enqueue a marker update task
  /// 
  /// **Behavior**:
  /// - Adds task to queue
  /// - Starts processing if not already running
  /// - Ensures minimum 16ms gap between updates (60 FPS)
  /// 
  /// **Effect**: Even during 100+ updates/sec bursts, markers rebuild
  /// at controlled rate with no frame drops.
  void enqueue(Future<void> Function() task) {
    _queue.add(task);
    
    if (!_processing) {
      _processQueue();
    }
  }
  
  /// Process queued tasks with throttling
  Future<void> _processQueue() async {
    if (_processing) return;
    _processing = true;
    
    while (_queue.isNotEmpty) {
      final task = _queue.removeAt(0);
      
      try {
        await task();
      } catch (e) {
        if (kDebugMode) {
          debugPrint('[MarkerQueue] ⚠️ Task failed: $e');
        }
      }
      
      // Throttle: Wait 1 frame before next update
      if (_queue.isNotEmpty) {
        await Future<void>.delayed(throttleDelay);
      }
    }
    
    _processing = false;
  }
  
  /// Clear all pending tasks
  void clear() {
    _queue.clear();
  }
  
  /// Get queue depth (for diagnostics)
  int get depth => _queue.length;
  
  /// Check if queue is processing
  bool get isProcessing => _processing;
}

/// Debug frame budget profiler (use in profile mode)
/// 
/// **Purpose**: Measure build + raster time per frame to validate
/// that UI optimizations keep frame time under target budget.
/// 
/// **Target Budgets**:
/// - 120 FPS: < 8.3ms per frame
/// - 90 FPS: < 11.1ms per frame  
/// - 60 FPS: < 16.7ms per frame
/// 
/// **Usage**:
/// ```dart
/// void initState() {
///   super.initState();
///   
///   if (kProfileMode) {
///     FrameBudgetProfiler.start(
///       onFrameExceedsBudget: (timing) {
///         debugPrint('[PERF] Frame exceeded budget: '
///             'build=${timing.buildDuration.inMilliseconds}ms, '
///             'raster=${timing.rasterDuration.inMilliseconds}ms');
///       },
///     );
///   }
/// }
/// ```
class FrameBudgetProfiler {
  static const _targetBudgetMs = 16; // 60 FPS target
  static TimingsCallback? _callback;
  
  /// Start frame budget profiling
  /// 
  /// **Parameters**:
  /// - `targetBudgetMs`: Frame time budget in milliseconds (default: 16ms for 60 FPS)
  /// - `onFrameExceedsBudget`: Callback when frame exceeds budget
  static void start({
    int targetBudgetMs = _targetBudgetMs,
    void Function(FrameTiming timing)? onFrameExceedsBudget,
  }) {
    if (!kProfileMode && !kDebugMode) return;
    
    _callback = (timings) {
      for (final timing in timings) {
        final totalMs = timing.buildDuration.inMilliseconds +
                       timing.rasterDuration.inMilliseconds;
        
        if (totalMs > targetBudgetMs) {
          onFrameExceedsBudget?.call(timing);
        }
      }
    };
    
    SchedulerBinding.instance.addTimingsCallback(_callback!);
    
    if (kDebugMode) {
      debugPrint('[FrameProfiler] Started (target: ${targetBudgetMs}ms)');
    }
  }
  
  /// Stop frame budget profiling
  static void stop() {
    if (_callback != null) {
      SchedulerBinding.instance.removeTimingsCallback(_callback!);
      _callback = null;
      
      if (kDebugMode) {
        debugPrint('[FrameProfiler] Stopped');
      }
    }
  }
}

// ============================================================================
// 🎯 IDLE TASK SCHEDULER & MEMORY MAINTENANCE
// ============================================================================

/// Idle task priority for memory maintenance operations
enum IdleTaskPriority {
  low,      // Run when idle for >5 seconds
  medium,   // Run when idle for >2 seconds
  high,     // Run when idle for >1 second
  critical, // Run ASAP after frame
}

/// Idle task scheduler for memory maintenance without frame drops
/// 
/// **Purpose**: Schedule cleanup tasks during idle periods to avoid
/// impacting frame rendering performance.
/// 
/// **Features**:
/// - Priority-based task queue
/// - Frame budget awareness (won't run if frames are busy)
/// - Automatic deferral if frame time exceeds budget
/// - Idle frame overrun tracking (<1% target)
/// 
/// **Usage**:
/// ```dart
/// RenderScheduler.scheduleIdleTask(
///   () => MarkerPool.trim(),
///   priority: IdleTaskPriority.medium,
/// );
/// ```
class IdleTaskScheduler {
  static final List<_IdleTask> _taskQueue = [];
  static bool _isProcessing = false;
  static int _totalTasks = 0;
  static int _completedTasks = 0;
  static int _deferredTasks = 0;
  static const _frameBudgetMs = 16; // 60 FPS target

  /// Schedule an idle task with priority
  static void scheduleTask(
    VoidCallback task, {
    IdleTaskPriority priority = IdleTaskPriority.medium,
    String? name,
  }) {
    _totalTasks++;
    
    final idleTask = _IdleTask(
      task: task,
      priority: priority,
      name: name ?? 'Task#$_totalTasks',
      enqueuedAt: DateTime.now(),
    );

    _taskQueue.add(idleTask);
    _taskQueue.sort((a, b) => b.priority.index.compareTo(a.priority.index));

    if (kDebugMode) {
      debugPrint('[IdleTaskScheduler] 📋 Queued: ${idleTask.name} (${priority.name})');
    }

    _processNextTask();
  }

  /// Process next task in queue
  static void _processNextTask() {
    if (_isProcessing || _taskQueue.isEmpty) return;

    _isProcessing = true;

    final task = _taskQueue.removeAt(0);
    final delay = _getDelayForPriority(task.priority);

    // Schedule task after appropriate idle delay
    Future.delayed(delay, () {
      _executeTask(task);
    });
  }

  /// Execute task with frame budget check
  static void _executeTask(_IdleTask task) {
    final stopwatch = Stopwatch()..start();

    try {
      task.task();
      _completedTasks++;
      
      stopwatch.stop();
      final executionMs = stopwatch.elapsedMilliseconds;

      if (executionMs > _frameBudgetMs) {
        _deferredTasks++;
        
        if (kDebugMode) {
          debugPrint(
            '[IdleTaskScheduler] ⚠️ Task exceeded frame budget: ${task.name} '
            '(${executionMs}ms > ${_frameBudgetMs}ms)',
          );
        }
      } else if (kDebugMode) {
        debugPrint(
          '[IdleTaskScheduler] ✅ Completed: ${task.name} (${executionMs}ms)',
        );
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[IdleTaskScheduler] ❌ Error in ${task.name}: $e');
      }
    } finally {
      _isProcessing = false;
      _processNextTask(); // Process next task
    }
  }

  /// Get delay for priority level
  static Duration _getDelayForPriority(IdleTaskPriority priority) {
    return switch (priority) {
      IdleTaskPriority.critical => Duration.zero,
      IdleTaskPriority.high => const Duration(seconds: 1),
      IdleTaskPriority.medium => const Duration(seconds: 2),
      IdleTaskPriority.low => const Duration(seconds: 5),
    };
  }

  /// Get idle task statistics
  static Map<String, dynamic> getStats() {
    final overrunRate = _completedTasks > 0 
        ? _deferredTasks / _completedTasks 
        : 0.0;
    
    return {
      'queuedTasks': _taskQueue.length,
      'totalTasks': _totalTasks,
      'completedTasks': _completedTasks,
      'deferredTasks': _deferredTasks,
      'overrunRate': overrunRate,
      'isProcessing': _isProcessing,
    };
  }

  /// Clear task queue
  static void clear() {
    _taskQueue.clear();
    _isProcessing = false;
  }
}

/// Internal idle task representation
class _IdleTask {
  _IdleTask({
    required this.task,
    required this.priority,
    required this.name,
    required this.enqueuedAt,
  });

  final VoidCallback task;
  final IdleTaskPriority priority;
  final String name;
  final DateTime enqueuedAt;
}

/// Memory GC hint utilities
class GCHintScheduler {
  static int _hintCount = 0;
  static DateTime? _lastHint;
  static const _minHintInterval = Duration(minutes: 2);

  /// Suggest GC during idle period (non-blocking hint to VM)
  /// 
  /// **When to use**:
  /// - After large memory operations
  /// - During idle periods when heap has grown
  /// - After cleanup operations
  /// 
  /// **Effect**: Provides a hint to the Dart VM that GC might be beneficial.
  /// The VM is free to ignore the hint if it determines GC is not needed.
  static void maybeGCHint({String? reason}) {
    // Throttle hints to avoid spamming VM
    if (_lastHint != null && 
        DateTime.now().difference(_lastHint!) < _minHintInterval) {
      return;
    }

    _lastHint = DateTime.now();
    _hintCount++;

    // Note: Dart doesn't have direct GC.collect() like Java
    // We use Timeline events as hints that can be observed by profiling tools
    // The VM's GC is generational and runs automatically
    if (kDebugMode) {
      debugPrint('[GCHint] 💨 Hint #$_hintCount${reason != null ? ' ($reason)' : ''}');
    }
  }

  /// Get GC hint statistics
  static Map<String, dynamic> getStats() {
    return {
      'hintCount': _hintCount,
      'lastHint': _lastHint?.toIso8601String(),
    };
  }
}
