import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_app_gps/services/auth_service.dart';

/// Temporary diagnostic function: run API polling rate probe.
/// After using and extracting JSON metrics, delete this file + FAB trigger.
Future<void> runRateProbe(WidgetRef ref, {required int deviceId}) async {
  final dio = ref.read(dioProvider);
  final freqs = <({String label, int delayMs})>[
    (label: '1_rps', delayMs: 1000),
    (label: '2_rps', delayMs: 500),
    (label: '4_rps', delayMs: 250),
    (label: '8_rps', delayMs: 125),
    (label: '10_rps', delayMs: 100),
  ];
  const perFreqRequests = 8;
  final samples = <Map<String, dynamic>>[];

  Future<void> burst(String label, int delayMs) async {
    for (var i = 0; i < perFreqRequests; i++) {
      // /api/devices
      final started = DateTime.now();
      final sw = Stopwatch()..start();
      int? status;
      String? error;
      var devCount = 0;
      try {
        final r = await dio.get<List<dynamic>>('/api/devices');
        status = r.statusCode;
        if (r.data is List) devCount = (r.data!).length;
      } catch (e) {
        error = e.toString();
      }
      sw.stop();
      samples.add({
        'phase': 'devices',
        'freq': label,
        'seq': i,
        't': started.toIso8601String(),
        'durMs': sw.elapsedMilliseconds,
        if (status != null) 'status': status,
        'count': devCount,
        if (error != null) 'error': error,
      });
      // /api/positions (5m window)
      final posStart = DateTime.now();
      final psw = Stopwatch()..start();
      status = null;
      error = null;
      var posCount = 0;
      try {
        final to = DateTime.now().toUtc();
        final from = to.subtract(const Duration(minutes: 5));
        final r = await dio.get<List<dynamic>>(
          '/api/positions',
          queryParameters: {
            'deviceId': deviceId,
            'from': from.toIso8601String(),
            'to': to.toIso8601String(),
          },
        );
        if (r.data is List) {
          posCount = (r.data!).length;
          status = 200;
        } else {
          error = 'non-list';
        }
      } catch (e) {
        error = e.toString();
      }
      psw.stop();
      samples.add({
        'phase': 'positions',
        'freq': label,
        'seq': i,
        't': posStart.toIso8601String(),
        'durMs': psw.elapsedMilliseconds,
        if (status != null) 'status': status,
        'count': posCount,
        if (error != null) 'error': error,
      });
      await Future<void>.delayed(Duration(milliseconds: delayMs));
    }
  }

  for (final f in freqs) {
    await burst(f.label, f.delayMs);
  }

  // Summarize
  final summary = <String, dynamic>{};
  for (final f in freqs) {
    final freqObj = <String, dynamic>{};
    for (final ph in ['devices', 'positions']) {
      final list = samples
          .where((s) => s['freq'] == f.label && s['phase'] == ph)
          .toList();
      if (list.isEmpty) continue;
      final lat = list.map((e) => e['durMs'] as int).toList()..sort();
      int pick(num p) => lat[(lat.length * p).clamp(0, lat.length - 1).floor()];
      final statuses = <String, int>{};
      for (final s in list) {
        final st = s['status'];
        if (st is int) statuses['$st'] = (statuses['$st'] ?? 0) + 1;
      }
      freqObj[ph] = {
        'count': list.length,
        'latencyMs': {
          'min': lat.first,
          'p50': pick(0.5),
          'p90': pick(0.9),
          'p99': pick(0.99),
          'max': lat.last,
          'avg': (lat.reduce((a, b) => a + b) / lat.length).toStringAsFixed(1),
        },
        'statusCounts': statuses,
        'errors': list.where((e) => e.containsKey('error')).length,
      };
    }
    summary[f.label] = freqObj;
  }

  final output = {
    'meta': {
      'generatedAt': DateTime.now().toUtc().toIso8601String(),
      'deviceId': deviceId,
      'baseUrl': dio.options.baseUrl,
      'freqs': freqs.map((f) => f.label).toList(),
      'traccarVersionAssumed': '5.12',
    },
    'summary': summary,
    'samples': samples,
  };
  debugPrint(jsonEncode(output));
}
