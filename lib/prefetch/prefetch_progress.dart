/// Prefetch progress tracking
///
/// Emitted by PrefetchOrchestrator to provide real-time download status
library;

import 'package:flutter/foundation.dart';

/// Current state of a prefetch operation
enum PrefetchState {
  /// Idle, no active prefetch
  idle,

  /// Calculating tile ranges
  preparing,

  /// Actively downloading tiles
  downloading,

  /// Paused (e.g., due to offline state)
  paused,

  /// Completed successfully
  completed,

  /// Cancelled by user
  cancelled,

  /// Failed with errors
  failed,
}

/// Progress data for an active prefetch operation
@immutable
class PrefetchProgress {
  /// Current state
  final PrefetchState state;

  /// Tile source being prefetched (osm, esri_sat)
  final String sourceId;

  /// FMTC store name (tiles_osm, tiles_esri_sat)
  final String storeName;

  /// Total tiles queued for download
  final int queuedCount;

  /// Tiles successfully downloaded
  final int completedCount;

  /// Tiles that failed to download
  final int failedCount;

  /// Tiles skipped (already cached)
  final int skippedCount;

  /// Current zoom level being processed
  final int? currentZoom;

  /// Optional error message if state is failed
  final String? errorMessage;

  /// Timestamp when prefetch started
  final DateTime? startTime;

  /// Timestamp when prefetch finished (completed/cancelled/failed)
  final DateTime? endTime;

  const PrefetchProgress({
    this.state = PrefetchState.idle,
    this.sourceId = '',
    this.storeName = '',
    this.queuedCount = 0,
    this.completedCount = 0,
    this.failedCount = 0,
    this.skippedCount = 0,
    this.currentZoom,
    this.errorMessage,
    this.startTime,
    this.endTime,
  });

  /// Initial idle state
  const PrefetchProgress.idle()
      : state = PrefetchState.idle,
        sourceId = '',
        storeName = '',
        queuedCount = 0,
        completedCount = 0,
        failedCount = 0,
        skippedCount = 0,
        currentZoom = null,
        errorMessage = null,
        startTime = null,
        endTime = null;

  /// Percentage complete (0-100)
  double get progressPercent {
    if (queuedCount == 0) return 0.0;
    final processed = completedCount + failedCount + skippedCount;
    return (processed / queuedCount * 100).clamp(0, 100);
  }

  /// Total tiles processed (completed + failed + skipped)
  int get processedCount => completedCount + failedCount + skippedCount;

  /// Remaining tiles to process
  int get remainingCount => queuedCount - processedCount;

  /// Whether prefetch is actively running
  bool get isActive => state == PrefetchState.downloading;

  /// Whether prefetch can be resumed
  bool get canResume => state == PrefetchState.paused;

  /// Whether prefetch is finished (any terminal state)
  bool get isFinished =>
      state == PrefetchState.completed ||
      state == PrefetchState.cancelled ||
      state == PrefetchState.failed;

  /// Elapsed time since start (if started)
  Duration? get elapsedTime {
    if (startTime == null) return null;
    final end = endTime ?? DateTime.now();
    return end.difference(startTime!);
  }

  /// Estimated time remaining based on current rate
  Duration? get estimatedTimeRemaining {
    if (startTime == null || completedCount == 0 || isFinished) return null;

    final elapsed = elapsedTime!;
    final avgTimePerTile = elapsed.inMilliseconds / completedCount;
    final remainingMs = (remainingCount * avgTimePerTile).ceil();

    return Duration(milliseconds: remainingMs);
  }

  /// Download rate in tiles per second
  double get tilesPerSecond {
    if (startTime == null || completedCount == 0) return 0.0;
    final elapsed = elapsedTime!;
    if (elapsed.inMilliseconds == 0) return 0.0;
    return completedCount / (elapsed.inMilliseconds / 1000);
  }

  /// Copy with modified fields
  PrefetchProgress copyWith({
    PrefetchState? state,
    String? sourceId,
    String? storeName,
    int? queuedCount,
    int? completedCount,
    int? failedCount,
    int? skippedCount,
    int? currentZoom,
    String? errorMessage,
    DateTime? startTime,
    DateTime? endTime,
  }) {
    return PrefetchProgress(
      state: state ?? this.state,
      sourceId: sourceId ?? this.sourceId,
      storeName: storeName ?? this.storeName,
      queuedCount: queuedCount ?? this.queuedCount,
      completedCount: completedCount ?? this.completedCount,
      failedCount: failedCount ?? this.failedCount,
      skippedCount: skippedCount ?? this.skippedCount,
      currentZoom: currentZoom ?? this.currentZoom,
      errorMessage: errorMessage ?? this.errorMessage,
      startTime: startTime ?? this.startTime,
      endTime: endTime ?? this.endTime,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PrefetchProgress &&
          runtimeType == other.runtimeType &&
          state == other.state &&
          sourceId == other.sourceId &&
          storeName == other.storeName &&
          queuedCount == other.queuedCount &&
          completedCount == other.completedCount &&
          failedCount == other.failedCount &&
          skippedCount == other.skippedCount &&
          currentZoom == other.currentZoom &&
          errorMessage == other.errorMessage &&
          startTime == other.startTime &&
          endTime == other.endTime;

  @override
  int get hashCode =>
      Object.hash(
        state,
        sourceId,
        storeName,
        queuedCount,
        completedCount,
        failedCount,
        skippedCount,
        currentZoom,
        errorMessage,
        startTime,
        endTime,
      );

  @override
  String toString() =>
      'PrefetchProgress($state: $completedCount/$queuedCount, '
      '${progressPercent.toStringAsFixed(1)}%, '
      '${tilesPerSecond.toStringAsFixed(1)} tiles/s)';
}
