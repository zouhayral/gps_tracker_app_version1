import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

class RebuildProfilerOverlay extends StatefulWidget {
  const RebuildProfilerOverlay({
    required this.child,
    super.key,
  });

  final Widget child;

  @override
  State<RebuildProfilerOverlay> createState() => _RebuildProfilerOverlayState();
}

class _RebuildProfilerOverlayState extends State<RebuildProfilerOverlay> {
  final _stats = _PerformanceStats();
  Timer? _statsTimer;
  Timer? _logTimer;

  @override
  void initState() {
    super.initState();
    if (kDebugMode) {
      _initTimers();
    }
  }

  void _initTimers() {
    // Update stats every frame
    SchedulerBinding.instance.addTimingsCallback(_onFrameTimings);

    // Log stats every 5 seconds
    _logTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      final stats = _stats.snapshot;
      debugPrint(
        '[PERF] Avg FPS: ${stats.avgFps.toStringAsFixed(1)}, '
        'frame time: ${stats.avgFrameTime.toStringAsFixed(1)}ms, '
        'dropped: ${stats.droppedFrames}',
      );
    });

    // Reset stats every 5 seconds to keep moving average
    _statsTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      _stats.reset();
    });
  }

  void _onFrameTimings(List<FrameTiming> timings) {
    for (final timing in timings) {
      final duration = timing.totalSpan.inMicroseconds / 1000.0; // Convert to ms
      _stats.addFrameTiming(duration);
    }
  }

  @override
  void dispose() {
    _statsTimer?.cancel();
    _logTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!kDebugMode) return widget.child;

    return Stack(
      children: [
        widget.child,
        Positioned(
          top: 0,
          right: 0,
          child: SafeArea(
            child: Container(
              padding: const EdgeInsets.all(8),
              color: Colors.black54,
              child: ValueListenableBuilder(
                valueListenable: _stats.notifier,
                builder: (context, stats, _) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        'FPS: ${stats.avgFps.toStringAsFixed(1)}',
                        style: const TextStyle(color: Colors.white),
                      ),
                      Text(
                        'Frame: ${stats.avgFrameTime.toStringAsFixed(1)}ms',
                        style: const TextStyle(color: Colors.white),
                      ),
                      Text(
                        'Dropped: ${stats.droppedFrames}',
                        style: const TextStyle(color: Colors.white),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _PerformanceStats {
  final List<double> _frameTimes = [];
  int _droppedFrames = 0;
  final notifier = ValueNotifier(_StatsSnapshot(0, 0, 0));

  void addFrameTiming(double frameTimeMs) {
    _frameTimes.add(frameTimeMs);
    if (frameTimeMs > 16.67) { // Above 60 FPS threshold
      _droppedFrames++;
    }
    _updateSnapshot();
  }

  void reset() {
    _frameTimes.clear();
    _droppedFrames = 0;
    _updateSnapshot();
  }

  void _updateSnapshot() {
    if (_frameTimes.isEmpty) return;

    final avgFrameTime = _frameTimes.reduce((a, b) => a + b) / _frameTimes.length;
    final avgFps = 1000.0 / avgFrameTime;

    notifier.value = _StatsSnapshot(
      avgFps,
      avgFrameTime,
      _droppedFrames,
    );
  }

  _StatsSnapshot get snapshot => notifier.value;
}

class _StatsSnapshot {
  const _StatsSnapshot(this.avgFps, this.avgFrameTime, this.droppedFrames);

  final double avgFps;
  final double avgFrameTime;
  final int droppedFrames;
}

class RebuildCounter extends StatefulWidget {
  const RebuildCounter({
    required this.child,
    required this.name,
    super.key,
  });

  final Widget child;
  final String name;

  @override
  State<RebuildCounter> createState() => _RebuildCounterState();
}

class _RebuildCounterState extends State<RebuildCounter> {
  int _rebuilds = 0;
  DateTime? _lastRebuild;
  Timer? _logTimer;
  final List<Duration> _intervals = [];

  @override
  void initState() {
    super.initState();
    if (kDebugMode) {
      _logTimer = Timer.periodic(const Duration(seconds: 2), (_) {
        final avgInterval = _intervals.isEmpty
            ? 0.0
            : _intervals.reduce((a, b) => a + b).inMilliseconds /
                _intervals.length;
        debugPrint(
          '[REBUILD] ${widget.name} rebuilt $_rebuilds times '
          '(avg ${avgInterval.toStringAsFixed(1)} ms apart)',
        );
        _rebuilds = 0;
        _intervals.clear();
      });
    }
  }

  @override
  void dispose() {
    _logTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (kDebugMode) {
      _rebuilds++;
      final now = DateTime.now();
      if (_lastRebuild != null) {
        _intervals.add(now.difference(_lastRebuild!));
      }
      _lastRebuild = now;
    }
    return widget.child;
  }
}