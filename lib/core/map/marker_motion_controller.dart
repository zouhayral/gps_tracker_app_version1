import 'dart:async';
import 'dart:math' as math;

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
    this.enableExtrapolation = true,
    this.maxExtrapolation = const Duration(seconds: 8),
    this.minSpeedKmhForExtrapolation = 3.0,
  }) {
    // Lazy scheduling: only tick when there are active devices.
    // Also disable timers entirely in tests to avoid pending timers.
    if (!testMode) {
      _maybeScheduleTick();
    }
  }

  // Config
  /// Target tick cadence for motion updates (default ~200ms for balanced smoothness)
  Duration motionInterval; // ~200ms
  final Duration interpolationDuration; // ~1200ms (between real updates)
  final Curve curve;
  final bool enableExtrapolation;
  final Duration maxExtrapolation;
  final double minSpeedKmhForExtrapolation;

  /// Single-shot timer used for on-demand scheduling (avoids idle wakeups)
  Timer? _ticker;
  final ValueNotifier<int> _tick = ValueNotifier<int>(0);
  
  // Track devices that should be processed on each tick
  final Set<int> _activeDevices = <int>{};
  
  // Optional verbosity for motion logs (debug-only)
  bool verboseMotionLogs = false;
  
  void _logMotion(String msg) {
    if (kDebugMode && verboseMotionLogs) debugPrint(msg);
  }

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
    double? speedKmh,
    double? courseDeg,
  }) {
    if (kDebugMode) {
      debugPrint('[MOTION] device#$deviceId received target ${target.latitude.toStringAsFixed(6)},${target.longitude.toStringAsFixed(6)}');
    }
    
    final now = DateTime.now();
    final startTime = now;
    final endTime = now.add(interpolationDuration);

    final posNotifier = _positions.putIfAbsent(
      deviceId,
      () => ValueNotifier<LatLng>(target),
    );

    final prev = _states[deviceId];
    final from = prev?.lastEmitted ?? posNotifier.value;

    _states[deviceId] = _MotionState(
      from: from,
      to: target,
      start: startTime,
      end: endTime,
      lastEmitted: from,
      lastTelemetry: timestamp ?? now,
      lastEmitAt: now,
      speedKmh: speedKmh ?? prev?.speedKmh,
      courseDeg: courseDeg ?? prev?.courseDeg,
    );
    _states[deviceId]!.isInterpolating = true;

    // Ensure device is marked active for ticking
    _activeDevices.add(deviceId);

  // Schedule ticking if not already scheduled
  if (!testMode) _maybeScheduleTick();

    _logMotion('[MOTION] Device #$deviceId interpolating: (${from.latitude.toStringAsFixed(6)}, ${from.longitude.toStringAsFixed(6)})  (${target.latitude.toStringAsFixed(6)}, ${target.longitude.toStringAsFixed(6)}) over ${interpolationDuration.inMilliseconds} ms');
  }

  void _onTick() {
    final now = DateTime.now();
    var anyActive = false;

    if (_activeDevices.isEmpty) return;

    // Interpolation pass for active devices only
    for (final id in _activeDevices.toList()) {
      final s = _states[id];
      if (s == null) {
        _activeDevices.remove(id);
        continue;
      }

      final animActive = now.isBefore(s.end);
      if (animActive) {
        final t = _clamp01(_progress(s.start, s.end, now));
        final eased = curve.transform(t);
        final lat = _lerpDouble(s.from.latitude, s.to.latitude, eased);
        final lon = _lerpDouble(s.from.longitude, s.to.longitude, eased);
        final cur = LatLng(lat, lon);
        _positions[id]?.value = cur;
        s.lastEmitted = cur;
        s.lastEmitAt = now;
        s.isInterpolating = true;
        s.isExtrapolating = false;

        if (t >= 1) {
          // Debounce completion log
          if (!s.hasReachedTarget) {
            _logMotion('[MOTION] Device #$id reached target.');
            s.hasReachedTarget = true;
          }
          s.isInterpolating = false;
        } else {
          s.hasReachedTarget = false;
          anyActive = true;
        }
      } else {
        s.isInterpolating = false;
      }
    }

    // Dead-reckoning extrapolation when not actively interpolating
    if (enableExtrapolation) {
      for (final id in _activeDevices.toList()) {
        final s = _states[id];
        if (s == null) continue;
        if (s.isInterpolating) continue;

        final spd = s.speedKmh ?? 0.0;
        final course = s.courseDeg;
        final telemetryAge = now.difference(s.lastTelemetry);
        final dt = now.difference(s.lastEmitAt).inMilliseconds / 1000;

        final canExtrapolate = spd >= minSpeedKmhForExtrapolation &&
            course != null &&
            telemetryAge <= maxExtrapolation &&
            dt > 0;

        if (canExtrapolate) {
          final cur = s.lastEmitted;
          final drift = _offset(cur, spd, course, dt);
          _positions[id]?.value = drift;
          s.lastEmitted = drift;
          s.lastEmitAt = now;
          s.isExtrapolating = true;
          s.hasReachedTarget = false;
          anyActive = true;
        } else {
          s.isExtrapolating = false;
        }
      }
    }

    // Pause idle devices to reduce CPU use
    for (final id in _activeDevices.toList()) {
      final s = _states[id];
      if (s == null) {
        _activeDevices.remove(id);
        continue;
      }
      if (!s.isInterpolating && !s.isExtrapolating) {
        _activeDevices.remove(id);
      }
    }

    // Notify global listeners only if any device is actively moving
    if (anyActive) {
      _tick.value = _tick.value + 1;
    }

    // Reschedule next tick if there are still active devices
    if (!testMode) _maybeScheduleTick(force: anyActive && _activeDevices.isNotEmpty);
  }

  /// Schedules the next motion tick if needed using a single-shot timer.
  ///
  /// This design avoids a constantly running periodic timer when there are no
  /// active devices, reducing CPU wakeups and GPU overdraw from unnecessary
  /// repaints.
  void _maybeScheduleTick({bool force = false}) {
    if (_ticker?.isActive == true && !force) return;
    if (_activeDevices.isEmpty) {
      // Nothing to animate, ensure timer is cancelled
      _ticker?.cancel();
      _ticker = null;
      return;
    }
    _ticker?.cancel();
    _ticker = Timer(motionInterval, _onTick);
  }

  /// Allows external systems (e.g., Adaptive LOD) to adjust the motion
  /// tick interval at runtime. Takes effect on the next scheduled tick.
  void setMotionInterval(Duration interval) {
    if (interval == motionInterval) return;
    motionInterval = interval;
    if (!testMode) {
      // Re-arm the timer with the new interval if currently scheduled
      if (_ticker?.isActive == true) {
        _ticker?.cancel();
        _ticker = Timer(motionInterval, _onTick);
      }
    }
  }

  double _progress(DateTime start, DateTime end, DateTime now) {
    final total = end.difference(start).inMilliseconds;
    if (total <= 0) return 1;
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

/// Internal motion state for a single device
class _MotionState {
  _MotionState({
    required this.from,
    required this.to,
    required this.start,
    required this.end,
    required this.lastEmitted,
    required this.lastTelemetry,
    required this.lastEmitAt,
    this.speedKmh,
    this.courseDeg,
  });

  final LatLng from;
  final LatLng to;
  final DateTime start;
  final DateTime end;
  LatLng lastEmitted;
  DateTime lastTelemetry;
  double? speedKmh;
  double? courseDeg;
  DateTime lastEmitAt;
  bool isInterpolating = false;
  bool isExtrapolating = false;
  bool hasReachedTarget = false;
}

/// Geo helpers for dead-reckoning extrapolation
LatLng _offset(LatLng from, double speedKmh, double courseDeg, double dtSeconds) {
  // Convert speed to m/s and compute distance
  final v = speedKmh / 3.6; // m/s
  final d = v * dtSeconds; // meters
  if (d <= 0) return from;
  
  // Earth radius in meters
  const R = 6371000;
  final brg = courseDeg * math.pi / 180;
  final lat1 = from.latitude * math.pi / 180;
  final lon1 = from.longitude * math.pi / 180;
  final angDist = d / R;
  final sinLat1 = math.sin(lat1);
  final cosLat1 = math.cos(lat1);
  final sinAD = math.sin(angDist);
  final cosAD = math.cos(angDist);

  final sinLat2 = sinLat1 * cosAD + cosLat1 * sinAD * math.cos(brg);
  final lat2 = math.asin(sinLat2);
  final y = math.sin(brg) * sinAD * cosLat1;
  final x = cosAD - sinLat1 * sinLat2;
  final lon2 = lon1 + math.atan2(y, x);

  final newLat = lat2 * 180 / math.pi;
  var newLon = lon2 * 180 / math.pi;
  
  // Normalize longitude to [-180, 180]
  if (newLon > 180) newLon -= 360;
  if (newLon < -180) newLon += 360;
  
  return LatLng(newLat, newLon);
}
