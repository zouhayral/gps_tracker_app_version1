import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

/// MarkerMotionController
///
/// Smoothly interpolates device marker positions between discrete telemetry updates.
/// - Per-device ValueNotifier emits LatLng at a steady interval (kMotionInterval)
/// - On new telemetry, we interpolate from current -> target over kInterpolationDuration
/// - Curve-eased progression (default: Curves.easeOutCubic)
/// - Designed to be lightweight and work with FMTC throttling/diffing
class MarkerMotionController {
  /// When true (tests), disables the periodic timer to avoid pending timers.
  static bool testMode = false;
  MarkerMotionController({
    this.motionInterval = const Duration(milliseconds: 200),
    this.interpolationDuration = const Duration(milliseconds: 1200),
    this.curve = Curves.easeOutCubic,
  }) {
    // Disable periodic ticker in tests to avoid pending timers in widget tests.
    _ticker = testMode ? null : Timer.periodic(motionInterval, _onTick);
  }

  // Config
  final Duration motionInterval; // ~200ms
  final Duration interpolationDuration; // ~1200ms (between real updates)
  final Curve curve;

  late final Timer? _ticker;
  final ValueNotifier<int> _tick = ValueNotifier<int>(0);

  // Per-device state
  final Map<int, _MotionState> _states = <int, _MotionState>{};
  final Map<int, ValueNotifier<LatLng>> _positions = <int, ValueNotifier<LatLng>>{};

  /// Expose a ValueListenable for a device's interpolated LatLng
  ValueListenable<LatLng>? listenableFor(int deviceId) => _positions[deviceId];

  /// Global motion tick (increments when any device is animating)
  ValueListenable<int> get globalTick => _tick;

  /// Get current value (if any)
  LatLng? currentValue(int deviceId) => _positions[deviceId]?.value;

  /// Update target position for a device; starts a new interpolation window.
  void updatePosition({
    required int deviceId,
    required LatLng target,
    DateTime? timestamp,
  }) {
    final now = DateTime.now();
    final startTime = now;
    final endTime = now.add(interpolationDuration);

    final posNotifier = _positions.putIfAbsent(deviceId, () => ValueNotifier<LatLng>(target));

    final prev = _states[deviceId];
    final from = prev?.lastEmitted ?? posNotifier.value;

    _states[deviceId] = _MotionState(
      from: from,
      to: target,
      start: startTime,
      end: endTime,
      lastEmitted: from,
    );

    if (kDebugMode) {
      debugPrint('[MOTION] Device #$deviceId interpolating: '
          '(${from.latitude.toStringAsFixed(6)}, ${from.longitude.toStringAsFixed(6)}) '
          '→ (${target.latitude.toStringAsFixed(6)}, ${target.longitude.toStringAsFixed(6)}) '
          'over ${interpolationDuration.inMilliseconds} ms');
    }
  }

  void _onTick(Timer _) {
    final now = DateTime.now();
    final toComplete = <int>[];
    var anyActive = false;

    for (final entry in _states.entries) {
      final id = entry.key;
      final s = entry.value;

      final t = _clamp01(_progress(s.start, s.end, now));
      final eased = curve.transform(t);

      final lat = _lerpDouble(s.from.latitude, s.to.latitude, eased);
      final lon = _lerpDouble(s.from.longitude, s.to.longitude, eased);
      final cur = LatLng(lat, lon);

      _positions[id]?.value = cur;
      s.lastEmitted = cur;

      if (t >= 1.0) {
        toComplete.add(id);
      } else {
        anyActive = true;
      }
    }

    for (final id in toComplete) {
      final s = _states[id];
      if (s != null && kDebugMode) {
        debugPrint('[MOTION] Device #$id reached target.');
      }
      _states.remove(id);
    }

    // Notify global listeners only if any device is actively interpolating
    if (anyActive) {
      _tick.value = _tick.value + 1;
    }
  }

  double _progress(DateTime start, DateTime end, DateTime now) {
    final total = end.difference(start).inMilliseconds;
    if (total <= 0) return 1.0;
    final elapsed = now.difference(start).inMilliseconds;
    return elapsed / total;
  }

  double _clamp01(double v) => v < 0 ? 0 : (v > 1 ? 1 : v);

  double _lerpDouble(double a, double b, double t) => a + (b - a) * t;

  /// Provide a snapshot of all current positions (for batch consumers)
  Map<int, LatLng> get currentPositions {
    return _positions.map((k, v) => MapEntry(k, v.value));
  }

  /// Ensure resources are freed
  void dispose() {
    _ticker?.cancel();
    _tick.dispose();
    for (final vn in _positions.values) {
      vn.dispose();
    }
    _positions.clear();
    _states.clear();
  }
}

class _MotionState {
  _MotionState({
    required this.from,
    required this.to,
    required this.start,
    required this.end,
    required this.lastEmitted,
  });

  final LatLng from;
  final LatLng to;
  final DateTime start;
  final DateTime end;
  LatLng lastEmitted;
}
