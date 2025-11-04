import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:my_app_gps/core/data/vehicle_data_snapshot.dart';
import 'package:my_app_gps/core/utils/adaptive_render.dart';
import 'package:my_app_gps/core/utils/app_logger.dart';
import 'package:my_app_gps/core/utils/stream_memoizer.dart';
import 'package:my_app_gps/features/map/data/position_model.dart';

/// Lifecycle tracking wrapper for per-device position streams.
/// 
/// **Purpose:** Track listener count and last access time for idle stream cleanup.
class StreamEntry {
  final StreamController<Position?> controller;
  int listenerCount = 0;
  DateTime lastAccess = DateTime.now();

  StreamEntry(this.controller);

  void incrementListeners() {
    listenerCount++;
    lastAccess = DateTime.now();
  }

  void decrementListeners() {
    listenerCount--;
    lastAccess = DateTime.now();
  }

  void refreshAccess() => lastAccess = DateTime.now();

  bool get isIdle => listenerCount == 0;
  Duration get idleTime => DateTime.now().difference(lastAccess);
}

/// Service responsible for position streams and WebSocket integration.
/// 
/// **Responsibilities:**
/// - Per-device position stream management
/// - Stream lifecycle tracking and cleanup
/// - LRU eviction and memory management
/// - Adaptive backpressure based on LOD
/// - Stream memoization
/// - Position broadcast to active streams
/// 
/// **Extracted from:** VehicleDataRepository (lines ~85-113, ~230-264, ~1150-1395)
class VehicleDataStreamService {
  static final _log = 'VehicleStreamSvc'.logger;

  VehicleDataStreamService();

  // Per-device position streams
  final Map<int, StreamEntry> _deviceStreams = {};
  final Map<int, Position?> _latestPositions = {};

  // Stream memoization & lifecycle management
  final _streamMemoizer = StreamMemoizer<Position?>();

  // Stream backpressure: Adaptive throttling based on LOD mode
  final Map<int, DateTime> _lastEmit = {};
  final Map<int, VehicleDataSnapshot> _pendingUpdates = {};
  int _coalescedCount = 0;
  AdaptiveLodController? _lodController;

  // Stream cleanup timer
  Timer? _streamCleanupTimer;
  bool _isDisposed = false;

  // Test-mode flag to disable background timers in widget tests
  static bool testMode = false;

  // Configuration constants
  static const _kIdleTimeout = Duration(minutes: 1);
  static const _kMaxStreams = 500;
  static const _kCleanupInterval = Duration(seconds: 60);

  /// Set the LOD controller for adaptive backpressure
  void setLodController(AdaptiveLodController? controller) {
    _lodController = controller;
    _log.debug('[Backpressure] LOD controller ${controller != null ? 'attached' : 'detached'}');
  }

  /// Get emit gap duration based on current LOD mode
  Duration _emitGap() {
    final mode = _lodController?.mode ?? RenderMode.high;
    return switch (mode) {
      RenderMode.high => const Duration(milliseconds: 33),   // ~30 Hz
      RenderMode.medium => const Duration(milliseconds: 66), // ~15 Hz
      RenderMode.low => const Duration(milliseconds: 120),   // ~8 Hz
    };
  }

  /// Broadcast position update to device-specific stream
  void broadcastPositionUpdate(
    VehicleDataSnapshot snapshot, {
    bool useBackpressure = true,
  }) {
    final position = snapshot.position;
    final deviceId = snapshot.deviceId;
    
    // Update latest position cache
    _latestPositions[deviceId] = position;
    
    if (useBackpressure) {
      // Apply adaptive backpressure
      _broadcastWithBackpressure(snapshot);
    } else {
      // Direct broadcast without backpressure
      _directBroadcast(deviceId, position);
    }
  }

  /// Broadcast with adaptive backpressure
  void _broadcastWithBackpressure(VehicleDataSnapshot snapshot) {
    final deviceId = snapshot.deviceId;
    final now = DateTime.now();
    final gap = _emitGap();
    final lastEmit = _lastEmit[deviceId];

    // Check if we're within throttle window
    if (lastEmit != null && now.difference(lastEmit) < gap) {
      // Coalesce: Store latest update, discard previous pending
      final hadPending = _pendingUpdates.containsKey(deviceId);
      _pendingUpdates[deviceId] = snapshot;
      
      if (hadPending) {
        _coalescedCount++;
        if (kDebugMode && _coalescedCount % 10 == 0) {
          _log.debug('[Backpressure] Coalesced $_coalescedCount updates (device $deviceId)');
        }
      }

      // Schedule delayed emission after gap expires
      Future.delayed(gap, () {
        final pending = _pendingUpdates.remove(deviceId);
        if (pending != null && !_isDisposed) {
          _directBroadcast(deviceId, pending.position);
          _lastEmit[deviceId] = DateTime.now();
        }
      });
      
      return; // Skip immediate emission
    }

    // Emit immediately if gap has passed
    _directBroadcast(deviceId, snapshot.position);
    _lastEmit[deviceId] = now;
  }

  /// Direct broadcast to stream (no backpressure)
  void _directBroadcast(int deviceId, Position? position) {
    // Defer stream broadcast to microtask queue
    // This shifts emissions after current UI work completes, preventing frame jank
    Future.microtask(() {
      final entry = _deviceStreams[deviceId];
      if (entry != null && !entry.controller.isClosed && entry.controller.hasListener) {
        entry.controller.add(position);
        entry.refreshAccess();
        _log.debug('📡 Position broadcast to stream for device $deviceId (listeners: ${entry.listenerCount})');
      }
    });
  }

  /// Get a reactive stream of position updates for a specific device.
  Stream<Position?> positionStream(int deviceId) {
    // Proactive LRU eviction BEFORE creating new stream
    if (_deviceStreams.length >= _kMaxStreams && !_deviceStreams.containsKey(deviceId)) {
      _evictLRUStream();
      _log.debug('⚠️ Proactive LRU eviction triggered (limit: $_kMaxStreams, current: ${_deviceStreams.length})');
    }
    
    // Use StreamMemoizer to cache streams and prevent duplicates
    return _streamMemoizer.memoize(
      'device_$deviceId',
      () {
        // Lazy-create stream entry with lifecycle tracking
        final entry = _deviceStreams.putIfAbsent(
          deviceId,
          () {
            final controller = StreamController<Position?>.broadcast(
              sync: true, // Synchronous delivery for immediate UI updates
              onListen: () {
                final entry = _deviceStreams[deviceId];
                if (entry != null) {
                  entry.incrementListeners();
                  _log.debug('📡 Stream listener added for device $deviceId (count: ${entry.listenerCount})');
                }
              },
              onCancel: () {
                final entry = _deviceStreams[deviceId];
                if (entry != null) {
                  entry.decrementListeners();
                  _log.debug('📡 Stream listener removed for device $deviceId (count: ${entry.listenerCount})');
                }
              },
            );
            return StreamEntry(controller);
          },
        );

        // Start cleanup timer if not already running
        _startStreamCleanupTimer();

        // Return stream with access time refresh on every emission
        return entry.controller.stream.transform(
          StreamTransformer<Position?, Position?>.fromHandlers(
            handleData: (position, sink) {
              final e = _deviceStreams[deviceId];
              e?.refreshAccess();
              sink.add(position);
            },
          ),
        );
      },
    );
  }

  /// Get the latest known position for a device synchronously
  Position? getLatestPosition(int deviceId) => _latestPositions[deviceId];

  /// Get all latest positions as an unmodifiable map
  Map<int, Position?> getAllLatestPositions() =>
      Map<int, Position?>.unmodifiable(_latestPositions);

  /// Load cached positions into latest positions map
  void loadCachedPositions(Map<int, Position?> cached) {
    _latestPositions.addAll(cached);
  }

  /// Start periodic cleanup timer for idle streams
  void _startStreamCleanupTimer() {
    if (_streamCleanupTimer != null || testMode) return;
    
    _streamCleanupTimer = Timer.periodic(_kCleanupInterval, (_) {
      _cleanupIdleStreams();
      _capStreamsIfNeeded();
    });
    
    _log.debug('🧹 Stream cleanup timer started (interval: ${_kCleanupInterval.inSeconds}s)');
  }

  /// Clean up idle streams (0 listeners + >1 min since last access)
  void _cleanupIdleStreams() {
    final toRemove = <int>[];
    
    for (final entry in _deviceStreams.entries) {
      final deviceId = entry.key;
      final streamEntry = entry.value;
      
      if (streamEntry.isIdle && streamEntry.idleTime > _kIdleTimeout) {
        toRemove.add(deviceId);
      }
    }
    
    if (toRemove.isEmpty) {
      _log.debug('🧹 No idle streams to clean up (active: ${_deviceStreams.length})');
      return;
    }
    
    // Enhanced logging with memory impact estimate
    final memoryFreedEstimate = toRemove.length * 5; // ~5KB per stream
    debugPrint('[STREAM_CLEANUP] 🧹 Cleaning ${toRemove.length} idle streams');
    debugPrint('[STREAM_CLEANUP] 📊 Est. memory freed: ~${memoryFreedEstimate}KB');
    debugPrint('[STREAM_CLEANUP] 📈 Streams before: ${_deviceStreams.length}, after: ${_deviceStreams.length - toRemove.length}');
    
    for (final deviceId in toRemove) {
      final entry = _deviceStreams[deviceId];
      if (entry != null) {
        final idleDuration = entry.idleTime;
        debugPrint('[STREAM_CLEANUP] 🗑️ Evicting device $deviceId (idle: ${idleDuration.inMinutes}m ${idleDuration.inSeconds % 60}s)');
      }
      entry?.controller.close();
      _deviceStreams.remove(deviceId);
      _latestPositions.remove(deviceId);
      _streamMemoizer.clear(); // Clear memoization cache
    }
    
    _log.debug('🧹 Cleaned up ${toRemove.length} idle streams (remaining: ${_deviceStreams.length})');
  }

  /// Cap streams using LRU eviction when exceeding max limit
  void _capStreamsIfNeeded() {
    if (_deviceStreams.length <= _kMaxStreams) return;
    
    // Get all idle streams sorted by last access time (oldest first)
    final idleStreams = _deviceStreams.entries
        .where((e) => e.value.isIdle)
        .toList()
      ..sort((a, b) => a.value.lastAccess.compareTo(b.value.lastAccess));
    
    final toEvict = _deviceStreams.length - _kMaxStreams;
    final evicted = <int>[];
    
    debugPrint('[STREAM_CAP] 🔒 Stream limit exceeded (current: ${_deviceStreams.length}, max: $_kMaxStreams)');
    debugPrint('[STREAM_CAP] 📊 Idle streams available: ${idleStreams.length}, need to evict: $toEvict');
    
    for (final entry in idleStreams.take(toEvict)) {
      final deviceId = entry.key;
      debugPrint('[STREAM_CAP] 🗑️ Evicting device $deviceId (idle: ${entry.value.idleTime.inMinutes}m)');
      entry.value.controller.close();
      _deviceStreams.remove(deviceId);
      _latestPositions.remove(deviceId);
      evicted.add(deviceId);
    }
    
    if (evicted.isNotEmpty) {
      _streamMemoizer.clear();
      final memoryFreedEstimate = evicted.length * 5; // ~5KB per stream
      debugPrint('[STREAM_CAP] ✅ Evicted ${evicted.length} streams, freed ~${memoryFreedEstimate}KB');
      _log.debug('🔒 Evicted ${evicted.length} streams (LRU cap: $_kMaxStreams)');
    }
  }

  /// Proactive single-stream LRU eviction
  void _evictLRUStream() {
    // Find oldest idle stream
    MapEntry<int, StreamEntry>? oldestIdle;
    
    for (final entry in _deviceStreams.entries) {
      if (entry.value.isIdle) {
        if (oldestIdle == null || entry.value.lastAccess.isBefore(oldestIdle.value.lastAccess)) {
          oldestIdle = entry;
        }
      }
    }
    
    // If found, evict it
    if (oldestIdle != null) {
      final deviceId = oldestIdle.key;
      final idleDuration = oldestIdle.value.idleTime;
      
      debugPrint('[PROACTIVE_EVICT] 🗑️ Evicting device $deviceId (idle: ${idleDuration.inMinutes}m ${idleDuration.inSeconds % 60}s)');
      debugPrint('[PROACTIVE_EVICT] 📊 Streams: ${_deviceStreams.length} → ${_deviceStreams.length - 1} (limit: $_kMaxStreams)');
      
      oldestIdle.value.controller.close();
      _deviceStreams.remove(deviceId);
      _latestPositions.remove(deviceId);
      _streamMemoizer.clear();
      
      _log.debug('🗑️ Proactive LRU eviction: device $deviceId (idle for ${oldestIdle.value.idleTime.inMinutes}m)');
    } else {
      debugPrint('[PROACTIVE_EVICT] ⚠️ Cannot evict: all ${_deviceStreams.length} streams have active listeners');
      _log.warning('⚠️ Cannot evict: all ${_deviceStreams.length} streams have active listeners');
    }
  }

  /// Get stream lifecycle diagnostics
  Map<String, dynamic> getStreamDiagnostics() {
    final activeStreams = _deviceStreams.values.where((e) => !e.isIdle).length;
    final idleStreams = _deviceStreams.values.where((e) => e.isIdle).length;
    final totalListeners = _deviceStreams.values.fold<int>(
      0,
      (sum, entry) => sum + entry.listenerCount,
    );
    
    return {
      'totalStreams': _deviceStreams.length,
      'activeStreams': activeStreams,
      'idleStreams': idleStreams,
      'totalListeners': totalListeners,
      'positionsCached': _latestPositions.length,
      'streamMemoizerStats': _streamMemoizer.getStats(),
      'backpressure': {
        'coalescedCount': _coalescedCount,
        'pendingUpdates': _pendingUpdates.length,
        'emitGapMs': _emitGap().inMilliseconds,
        'lodMode': _lodController?.mode.name ?? 'none',
      },
    };
  }

  /// Dispose resources
  void dispose() {
    if (_isDisposed) return;
    _isDisposed = true;

    _streamCleanupTimer?.cancel();
    
    // Clear pending updates
    _pendingUpdates.clear();
    _lastEmit.clear();
    
    if (kDebugMode && _coalescedCount > 0) {
      _log.debug('[Backpressure] Total coalesced updates: $_coalescedCount');
    }

    // Close all per-device position streams
    for (final entry in _deviceStreams.values) {
      entry.controller.close();
    }
    _deviceStreams.clear();
    _latestPositions.clear();

    _log.debug('Stream service disposed');
  }
}
