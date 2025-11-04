import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_app_gps/features/geofencing/providers/geofence_providers.dart';

class GeofenceProfilerPanel extends ConsumerWidget {
  const GeofenceProfilerPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!kDebugMode) return const SizedBox.shrink();

    final profAsync = ref.watch(geofenceProfilerProvider);

    return profAsync.when(
      data: (p) {
        final level = _levelFor(p.avgMs);
        final bgColor = Colors.black.withOpacity(0.6);
        final accent = _accentFor(level);

        return AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeInOut,
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: accent.withOpacity(0.5), width: 1),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                '⚡ Evaluation Profiler',
                style: TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 4),
              _metric('Avg', '${p.avgMs.toStringAsFixed(1)} ms', color: accent),
              _metric('Min', '${p.minMs.toStringAsFixed(0)} ms', color: Colors.greenAccent),
              _metric('Max', '${p.maxMs.toStringAsFixed(0)} ms', color: Colors.orangeAccent),
              Text('Samples: ${p.sampleCount}', style: const TextStyle(color: Colors.white54, fontSize: 11)),
            ],
          ),
        );
      },
      loading: () => Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.6),
          borderRadius: BorderRadius.circular(8),
        ),
        child: const SizedBox(
          width: 16,
          height: 16,
          child: CircularProgressIndicator(strokeWidth: 1.6, valueColor: AlwaysStoppedAnimation<Color>(Colors.white70)),
        ),
      ),
      error: (e, _) => Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.6),
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Text('Profiler error', style: TextStyle(color: Colors.redAccent, fontSize: 12)),
      ),
    );
  }

  Widget _metric(String label, String value, {required Color color}) {
    return Text(
      '$label: $value',
      style: TextStyle(color: color, fontSize: 12),
    );
  }

  _Level _levelFor(double avgMs) {
    if (avgMs > 800) return _Level.red;
    if (avgMs > 300) return _Level.yellow;
    if (avgMs < 200) return _Level.green;
    return _Level.normal;
  }

  Color _accentFor(_Level l) {
    switch (l) {
      case _Level.red:
        return Colors.redAccent;
      case _Level.yellow:
        return Colors.amberAccent;
      case _Level.green:
        return Colors.greenAccent;
      case _Level.normal:
        return Colors.cyanAccent;
    }
  }
}

enum _Level { normal, green, yellow, red }
