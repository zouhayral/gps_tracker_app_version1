import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:my_app_gps/core/utils/adaptive_render.dart';
import 'package:my_app_gps/perf/startup_prewarm.dart';

/// Debug-only FPS/LOD overlay
///
/// Displays current FPS, LOD mode, and camera throttle statistics.
/// Only visible in debug builds.
///
/// **Usage:**
/// ```dart
/// Stack(
///   children: [
///     // Your map widget
///     if (kDebugMode) PerformanceDebugOverlay(
///       fps: _currentFps,
///       lodMode: _lodController.mode,
///       cameraThrottle: _cameraThrottle,
///     ),
///   ],
/// )
/// ```
class PerformanceDebugOverlay extends StatelessWidget {
  final double fps;
  final RenderMode lodMode;
  final CameraThrottle? cameraThrottle;
  final bool showPrewarmStatus;

  const PerformanceDebugOverlay({
    required this.fps,
    required this.lodMode,
    this.cameraThrottle,
    this.showPrewarmStatus = true,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    // Only show in debug mode
    if (!kDebugMode) return const SizedBox.shrink();

    return Positioned(
      top: 60,
      right: 8,
      child: Material(
        color: Colors.black.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // FPS
              _buildRow(
                icon: Icons.speed,
                label: 'FPS',
                value: fps.toStringAsFixed(1),
                color: _getFpsColor(fps),
              ),

              const SizedBox(height: 4),

              // LOD Mode
              _buildRow(
                icon: Icons.tune,
                label: 'LOD',
                value: lodMode.name.toUpperCase(),
                color: _getLodColor(lodMode),
              ),

              // Camera Throttle
              if (cameraThrottle != null) ...[
                const SizedBox(height: 4),
                _buildThrottleStats(cameraThrottle!),
              ],

              // Prewarm Status
              if (showPrewarmStatus) ...[
                const SizedBox(height: 4),
                _buildPrewarmStatus(),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRow({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 4),
        Text(
          '$label: ',
          style: const TextStyle(
            color: Colors.white70,
            fontSize: 12,
            fontWeight: FontWeight.bold,
          ),
        ),
        Text(
          value,
          style: TextStyle(
            color: color,
            fontSize: 12,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }

  Widget _buildThrottleStats(CameraThrottle throttle) {
    final stats = throttle.getStats();
    final totalUpdates = stats['totalUpdates'] as int;
    final skippedCount = stats['skippedCount'] as int;
    final lastIntervalMs = stats['lastIntervalMs'] as int?;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildRow(
          icon: Icons.videocam,
          label: 'Cam',
          value: '$totalUpdates upd, $skippedCount skip',
          color: Colors.cyan,
        ),
        if (lastIntervalMs != null)
          Padding(
            padding: const EdgeInsets.only(left: 20),
            child: Text(
              'Last: ${lastIntervalMs}ms',
              style: const TextStyle(
                color: Colors.white60,
                fontSize: 10,
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildPrewarmStatus() {
    final isRunning = StartupPrewarm.isRunning;
    final (completed, total) = StartupPrewarm.progress;

    if (!isRunning && completed == 0) {
      return const SizedBox.shrink();
    }

    return _buildRow(
      icon: Icons.rocket_launch,
      label: 'Prewarm',
      value: isRunning ? '$completed/$total' : 'Done',
      color: isRunning ? Colors.orange : Colors.green,
    );
  }

  Color _getFpsColor(double fps) {
    if (fps >= 55) return Colors.green;
    if (fps >= 40) return Colors.yellow;
    if (fps >= 25) return Colors.orange;
    return Colors.red;
  }

  Color _getLodColor(RenderMode mode) {
    switch (mode) {
      case RenderMode.high:
        return Colors.green;
      case RenderMode.medium:
        return Colors.yellow;
      case RenderMode.low:
        return Colors.red;
    }
  }
}

/// Compact debug overlay for minimal visual footprint
///
/// Shows only the most critical metrics in a smaller format.
///
/// **Usage:**
/// ```dart
/// if (kDebugMode) CompactDebugOverlay(
///   fps: _currentFps,
///   lodMode: _lodController.mode,
/// ),
/// ```
class CompactDebugOverlay extends StatelessWidget {
  final double fps;
  final RenderMode lodMode;

  const CompactDebugOverlay({
    required this.fps,
    required this.lodMode,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    // Only show in debug mode
    if (!kDebugMode) return const SizedBox.shrink();

    return Positioned(
      top: 60,
      right: 8,
      child: Material(
        color: Colors.black.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(4),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          child: Text(
            '${fps.toStringAsFixed(0)} FPS | ${lodMode.name.toUpperCase()}',
            style: TextStyle(
              color: _getFpsColor(fps),
              fontSize: 10,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ),
    );
  }

  Color _getFpsColor(double fps) {
    if (fps >= 55) return Colors.green;
    if (fps >= 40) return Colors.yellow;
    if (fps >= 25) return Colors.orange;
    return Colors.red;
  }
}
