import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'trip_metrics.dart';

class AdaptiveInsight {
  final String message;
  final Color color;
  const AdaptiveInsight(this.message, this.color);
}

class AdaptiveInsightReport {
  final List<AdaptiveInsight> insights;
  const AdaptiveInsightReport(this.insights);
}

class TripAdaptiveInsights {
  static AdaptiveInsightReport compute(
    List<TripPerfSample> samples, {
    int window = 30,
  }) {
    if (samples.isEmpty) return const AdaptiveInsightReport(<AdaptiveInsight>[]);

    final win = samples.length > window
        ? samples.sublist(samples.length - window)
        : samples;

    double _avgParseMsNonZero(List<TripPerfSample> s) {
      final vals = s.map((e) => e.parseDurationMs).where((v) => v > 0).toList();
      if (vals.isEmpty) return 0;
      return vals.reduce((a, b) => a + b) / vals.length;
    }

    double _rateFromCumulative(List<TripPerfSample> s, double Function(int,int,int) calc) {
      if (s.length < 2) return 0;
      final first = s.first;
      final last = s.last;
      final dHits = (last.cacheHits - first.cacheHits).clamp(0, 1 << 30);
      final dMiss = (last.cacheMisses - first.cacheMisses).clamp(0, 1 << 30);
      final dReuse = (last.reuse - first.reuse).clamp(0, 1 << 30);
      return calc(dHits, dMiss, dReuse);
    }

    double reuseRate = _rateFromCumulative(win, (h, m, r) {
      final total = h + m;
      if (total == 0) return 0;
      return r / total;
    });

    double hitRate = _rateFromCumulative(win, (h, m, r) {
      final total = h + m;
      if (total == 0) return 0;
      return h / total;
    });

    final avgParseMs = _avgParseMsNonZero(win);

    // Trend over last 5 vs previous 5 samples
    double _windowRate(List<TripPerfSample> s) => _rateFromCumulative(s, (h, m, r) {
          final total = h + m;
          if (total == 0) return 0;
          return h / total; // hitRate window
        });
    double _windowReuse(List<TripPerfSample> s) => _rateFromCumulative(s, (h, m, r) {
          final total = h + m;
          if (total == 0) return 0;
          return r / total;
        });
    double _windowParse(List<TripPerfSample> s) => _avgParseMsNonZero(s);

    double _trend(List<TripPerfSample> s, double Function(List<TripPerfSample>) f) {
      if (s.length < 10) return 0; // need 5 + 5
      final last5 = s.sublist(s.length - 5);
      final prev5 = s.sublist(s.length - 10, s.length - 5);
      final a = f(last5);
      final b = f(prev5);
      if (b == 0) return 0;
      return ((a - b) / b) * 100.0; // percent delta
    }

    final trendParse = _trend(win, _windowParse);
    final trendHit = _trend(win, _windowRate);
    final trendReuse = _trend(win, _windowReuse);

    final out = <AdaptiveInsight>[];

    // Thresholds
    if (avgParseMs > 600) {
      out.add(const AdaptiveInsight('⚠️ Parsing slower — consider increasing isolate threshold.', Colors.redAccent));
    } else if (avgParseMs > 500) {
      out.add(const AdaptiveInsight('⚠️ Parsing slower — consider raising isolate threshold.', Colors.orangeAccent));
    }

    if (reuseRate > 0.90) {
      out.add(const AdaptiveInsight('✅ Reuse rate excellent.', Colors.greenAccent));
    } else if (reuseRate > 0.85) {
      out.add(const AdaptiveInsight('✅ Reuse rate healthy.', Colors.greenAccent));
    } else if (reuseRate < 0.60) {
      out.add(const AdaptiveInsight('⚠️ Low reuse — check signature diffing or TTL.', Colors.redAccent));
    } else if (reuseRate < 0.85) {
      out.add(const AdaptiveInsight('ℹ️ Reuse moderate — consider TTL/signature tuning.', Colors.orangeAccent));
    }

    if (hitRate > 0.8) {
      out.add(const AdaptiveInsight('👍 Cache efficiency good.', Colors.greenAccent));
    } else if (hitRate < 0.5) {
      out.add(const AdaptiveInsight('⚠️ Many cache misses — review fetch interval.', Colors.orangeAccent));
    }

    // Trends
    if (trendParse > 10) {
      out.add(const AdaptiveInsight('↗ Parse time rising.', Colors.purpleAccent));
    } else if (trendParse < -10) {
      out.add(const AdaptiveInsight('↘ Parse time falling.', Colors.cyanAccent));
    }
    if (trendHit > 10) {
      out.add(const AdaptiveInsight('↗ Hit rate rising.', Colors.cyanAccent));
    } else if (trendHit < -10) {
      out.add(const AdaptiveInsight('↘ Hit rate falling.', Colors.purpleAccent));
    }
    if (trendReuse > 10) {
      out.add(const AdaptiveInsight('↗ Reuse rising.', Colors.cyanAccent));
    } else if (trendReuse < -10) {
      out.add(const AdaptiveInsight('↘ Reuse falling.', Colors.purpleAccent));
    }

    // Optional advanced hints
    if (avgParseMs > 600 && reuseRate < 0.70) {
      out.add(const AdaptiveInsight('💡 Consider increasing isolate threshold or extending TTL.', Colors.redAccent));
    }
    if (reuseRate > 0.90 && avgParseMs < 300) {
      out.add(const AdaptiveInsight('💡 System optimal; you may lower LOD debounce.', Colors.greenAccent));
    }

    return AdaptiveInsightReport(List<AdaptiveInsight>.unmodifiable(out));
  }
}

/// Provider to compute insights from the current timeline samples
final adaptiveInsightsProvider = Provider<AdaptiveInsightReport>((ref) {
  final samples = ref.watch(tripPerfTimelineProvider);
  return TripAdaptiveInsights.compute(samples, window: 30);
});