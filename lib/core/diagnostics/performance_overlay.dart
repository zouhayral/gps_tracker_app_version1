import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_app_gps/core/diagnostics/performance_metrics_service.dart';

final performanceOverlayVisibleProvider = StateProvider<bool>((ref) => true);

class PerformanceOverlayWidget extends ConsumerStatefulWidget {
  const PerformanceOverlayWidget({super.key});

  @override
  ConsumerState<PerformanceOverlayWidget> createState() => _PerformanceOverlayWidgetState();
}

class _PerformanceOverlayWidgetState extends ConsumerState<PerformanceOverlayWidget> {
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    // Start sampling by ensuring service is running
    final svc = ref.read(performanceMetricsServiceProvider);
    svc.start();

    // Listen to hardware keyboard events for a toggle (Ctrl+P)
    HardwareKeyboard.instance.addHandler(_hardwareKeyHandler);
  }

  bool _hardwareKeyHandler(KeyEvent event) {
    try {
      if (event is KeyDownEvent) {
        final isCtrl = HardwareKeyboard.instance.physicalKeysPressed
            .contains(PhysicalKeyboardKey.controlLeft) ||
            HardwareKeyboard.instance.physicalKeysPressed
            .contains(PhysicalKeyboardKey.controlRight);
        if (isCtrl && event.logicalKey == LogicalKeyboardKey.keyP) {
          final cur = ref.read(performanceOverlayVisibleProvider);
          ref.read(performanceOverlayVisibleProvider.notifier).state = !cur;
          return true;
        }
      }
    } catch (_) {
      // ignore on platforms without hardware keyboard
    }
    return false;
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_hardwareKeyHandler);
    _tick?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final visible = ref.watch(performanceOverlayVisibleProvider);
    if (!visible || !kDebugMode) return const SizedBox.shrink();

    final svc = ref.watch(performanceMetricsServiceProvider);
    return Positioned(
      left: 12,
      top: 12,
      child: ValueListenableBuilder<Map<String, dynamic>>(
        valueListenable: svc.latestMetrics,
        builder: (context, metrics, _) {
          final fpsVal = metrics['fps'] ?? 0;
          final fps = (fpsVal is num) ? fpsVal.toStringAsFixed(1) : fpsVal.toString();
          final memVal = metrics['mem_mb'];
          final mem = (memVal is num) ? '${(memVal.toDouble()).toStringAsFixed(0)} MB' : 'N/A';
          final markers = metrics['marker_count']?.toString() ?? '-';
          return Material(
            color: Colors.black.withValues(alpha: 0.5),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('FPS: $fps', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                  const SizedBox(width: 12),
                  Text('Mem: $mem', style: const TextStyle(color: Colors.white)),
                  const SizedBox(width: 12),
                  Text('Markers: $markers', style: const TextStyle(color: Colors.white)),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
