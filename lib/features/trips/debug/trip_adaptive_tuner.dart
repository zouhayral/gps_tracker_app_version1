import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'trip_adaptive_insights.dart';
import 'package:my_app_gps/repositories/trip_repository.dart';

class RuntimeParams {
  final Duration debounce;
  final Duration ttl;
  final int isolateThreshold;
  final DateTime lastUpdate;
  const RuntimeParams({
    required this.debounce,
    required this.ttl,
    required this.isolateThreshold,
    required this.lastUpdate,
  });

  RuntimeParams copyWith({
    Duration? debounce,
    Duration? ttl,
    int? isolateThreshold,
    DateTime? lastUpdate,
  }) => RuntimeParams(
        debounce: debounce ?? this.debounce,
        ttl: ttl ?? this.ttl,
        isolateThreshold: isolateThreshold ?? this.isolateThreshold,
        lastUpdate: lastUpdate ?? this.lastUpdate,
      );
}

// Global snapshot (readable outside Riverpod contexts when needed)
RuntimeParams _globalRuntimeParams = RuntimeParams(
  debounce: const Duration(milliseconds: 300),
  ttl: const Duration(seconds: 120),
  isolateThreshold: 1024,
  lastUpdate: DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
);

RuntimeParams get currentRuntimeParams => _globalRuntimeParams;
int currentIsolateThreshold() => _globalRuntimeParams.isolateThreshold;

class AdaptiveRuntimeConfig extends StateNotifier<RuntimeParams> {
  AdaptiveRuntimeConfig()
      : super(_globalRuntimeParams);

  static const _minInterval = Duration(seconds: 30);

  void _apply(RuntimeParams next, String reason) {
    // Rate-limit
    final now = DateTime.now();
    if (now.difference(state.lastUpdate) < _minInterval) return;

    state = next.copyWith(lastUpdate: now);
    _globalRuntimeParams = state;

    if (kDebugMode) {
      debugPrint('[AdaptiveTuner] debounce=${state.debounce.inMilliseconds}ms '
          'ttl=${state.ttl.inSeconds}s '
          'threshold=${state.isolateThreshold}B (reason: $reason)');
    }
  }

  void updateDebounce(Duration newDebounce, {String reason = 'update'}) {
    Duration _clampDuration(Duration v, Duration min, Duration max) {
      final ms = v.inMilliseconds.clamp(min.inMilliseconds, max.inMilliseconds);
      return Duration(milliseconds: ms);
    }
    final clamped = _clampDuration(
      newDebounce,
      const Duration(milliseconds: 200),
      const Duration(milliseconds: 600),
    );
    if (clamped == state.debounce) return;
    _apply(state.copyWith(debounce: clamped), reason);
  }

  void updateTtl(Duration newTtl, {String reason = 'update'}) {
    final min = const Duration(seconds: 120);
    final max = const Duration(seconds: 600);
    final ms = newTtl.inMilliseconds.clamp(min.inMilliseconds, max.inMilliseconds);
    final clamped = Duration(milliseconds: ms);
    if (clamped == state.ttl) return;
    _apply(state.copyWith(ttl: clamped), reason);
  }

  void updateIsolateThreshold(int bytes, {String reason = 'update'}) {
    final b = bytes.clamp(512, 4096);
    if (b == state.isolateThreshold) return;
    _apply(state.copyWith(isolateThreshold: b), reason);
  }
}

final adaptiveRuntimeConfigProvider =
    StateNotifierProvider<AdaptiveRuntimeConfig, RuntimeParams>((ref) {
  return AdaptiveRuntimeConfig();
});

/// Feedback bridge: listens to insights and adjusts runtime parameters.
final tripAdaptiveTunerProvider = Provider<void>((ref) {
  final cfg = ref.read(adaptiveRuntimeConfigProvider.notifier);

  int slowParseStreak = 0;
  int risingParseStreak = 0;
  int highReuseStreak = 0;
  int lowReuseStreak = 0;
  int missWarnStreak = 0;

  void onReport(AdaptiveInsightReport report) {
    final msgs = report.insights.map((e) => e.message).toList();
    bool hasSlowParse = msgs.any((m) => m.contains('Parsing slower'));
    bool hasRisingParse = msgs.any((m) => m.contains('Parse time rising'));
    bool hasHighReuse = msgs.any((m) => m.contains('Reuse rate excellent') || m.contains('Reuse rate healthy'));
    bool hasLowReuse = msgs.any((m) => m.contains('Low reuse'));
    bool hasMissWarn = msgs.any((m) => m.contains('Many cache misses'));

    slowParseStreak = hasSlowParse ? (slowParseStreak + 1) : 0;
    risingParseStreak = hasRisingParse ? (risingParseStreak + 1) : 0;
    highReuseStreak = hasHighReuse ? (highReuseStreak + 1) : 0;
    lowReuseStreak = hasLowReuse ? (lowReuseStreak + 1) : 0;
    missWarnStreak = hasMissWarn ? (missWarnStreak + 1) : 0;

    // Apply hooks when streak >= 3
    if (slowParseStreak >= 3 || risingParseStreak >= 3) {
      cfg.updateIsolateThreshold(currentRuntimeParams.isolateThreshold + 512,
          reason: 'high parse avg');
      cfg.updateDebounce(const Duration(milliseconds: 450), reason: 'high parse avg');
    }

    if (highReuseStreak >= 3) {
      cfg.updateDebounce(const Duration(milliseconds: 250), reason: 'excellent reuse');
    }

    if (lowReuseStreak >= 3) {
      cfg.updateTtl(currentRuntimeParams.ttl + const Duration(seconds: 60),
          reason: 'low reuse');
      if (kDebugMode) {
        debugPrint('[AdaptiveTuner] extending TTL due to low reuse');
      }
    }

    if (missWarnStreak >= 3) {
      // Prefetch next window via repository helper if available
      // Use a safe best-effort call
      try {
        final repo = ref.read(tripRepositoryProvider);
        repo.prefetchLastUsedFilter();
      } catch (_) {}
    }
  }

  // Listen to insights stream
  ref.listen<AdaptiveInsightReport>(adaptiveInsightsProvider, (prev, next) {
    onReport(next);
  });
});