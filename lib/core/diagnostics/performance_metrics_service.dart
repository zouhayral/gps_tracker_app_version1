import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_app_gps/core/diagnostics/diagnostics_config.dart';
import 'package:my_app_gps/core/diagnostics/frame_metrics_logger.dart';

/// Provider to toggle overlay visibility/logging
final performanceOverlayEnabledProvider = StateProvider<bool>((ref) => true);

final performanceMetricsServiceProvider =
    Provider<PerformanceMetricsService>((ref) {
  final s = PerformanceMetricsService();
  ref.onDispose(s.dispose);
  return s;
});

class PerformanceMetricsService {
  PerformanceMetricsService();

  Timer? _sampleTimer;
  Timer? _csvTimer;
  bool _isRunning = false;

  // Latest metrics exposed to UI
  final ValueNotifier<Map<String, dynamic>> latestMetrics = ValueNotifier({});

  // Optional supplier to read marker count from map page
  int Function()? _markerCountSupplier;

  /// Start sampling metrics. Updates latestMetrics frequently and writes CSV every 5s
  void start(
      {Duration sampleInterval = const Duration(seconds: 1),
      Duration csvInterval = const Duration(seconds: 5),}) {
    if (_isRunning) return;
    _isRunning = true;

    // Ensure frame metrics collection is active
    FrameMetricsLogger.instance.reset();
    FrameMetricsLogger.instance.start();

    // If running inside flutter widget tests (AutomatedTestWidgetsFlutterBinding) we avoid
    // creating periodic timers because FakeAsync in tests will complain about pending timers
    // after the widget tree is torn down. Detect the test binding by checking the binding's
    // runtimeType string (the test binding types are only present during widget tests).
    final bindingName = WidgetsBinding.instance.runtimeType.toString();
    final inWidgetTest =
        bindingName.contains('AutomatedTestWidgetsFlutterBinding') ||
            bindingName.contains('TestWidgetsFlutterBinding');

    // Frequent sampling for overlay
    if (!inWidgetTest) {
      _sampleTimer = Timer.periodic(sampleInterval, (_) => _sample());

      // CSV exporter: only run on desktop platforms to avoid writing into
      // mobile sandboxed file systems which may throw FileSystemException.
      _csvTimer = Timer.periodic(csvInterval, (_) async {
        try {
          if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
            await _exportCsv();
          } else {
            if (kDebugMode && DiagnosticsConfig.enablePerfLogs) {
              debugPrint(
                  '[PerfMetrics] Skipping CSV export on mobile (sandboxed FS)',);
            }
          }
        } catch (e) {
          if (kDebugMode && DiagnosticsConfig.enablePerfLogs) {
            debugPrint('[PerfMetrics] CSV export skipped/error: $e');
          }
        }
      });
    } else {
      // In tests, do a one-off sample so the UI can read something without scheduling timers
      _sample();
    }
  }

  void stop() {
    if (!_isRunning) return;
    _isRunning = false;
    _sampleTimer?.cancel();
    _csvTimer?.cancel();
    FrameMetricsLogger.instance.stop();
  }

  void dispose() {
    stop();
    latestMetrics.dispose();
  }

  // Intentional explicit getter/setter pair for API clarity used across the app.
  // ignore: unnecessary_getters_setters
  set markerCountSupplier(int Function()? supplier) {
    _markerCountSupplier = supplier;
  }
  // ignore: unnecessary_getters_setters
  int Function()? get markerCountSupplier => _markerCountSupplier;

  Map<String, dynamic> _collectSnapshot() {
    final fm = FrameMetricsLogger.instance;
    final exported = fm.exportMetrics();

    final memBytes = _safeCurrentRss();
    final memMb = memBytes != null ? (memBytes / (1024 * 1024)) : null;

  final markers = _markerCountSupplier?.call();

    final now = DateTime.now().toUtc().toIso8601String();

    return {
      'timestamp': now,
      'avg_frame_ms': exported['averageFrameTime'],
      'p95_frame_ms': exported['p95FrameTime'],
      'p99_frame_ms': exported['p99FrameTime'],
      'jank_count': exported['jankCount'],
      'fps': exported['estimatedFps'],
      'mem_mb': memMb,
      'marker_count': markers,
    };
  }

  void _sample() {
    try {
      final snap = _collectSnapshot();
      latestMetrics.value = Map<String, dynamic>.from(snap);
    } catch (e, st) {
      if (kDebugMode && DiagnosticsConfig.enablePerfLogs) {
        debugPrint('[PerfMetrics] sample error: $e');
      }
      if (kDebugMode) debugPrintStack(stackTrace: st);
    }
  }

  // ignore: avoid_slow_async_io
  Future<void> _exportCsv() async {
    try {
      final snap = _collectSnapshot();
      final csvLine = _toCsvLine(snap);

  final file = await _openLogFile();
  // ignore: avoid_slow_async_io
  final exists = await file.exists();
      if (!exists) {
        await file.writeAsString('${_csvHeader()}\n');
      }
      await file.writeAsString('$csvLine\n', mode: FileMode.append);
      if (kDebugMode && DiagnosticsConfig.enablePerfLogs) {
        debugPrint('[PerfMetrics] CSV row appended');
      }
    } catch (e, st) {
      if (kDebugMode && DiagnosticsConfig.enablePerfLogs) {
        debugPrint('[PerfMetrics] export error: $e');
      }
      if (kDebugMode) debugPrintStack(stackTrace: st);
    }
  }

  String _csvHeader() =>
      'timestamp,avg_frame_ms,p95_frame_ms,p99_frame_ms,jank_count,fps,mem_mb,marker_count';

  String _toCsvLine(Map<String, dynamic> snap) {
    final parts = [
      snap['timestamp'] ?? '',
      _formatNum(snap['avg_frame_ms']),
      _formatNum(snap['p95_frame_ms']),
      _formatNum(snap['p99_frame_ms']),
      '${snap['jank_count'] ?? ''}',
      _formatNum(snap['fps']),
      _formatNum(snap['mem_mb']),
      '${snap['marker_count'] ?? ''}',
    ];
    return parts.join(',');
  }

  String _formatNum(dynamic v) {
    if (v == null) return '';
    if (v is num) return v.toStringAsFixed(2);
    return v.toString();
  }

  Future<File> _openLogFile() async {
    final now = DateTime.now();
    final name =
        'perf_log_${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}.csv';
    Directory dir;
    try {
      // Prefer application documents directory if available
      dir = Directory(Directory.current.path);
    } catch (_) {
      dir = Directory.systemTemp;
    }
    // ignore: avoid_slow_async_io
    if (!await dir.exists()) {
      // ignore: avoid_slow_async_io
      await dir.create(recursive: true);
    }
    return File('${dir.path}/$name');
  }

  int? _safeCurrentRss() {
    try {
      return ProcessInfo.currentRss; // bytes
    } catch (_) {
      return null;
    }
  }

  /// Export current collected metrics to JSON file (immediate)
  Future<File?> exportJsonSnapshot() async {
    try {
      final snap = _collectSnapshot();
      final now = DateTime.now();
      final name =
          'perf_snapshot_${now.toIso8601String().replaceAll(':', '-')}.json';
  final file = File('${Directory.current.path}/$name');
  // ignore: avoid_slow_async_io
  await file.writeAsString(jsonEncode(snap));
      return file;
    } catch (e) {
      if (kDebugMode && DiagnosticsConfig.enablePerfLogs) {
        debugPrint('[PerfMetrics] exportJson error: $e');
      }
      return null;
    }
  }
}
