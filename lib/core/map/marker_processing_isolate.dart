import 'dart:async';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';
import 'package:my_app_gps/features/map/core/map_adapter.dart';
import 'package:my_app_gps/features/map/data/position_model.dart';

/// Background isolate for heavy marker processing operations
/// Moves position filtering and marker creation off the main thread
class MarkerProcessingIsolate {
  MarkerProcessingIsolate._();

  static final MarkerProcessingIsolate instance = MarkerProcessingIsolate._();

  Isolate? _isolate;
  SendPort? _sendPort;
  final _receivePort = ReceivePort();
  final _resultStreamController =
      StreamController<List<MapMarkerData>>.broadcast();

  bool _isInitialized = false;

  /// Initialize the background isolate
  Future<void> initialize() async {
    if (_isInitialized) return;

    _receivePort.listen((message) {
      if (message is SendPort) {
        _sendPort = message;
        _isInitialized = true;
        if (kDebugMode) {
          debugPrint('[MarkerIsolate] Initialized and ready');
        }
      } else if (message is List<MapMarkerData>) {
        _resultStreamController.add(message);
      }
    });

    _isolate = await Isolate.spawn(
      _isolateEntry,
      _receivePort.sendPort,
      debugName: 'MarkerProcessingIsolate',
    );

    // Wait for isolate to be ready
    await Future.delayed(const Duration(milliseconds: 100));
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
      return _processMarkersSync(positions, devices, selectedIds, query);
    }

    try {
      final completer = Completer<List<MapMarkerData>>();

      // Listen for result
      StreamSubscription? subscription;
      subscription = _resultStreamController.stream.listen((markers) {
        if (!completer.isCompleted) {
          completer.complete(markers);
          subscription?.cancel();
        }
      });

      // Send work to isolate
      _sendPort!.send(
        _MarkerProcessingRequest(
          positions: positions,
          devices: devices,
          selectedIds: selectedIds,
          query: query,
        ),
      );

      // Timeout after 100ms and fall back to sync
      return await completer.future.timeout(
        const Duration(milliseconds: 100),
        onTimeout: () {
          subscription?.cancel();
          return _processMarkersSync(positions, devices, selectedIds, query);
        },
      );
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[MarkerIsolate] Error: $e, falling back to sync');
      }
      return _processMarkersSync(positions, devices, selectedIds, query);
    }
  }

  /// Dispose the isolate
  void dispose() {
    _isolate?.kill(priority: Isolate.immediate);
    _isolate = null;
    _receivePort.close();
    _resultStreamController.close();
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
        markers.add(
          MapMarkerData(
            id: '$deviceId',
            position: LatLng(p.latitude, p.longitude),
            isSelected: selectedIds.contains(deviceId),
            meta: {
              'name': name,
              'speed': p.speed,
              'course': p.course,
            },
          ),
        );
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
        markers.add(
          MapMarkerData(
            id: '$deviceId',
            position: LatLng(lat!, lon!),
            isSelected: selectedIds.contains(deviceId),
            meta: {'name': name},
          ),
        );
      }
    }

    // Final validation
    markers
        .removeWhere((m) => !_valid(m.position.latitude, m.position.longitude));
    return markers;
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
