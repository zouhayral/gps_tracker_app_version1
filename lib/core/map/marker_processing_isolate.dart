import 'dart:async';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';
import 'package:my_app_gps/core/diagnostics/dev_diagnostics.dart';
import 'package:my_app_gps/features/map/core/map_adapter.dart';
import 'package:my_app_gps/features/map/data/position_model.dart';

/// Background isolate for heavy marker processing operations
/// Moves position filtering and marker creation off the main thread
class MarkerProcessingIsolate {
  MarkerProcessingIsolate._();

  static final MarkerProcessingIsolate instance = MarkerProcessingIsolate._();

  Isolate? _isolate;
  SendPort? _sendPort;
  ReceivePort? _receivePort;
  StreamController<List<MapMarkerData>>? _resultStreamController;

  bool _isInitialized = false;

  /// Initialize the background isolate
  Future<void> initialize() async {
    if (_isInitialized) {
      if (kDebugMode) {
        debugPrint('[ISOLATE] Already initialized, skipping');
      }
      return;
    }

    _receivePort = ReceivePort();
    _resultStreamController = StreamController<List<MapMarkerData>>.broadcast();

    _receivePort!.listen((message) {
      if (message is SendPort) {
        _sendPort = message;
        _isInitialized = true;
        if (kDebugMode) {
          debugPrint('[MarkerIsolate] Initialized and ready');
        }
      } else if (message is List<MapMarkerData>) {
        _resultStreamController?.add(message);
      }
    });

    _isolate = await Isolate.spawn(
      _isolateEntry,
      _receivePort!.sendPort,
      debugName: 'MarkerProcessingIsolate',
    );

    // Wait for isolate to be ready
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }

  /// Process markers in background isolate
  Future<List<MapMarkerData>> processMarkers(
    Map<int, Position> positions,
    List<Map<String, dynamic>> devices,
    Set<int> selectedIds,
    String query,
  ) async {
    if (!_isInitialized || _sendPort == null) {
      // Fallback to main thread if isolate not ready
      final sw = Stopwatch()..start();
      final result = _processMarkersSync(positions, devices, selectedIds, query);
      sw.stop();
      if (kDebugMode) {
        DevDiagnostics.instance.recordClusterCompute(sw.elapsedMilliseconds);
      }
      return result;
    }

    try {
      final completer = Completer<List<MapMarkerData>>();

      // Listen for result
      StreamSubscription<List<MapMarkerData>>? subscription;
      subscription = _resultStreamController?.stream.listen((markers) {
        if (!completer.isCompleted) {
          completer.complete(markers);
          subscription?.cancel();
        }
      });

      // Send work to isolate
      final sw = Stopwatch()..start();
      _sendPort!.send(_MarkerProcessingRequest(
        positions: positions,
        devices: devices,
        selectedIds: selectedIds,
        query: query,
      ),);

      // Timeout after 100ms and fall back to sync
      final res = await completer.future.timeout(
        const Duration(milliseconds: 100),
        onTimeout: () {
          subscription?.cancel();
          final sw2 = Stopwatch()..start();
          final r = _processMarkersSync(positions, devices, selectedIds, query);
          sw2.stop();
          if (kDebugMode) {
            DevDiagnostics.instance.recordClusterCompute(sw2.elapsedMilliseconds);
          }
          return r;
        },
      );
      sw.stop();
      if (kDebugMode) {
        DevDiagnostics.instance.recordClusterCompute(sw.elapsedMilliseconds);
      }
      return res;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[MarkerIsolate] Error: $e, falling back to sync');
      }
      return _processMarkersSync(positions, devices, selectedIds, query);
    }
  }

  /// Decimate markers in the background isolate using distance threshold
  /// Keeps markers at least [minDistanceMeters] apart, capped to [markerCap].
  Future<List<MapMarkerData>> decimateMarkers(
    List<MapMarkerData> markers, {
    required int markerCap,
    double minDistanceMeters = 100,
  }) async {
    if (!_isInitialized || _sendPort == null) {
      // Fallback on main thread
      return _decimateByDistance(markers, markerCap, minDistanceMeters);
    }

    try {
      final completer = Completer<List<MapMarkerData>>();
      StreamSubscription<List<MapMarkerData>>? subscription;
      subscription = _resultStreamController?.stream.listen((result) {
        if (!completer.isCompleted) {
          completer.complete(result);
          subscription?.cancel();
        }
      });

      _sendPort!.send(_DecimationRequest(
        markers: markers,
        markerCap: markerCap,
        minDistanceMeters: minDistanceMeters,
      ));

      // Use a short timeout; fall back to sync if isolate is busy
      return completer.future.timeout(
        const Duration(milliseconds: 100),
        onTimeout: () {
          subscription?.cancel();
          return _decimateByDistance(markers, markerCap, minDistanceMeters);
        },
      );
    } catch (_) {
      return _decimateByDistance(markers, markerCap, minDistanceMeters);
    }
  }

  /// Dispose the isolate
  void dispose() {
    _isolate?.kill(priority: Isolate.immediate);
    _isolate = null;
    _receivePort?.close();
    _receivePort = null;
    _resultStreamController?.close();
    _resultStreamController = null;
    _sendPort = null;
    _isInitialized = false;
  }

  /// Isolate entry point
  /// Use vm entry-point pragma so this function remains reachable by the VM
  /// when tree-shaking/minification is used in AOT builds.
  @pragma('vm:entry-point')
  static void _isolateEntry(SendPort mainSendPort) {
    final isolateReceivePort = ReceivePort();
    mainSendPort.send(isolateReceivePort.sendPort);

    isolateReceivePort.listen((message) {
      if (message is _MarkerProcessingRequest) {
        // Perform heavy marker diffing, identity and hashing inside the isolate
        // so the main thread only receives the final marker list.
        final markers = _processMarkersSync(
          message.positions,
          message.devices,
          message.selectedIds,
          message.query,
        );
        mainSendPort.send(markers);
      } else if (message is _DecimationRequest) {
        final decimated = _decimateByDistance(
          message.markers,
          message.markerCap,
          message.minDistanceMeters,
        );
        mainSendPort.send(decimated);
      }
    });
  }

  /// Synchronous marker processing (used as fallback and in isolate)
  static List<MapMarkerData> _processMarkersSync(
    Map<int, Position> positions,
    List<Map<String, dynamic>> devices,
    Set<int> selectedIds,
    String query,
  ) {
    final markers = <MapMarkerData>[];
    final processedIds = <int>{};
    final q = query.trim().toLowerCase();

    // Process devices with positions
    for (final p in positions.values) {
      final deviceId = p.deviceId;
      final name = devices
              .firstWhere(
                (d) => d['id'] == deviceId,
                orElse: () => <String, Object>{'name': ''},
              )['name']
              ?.toString() ??
          '';

      if (q.isNotEmpty &&
          !name.toLowerCase().contains(q) &&
          !selectedIds.contains(deviceId)) {
        continue;
      }

      if (_valid(p.latitude, p.longitude)) {
        markers.add(MapMarkerData(
          id: '$deviceId',
          position: LatLng(p.latitude, p.longitude),
          isSelected: selectedIds.contains(deviceId),
          meta: {
            'name': name,
            'speed': p.speed,
            'course': p.course,
          },
        ),);
        processedIds.add(deviceId);
      }
    }

    // Process devices without positions (use stored lat/lon)
    for (final d in devices) {
      final deviceId = d['id'] as int?;
      if (deviceId == null || processedIds.contains(deviceId)) continue;

      final name = d['name']?.toString() ?? '';
      if (q.isNotEmpty &&
          !name.toLowerCase().contains(q) &&
          !selectedIds.contains(deviceId)) {
        continue;
      }

      final lat = _asDouble(d['latitude']);
      final lon = _asDouble(d['longitude']);
      if (_valid(lat, lon)) {
        markers.add(MapMarkerData(
          id: '$deviceId',
          position: LatLng(lat!, lon!),
          isSelected: selectedIds.contains(deviceId),
          meta: {'name': name},
        ),);
      }
    }

    // Final validation
    markers
        .removeWhere((m) => !_valid(m.position.latitude, m.position.longitude));
    return markers;
  }

  /// Simple greedy decimator: keeps markers at least [minDistanceMeters] apart
  /// until [maxCount] reached. Suitable for quick LOD downsampling.
  static List<MapMarkerData> _decimateByDistance(
    List<MapMarkerData> markers,
    int maxCount,
    double minDistanceMeters,
  ) {
    if (markers.length <= maxCount) return List<MapMarkerData>.from(markers);

    const distance = Distance();
    final result = <MapMarkerData>[];

    for (final m in markers) {
      bool farEnough = true;
      for (final kept in result) {
        final d = distance.as(LengthUnit.Meter, m.position, kept.position);
        if (d < minDistanceMeters) {
          farEnough = false;
          break;
        }
      }
      if (farEnough) {
        result.add(m);
        if (result.length >= maxCount) break;
      }
    }

    // If we didn't reach the cap due to strict spacing, fill with remaining
    if (result.length < maxCount) {
      for (final m in markers) {
        if (result.length >= maxCount) break;
        if (!result.contains(m)) result.add(m);
      }
    }

    return result;
  }

  static bool _valid(double? lat, double? lon) =>
      lat != null &&
      lon != null &&
      lat >= -90 &&
      lat <= 90 &&
      lon >= -180 &&
      lon <= 180;

  static double? _asDouble(dynamic v) {
    if (v == null) return null;
    if (v is double) return v;
    if (v is int) return v.toDouble();
    if (v is String) return double.tryParse(v);
    return null;
  }
}

/// Request message for isolate processing
class _MarkerProcessingRequest {
  const _MarkerProcessingRequest({
    required this.positions,
    required this.devices,
    required this.selectedIds,
    required this.query,
  });

  final Map<int, Position> positions;
  final List<Map<String, dynamic>> devices;
  final Set<int> selectedIds;
  final String query;
}

/// Request message for decimation
class _DecimationRequest {
  const _DecimationRequest({
    required this.markers,
    required this.markerCap,
    required this.minDistanceMeters,
  });

  final List<MapMarkerData> markers;
  final int markerCap;
  final double minDistanceMeters;
}
