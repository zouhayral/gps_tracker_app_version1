import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_app_gps/repositories/trip_repository.dart';
import 'package:my_app_gps/features/trips/debug/trip_metrics.dart';
import 'package:my_app_gps/features/trips/debug/trip_adaptive_insights.dart';

/// Global debug flag; set to false to disable overlay in debug builds.
const bool _showTripCacheOverlay = true;
const bool _showAdaptiveInsights = true;

/// A floating diagnostics overlay that displays TripRepository cache metrics.
class TripCacheOverlay extends ConsumerStatefulWidget {
  const TripCacheOverlay({super.key});

  static OverlayEntry? _entry;

  /// Attach the overlay to the nearest Overlay in [context].
  /// Safe to call multiple times; it will attach only once.
  static void attach(BuildContext context) {
    if (!kDebugMode) return;
    if (!_showTripCacheOverlay) return;
    if (_entry != null) return;
  final overlay = Overlay.of(context);
  _entry = OverlayEntry(builder: (ctx) => const TripCacheOverlay());
  overlay.insert(_entry!);
  }

  /// Remove the overlay if attached.
  static void detach() {
    _entry?.remove();
    _entry = null;
  }

  @override
  ConsumerState<TripCacheOverlay> createState() => _TripCacheOverlayState();
}

class _TripCacheOverlayState extends ConsumerState<TripCacheOverlay> {
  bool _minimized = false;
  bool _timelineMode = false;
  bool _insightsMode = false;

  @override
  Widget build(BuildContext context) {
    final metricsAsync = ref.watch(tripCacheMetricsProvider);
    final samples = ref.watch(tripPerfTimelineProvider);

    Widget content(TripCacheMetrics m) {
      final reusePct = (m.reuseRate * 100).toStringAsFixed(1);
      return Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.6),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.memory_rounded, size: 14, color: Colors.white70),
                const SizedBox(width: 6),
                const Text(
                  'Trip Cache Diagnostics',
                  style: TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w600),
                ),
                const SizedBox(width: 8),
                InkWell(
                  onTap: () => setState(() => _minimized = true),
                  child: const Icon(Icons.close, size: 14, color: Colors.white70),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text('Hits: ${m.hits}', style: const TextStyle(color: Colors.greenAccent, fontSize: 12)),
            Text('Misses: ${m.misses}', style: const TextStyle(color: Colors.orangeAccent, fontSize: 12)),
            Text('Reuse: ${m.reuse} ($reusePct%)', style: const TextStyle(color: Colors.cyanAccent, fontSize: 12)),
          ],
        ),
      );
    }

    Widget minimizedButton() {
      return FloatingActionButton.small(
        heroTag: 'trip-cache-overlay-toggle',
        onPressed: () => setState(() => _minimized = false),
        backgroundColor: Colors.black.withOpacity(0.6),
        shape: const CircleBorder(),
        child: const Text('🧩', style: TextStyle(fontSize: 16)),
      );
    }

    return IgnorePointer(
      ignoring: false,
      child: SafeArea(
        child: Stack(
          children: [
            Positioned(
              right: 12,
              bottom: 12,
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 150),
                child: _minimized
                    ? minimizedButton()
                    : Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.6),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.memory_rounded, size: 14, color: Colors.white70),
                                const SizedBox(width: 6),
                                Text(
                                  _timelineMode ? 'Performance Timeline' : 'Trip Cache Diagnostics',
                                  style: const TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w600),
                                ),
                                const SizedBox(width: 8),
                                TextButton(
                                  onPressed: () => setState(() { _timelineMode = false; _insightsMode = false; }),
                                  style: TextButton.styleFrom(minimumSize: const Size(0, 28), padding: const EdgeInsets.symmetric(horizontal: 6)),
                                  child: Text('Live', style: TextStyle(color: _timelineMode ? Colors.white54 : Colors.white)),
                                ),
                                TextButton(
                                  onPressed: () => setState(() { _timelineMode = true; _insightsMode = false; }),
                                  style: TextButton.styleFrom(minimumSize: const Size(0, 28), padding: const EdgeInsets.symmetric(horizontal: 6)),
                                  child: Text('Timeline', style: TextStyle(color: _timelineMode ? Colors.cyanAccent : Colors.white54)),
                                ),
                                if (_showAdaptiveInsights) ...[
                                  TextButton(
                                    onPressed: () => setState(() { _timelineMode = false; _insightsMode = true; }),
                                    style: TextButton.styleFrom(minimumSize: const Size(0, 28), padding: const EdgeInsets.symmetric(horizontal: 6)),
                                    child: Text('Insights', style: TextStyle(color: _insightsMode ? Colors.cyanAccent : Colors.white54)),
                                  ),
                                ],
                                const SizedBox(width: 6),
                                IconButton(
                                  onPressed: () {
                                    // Clear timeline buffer
                                    final notifier = ref.read(tripPerfTimelineProvider.notifier);
                                    notifier.state = const <TripPerfSample>[];
                                  },
                                  icon: const Icon(Icons.clear_all, size: 16, color: Colors.white70),
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(),
                                ),
                                const SizedBox(width: 6),
                                InkWell(
                                  onTap: () => setState(() => _minimized = true),
                                  child: const Icon(Icons.close, size: 14, color: Colors.white70),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            if (_timelineMode)
                              SizedBox(
                                width: 280,
                                height: 140,
                                child: _TimelineChart(samples: samples),
                              )
                            else
                              (_insightsMode && _showAdaptiveInsights)
                                  ? _InsightsPanel()
                                  : metricsAsync.when(
                                      data: (m) => content(m),
                                      loading: () => const SizedBox(
                                        width: 90,
                                        height: 36,
                                        child: Center(
                                          child: CircularProgressIndicator(
                                            strokeWidth: 1.6,
                                            valueColor: AlwaysStoppedAnimation<Color>(Colors.white70),
                                          ),
                                        ),
                                      ),
                                      error: (e, _) => const Text('Trip Cache: error', style: TextStyle(color: Colors.redAccent)),
                                    ),
                          ],
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _InsightsPanel extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final report = ref.watch(adaptiveInsightsProvider);
    final insights = report.insights;
    if (insights.isEmpty) {
      return const SizedBox(
        width: 280,
        child: Text('No insights yet', style: TextStyle(color: Colors.white70, fontSize: 12)),
      );
    }
    return AnimatedSize(
      duration: const Duration(milliseconds: 150),
      child: SizedBox(
        width: 280,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final i in insights)
              ListTile(
                dense: true,
                leading: Icon(Icons.lightbulb, color: i.color, size: 16),
                title: Text(
                  i.message,
                  style: TextStyle(color: i.color, fontSize: 13),
                ),
                contentPadding: EdgeInsets.zero,
                minLeadingWidth: 18,
                visualDensity: const VisualDensity(horizontal: -4, vertical: -4),
              ),
          ],
        ),
      ),
    );
  }
}

class _TimelineChart extends StatelessWidget {
  const _TimelineChart({required this.samples});
  final List<TripPerfSample> samples;

  @override
  Widget build(BuildContext context) {
    if (samples.isEmpty) {
      return const Center(
        child: Text('No samples', style: TextStyle(color: Colors.white70, fontSize: 12)),
      );
    }
    return CustomPaint(
      painter: _ChartPainter(samples),
    );
  }
}

class _ChartPainter extends CustomPainter {
  _ChartPainter(this.samples);
  final List<TripPerfSample> samples;

  @override
  void paint(Canvas canvas, Size size) {
    final bg = Paint()..color = Colors.transparent;
    canvas.drawRect(Offset.zero & size, bg);

    // Padding for labels
    const left = 4.0;
    const right = 4.0;
    const top = 4.0;
    const bottom = 14.0;
    final chartRect = Rect.fromLTWH(left, top, size.width - left - right, size.height - top - bottom);

    // Compute max for scaling
    double maxY = 0;
    for (final s in samples) {
      maxY = [maxY, s.parseDurationMs, s.cacheHits.toDouble(), s.cacheMisses.toDouble(), s.reuse.toDouble()].reduce((a, b) => a > b ? a : b);
    }
    if (maxY <= 0) maxY = 1;

    // Draw gridlines (4)
    final gridPaint = Paint()
      ..color = Colors.white12
      ..strokeWidth = 1;
    for (int i = 0; i <= 4; i++) {
      final y = chartRect.top + chartRect.height * (i / 4);
      canvas.drawLine(Offset(chartRect.left, y), Offset(chartRect.right, y), gridPaint);
    }

    Path toPath(List<double> ys) {
      final path = Path();
      for (int i = 0; i < ys.length; i++) {
        final x = chartRect.left + chartRect.width * (i / (ys.length - 1).clamp(1, ys.length));
        final v = ys[i];
        final y = chartRect.bottom - (v / maxY) * chartRect.height;
        if (i == 0) {
          path.moveTo(x, y);
        } else {
          path.lineTo(x, y);
        }
      }
      return path;
    }

    void drawSeries(List<double> ys, Color color) {
      final path = toPath(ys);
      final paint = Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5;
      canvas.drawPath(path, paint);
    }

    final parse = samples.map((s) => s.parseDurationMs).toList();
    final hits = samples.map((s) => s.cacheHits.toDouble()).toList();
    final misses = samples.map((s) => s.cacheMisses.toDouble()).toList();
    final reuse = samples.map((s) => s.reuse.toDouble()).toList();

    drawSeries(parse, Colors.lightBlueAccent);
    drawSeries(hits, Colors.greenAccent);
    drawSeries(misses, Colors.orangeAccent);
    drawSeries(reuse, Colors.cyanAccent);

    // Legend
    final tp = (String t, Color c) => TextPainter(
          text: TextSpan(text: t, style: TextStyle(color: c, fontSize: 10)),
          textDirection: TextDirection.ltr,
        )..layout();
    final l1 = tp('ms', Colors.lightBlueAccent);
    final l2 = tp('hit', Colors.greenAccent);
    final l3 = tp('miss', Colors.orangeAccent);
    final l4 = tp('reuse', Colors.cyanAccent);
    double x = chartRect.left;
    final y = chartRect.bottom + 2;
    for (final t in [l1, l2, l3, l4]) {
      t.paint(canvas, Offset(x, y));
      x += t.width + 8;
    }
  }

  @override
  bool shouldRepaint(covariant _ChartPainter oldDelegate) {
    return !identical(oldDelegate.samples, samples) || oldDelegate.samples.length != samples.length;
  }
}
