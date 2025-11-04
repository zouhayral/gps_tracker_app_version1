import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:my_app_gps/features/map/data/position_model.dart';

/// MarkerUpdateScheduler
///
/// Debounced, conditional scheduler that coalesces incoming device updates and
/// skips triggering expensive marker work when there is no effective change.
///
/// - Debounce: waits for [debounce] before flushing a batch
/// - Coalesce: merges device maps by id, last write wins
/// - Conditional: computes a lightweight signature of positions/selection/query
///   and skips if unchanged since the last trigger
/// - Logging: optional verbose logs to reduce "Scheduling marker update" spam
class MarkerUpdateScheduler {
  MarkerUpdateScheduler({
    required Duration debounce,
    required this.onTrigger,
    bool verbose = false,
    this.positionPrecisionE5 = 5, // ~1e-5 deg precision (~1.1m at equator)
  })  : _debounce = debounce,
        _verbose = verbose;

  Duration _debounce;
  final void Function(List<Map<String, dynamic>> mergedDevices) onTrigger;
  bool _verbose;
  final int positionPrecisionE5;

  Timer? _timer;
  final Map<int, Map<String, dynamic>> _buffer = <int, Map<String, dynamic>>{};

  // Store the latest context so we can safely re-arm timers when debounce changes.
  Map<int, Position> _pendingPositions = const {};
  Set<int> _pendingSelectedIds = const {};
  String _pendingQuery = '';

  int? _lastSignature;
  String _lastSelSig = '';
  String _lastQuery = '';

  /// Schedule a marker update with diff-based change detection.
  void schedule({
    required List<Map<String, dynamic>> devices,
    required Map<int, Position> positions,
    required Set<int> selectedIds,
    required String query,
  }) {
    // Merge incoming devices
    for (final d in devices) {
      final id = d['id'] as int?;
      if (id != null) _buffer[id] = d;
    }

    // Update pending context for this batch
    _pendingPositions = positions;
    _pendingSelectedIds = selectedIds;
    _pendingQuery = query;

    // Restart debounce timer with current settings
    _startTimer();
  }

  void cancel() {
    _timer?.cancel();
    _buffer.clear();
  }

  /// Update debounce duration dynamically.
  /// Cancels any pending timer and re-arms with the new interval to ensure
  /// thread-safe behavior and timely adaptation.
  void updateDebounce(Duration newDebounce) {
    if (newDebounce == _debounce) return;
    _debounce = newDebounce;
    if (_timer?.isActive == true) {
      _startTimer();
    }
  }

  /// Toggle verbose logging.
  void setVerbose(bool value) {
    _verbose = value;
  }

  // --- Helpers -----------------------------------------------------------------

  int _computeSignature(
    Map<int, Position> positions,
    Set<int> selectedIds,
    String query,
  ) {
    // Rolling hash over truncated lat/lon and a small subset of motion fields.
    var h = 17;
    // Include number of entries to quickly detect cardinality changes
    h = 37 * h + positions.length;

    // We only sample stable subsets to avoid noisy hashes.
    positions.forEach((id, p) {
      final latE5 = (p.latitude * 1e5).round();
      final lonE5 = (p.longitude * 1e5).round();
      final sp = p.speed.round(); // coarse speed
      final crs = p.course.round(); // coarse heading
      h = 37 * h + id;
      h = 37 * h + latE5;
      h = 37 * h + lonE5;
      h = 37 * h + sp;
      h = 37 * h + crs;
    });

    // Bake in selection/query as part of signature
    h = 37 * h + _selectionSignature(selectedIds).hashCode;
    h = 37 * h + query.trim().toLowerCase().hashCode;
    return h;
  }

  String _selectionSignature(Set<int> selected) {
    if (selected.isEmpty) return '';
    final ids = selected.toList()..sort();
    return ids.join(',');
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer(_debounce, _flush);
  }

  void _flush() {
    final merged = _buffer.values.toList(growable: false);
    _buffer.clear();

    // Compute signature and conditionally skip
    final sig = _computeSignature(_pendingPositions, _pendingSelectedIds, _pendingQuery);
    final selSig = _selectionSignature(_pendingSelectedIds);
    final q = _pendingQuery.trim().toLowerCase();

    final noChange = (_lastSignature != null && sig == _lastSignature) &&
        selSig == _lastSelSig &&
        q == _lastQuery;

    if (noChange) {
      if (_verbose && kDebugMode) {
        debugPrint('[MarkerScheduler] ⏭️ Skipped scheduling (no effective change)');
      }
      return;
    }

    _lastSignature = sig;
    _lastSelSig = selSig;
    _lastQuery = q;

    if (_verbose && kDebugMode) {
      debugPrint('[MarkerScheduler] 🚀 Triggering marker update for ${merged.length} devices');
    }
    onTrigger(merged);
  }
}
