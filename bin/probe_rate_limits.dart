import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:my_app_gps/services/auth_service.dart';
import 'package:my_app_gps/services/positions_service.dart';

/*
 * Probe Traccar API polling behavior.
 * Usage (PowerShell):
 *   dart run bin/probe_rate_limits.dart <email> <password> [deviceId]
 * If deviceId omitted, first device from /api/devices is used.
 */

Future<void> main(List<String> args) async {
  if (args.length < 2) {
    stderr.writeln(
      'Usage: dart run bin/probe_rate_limits.dart <email> <password> [deviceId]',
    );
    exit(64);
  }
  final email = args[0];
  final password = args[1];
  final explicitDeviceId = args.length >= 3 ? int.tryParse(args[2]) : null;

  final container = ProviderContainer();
  final dio = container.read(dioProvider);
  final auth = container.read(authServiceProvider);
  final positionsSvc = container.read(positionsServiceProvider);

  await auth.clearStoredSession();
  Map<String, dynamic> user;
  try {
    user = await auth.login(email, password);
  } catch (e) {
    stderr.writeln('Login failed: $e');
    exit(1);
  }

  final probeStart = DateTime.now().toUtc();
  // Fetch devices
  List<Map<String, dynamic>> devices;
  try {
    final r = await dio.get<List<dynamic>>('/api/devices');
    final data = r.data;
    if (data == null) {
      stderr.writeln('Empty devices response');
      exit(1);
    }
    devices = data.cast<Map<String, dynamic>>().toList();
  } catch (e) {
    stderr.writeln('Failed to fetch devices: $e');
    exit(1);
  }

  if (devices.isEmpty) {
    stderr.writeln('No devices available to test');
    exit(1);
  }
  final deviceId = explicitDeviceId ?? (devices.first['id'] as int);

  final frequencies = <_FreqTest>[
    // requests per second targets
    _FreqTest(label: '1_rps', delayMs: 1000),
    _FreqTest(label: '2_rps', delayMs: 500),
    _FreqTest(label: '4_rps', delayMs: 250),
    _FreqTest(label: '8_rps', delayMs: 125),
    _FreqTest(label: '10_rps', delayMs: 100),
  ];

  const perFreqRequests = 8; // keep runtime modest

  final results = <Map<String, dynamic>>[];

  Future<void> runBurst(_FreqTest f) async {
    for (var i = 0; i < perFreqRequests; i++) {
      final start = DateTime.now();
      final sw = Stopwatch()..start();
      int? status;
      var bytes = 0;
      String? error;
      try {
        final r = await dio.get<List<dynamic>>('/api/devices');
        status = r.statusCode;
        bytes = utf8.encode(jsonEncode(r.data)).length;
      } catch (e) {
        error = e.toString();
      }
      sw.stop();
      results.add({
        'phase': 'devices',
        'freq': f.label,
        'seq': i,
        'start': start.toIso8601String(),
        'durMs': sw.elapsedMilliseconds,
        if (status != null) 'status': status,
        'bytes': bytes,
        if (error != null) 'error': error,
      });
      // Also small positions fetch (last 5 minutes) to include variety
      final posStart = DateTime.now();
      final posSw = Stopwatch()..start();
      status = null;
      bytes = 0;
      error = null;
      try {
        final to = DateTime.now().toUtc();
        final from = to.subtract(const Duration(minutes: 5));
        final list = await positionsSvc.fetchHistoryRaw(
          deviceId: deviceId,
          from: from,
          to: to,
        );
        status = 200; // fetchHistoryRaw throws if not 200 List
        bytes = utf8.encode(jsonEncode(list)).length;
      } catch (e) {
        error = e.toString();
      }
      posSw.stop();
      results.add({
        'phase': 'positions',
        'freq': f.label,
        'seq': i,
        'start': posStart.toIso8601String(),
        'durMs': posSw.elapsedMilliseconds,
        if (status != null) 'status': status,
        'bytes': bytes,
        if (error != null) 'error': error,
      });
      await Future<void>.delayed(Duration(milliseconds: f.delayMs));
    }
  }

  for (final f in frequencies) {
    await runBurst(f);
  }

  // Aggregate
  final aggregates = <String, Map<String, dynamic>>{};
  for (final f in frequencies) {
    final subset = results.where((r) => r['freq'] == f.label).toList();
    if (subset.isEmpty) continue;
    final byPhase = <String, List<Map<String, dynamic>>>{};
    for (final r in subset) {
      byPhase.putIfAbsent(r['phase'] as String, () => []).add(r);
    }
    final phasesAgg = <String, dynamic>{};
    byPhase.forEach((phase, list) {
      final latencies = list.map((e) => e['durMs'] as int).toList();
      latencies.sort();
      final statuses = <int, int>{};
      for (final r in list) {
        if (r['status'] is int) {
          statuses.update(r['status'] as int, (v) => v + 1, ifAbsent: () => 1);
        }
      }
      phasesAgg[phase] = {
        'count': list.length,
        'statusCounts': statuses.map((k, v) => MapEntry(k.toString(), v)),
        'latencyMs': {
          'min': latencies.first,
          'p50': latencies[(latencies.length * 0.5).floor()],
          'p90':
              latencies[(latencies.length * 0.9).floor().clamp(
                0,
                latencies.length - 1,
              )],
          'max': latencies.last,
          'avg': (latencies.reduce((a, b) => a + b) / latencies.length)
              .toStringAsFixed(1),
        },
        'errors': list.where((e) => e.containsKey('error')).length,
      };
    });
    aggregates[f.label] = phasesAgg;
  }

  // Simple recommendation logic (heuristic): find lowest frequency where latency stays <300ms p90; propose 5-10s normal polling.
  String recommendation;
  final oneRps = aggregates['1_rps'];
  if (oneRps != null) {
    final devicesP90 = int.tryParse(
      ((oneRps['devices'] as Map)['latencyMs'] as Map)['p90'].toString(),
    );
    if (devicesP90 != null && devicesP90 < 300) {
      recommendation =
          'Use WebSocket for sub-second real-time; fallback polling every 5–10s (1 rps sustainable but unnecessary). Background: 60s.';
    } else {
      recommendation =
          'Latency elevated even at 1 rps; start with 15s polling; strongly prefer WebSocket.';
    }
  } else {
    recommendation =
        'Insufficient data; default to 10s polling + WebSocket when available.';
  }

  final output = {
    'meta': {
      'started': probeStart.toIso8601String(),
      'ended': DateTime.now().toUtc().toIso8601String(),
      'baseUrl': dio.options.baseUrl,
      'deviceId': deviceId,
      'userId': user['id'],
      'frequenciesTested': frequencies.map((f) => f.label).toList(),
    },
    'results': results,
    'aggregates': aggregates,
    'recommendation': recommendation,
  };

  stdout.writeln(jsonEncode(output));
  container.dispose();
}

class _FreqTest {
  _FreqTest({required this.label, required this.delayMs});
  final String label; // descriptive label e.g. 1_rps
  final int delayMs; // delay between iterations (approx)
}
