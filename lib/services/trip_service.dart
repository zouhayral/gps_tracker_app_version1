import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_app_gps/data/models/trip.dart';
import 'package:my_app_gps/features/trips/debug/trip_adaptive_tuner.dart';

/// Tiny helper to log durations without boilerplate.
/// Use timeAsync/timeSync to wrap work and emit a single timing log.
Future<T> timeAsync<T>(String label, Future<T> Function() run,
		{void Function(int ms)? onDone}) async {
	final sw = Stopwatch()..start();
		try {
			return await run();
		} finally {
			sw.stop();
			if (kDebugMode) {
				// ignore: avoid_print
				print('$label: ${sw.elapsedMilliseconds}ms');
			}
			if (onDone != null) onDone(sw.elapsedMilliseconds);
		}
}

T timeSync<T>(String label, T Function() run, {void Function(int ms)? onDone}) {
	final sw = Stopwatch()..start();
		try {
			return run();
		} finally {
			sw.stop();
			if (kDebugMode) {
				// ignore: avoid_print
				print('$label: ${sw.elapsedMilliseconds}ms');
			}
			if (onDone != null) onDone(sw.elapsedMilliseconds);
		}
}

/// Top-level isolate function for parsing trips; required by compute().
List<Trip> _parseTripsIsolate(dynamic jsonData) {
	List<dynamic> jsonList;
	if (jsonData is String) {
		try {
			final decoded = jsonDecode(jsonData);
			if (decoded is List) {
				jsonList = decoded;
			} else {
				return const <Trip>[];
			}
		} catch (_) {
			return const <Trip>[];
		}
	} else if (jsonData is List) {
		jsonList = jsonData;
	} else {
		return const <Trip>[];
	}

	final trips = <Trip>[];
	for (final item in jsonList) {
		if (item is Map<String, dynamic>) {
			try {
				trips.add(Trip.fromJson(item));
			} catch (_) {/* skip malformed */}
		}
	}
	return trips;
}

/// Service offering adaptive trip parsing using compute() for large payloads.
class TripService {
	TripService();

	/// Parse trips adaptively: for payload >1KB, offload to an isolate.
	Future<List<Trip>> parseTripsAdaptive(dynamic data) async {
		int payloadBytes = 0;
		try {
			if (data is String) {
				payloadBytes = utf8.encode(data).length;
			} else if (data is List) {
				payloadBytes = utf8.encode(jsonEncode(data)).length;
			}
		} catch (_) {/* ignore */}

			int threshold;
			try {
				threshold = currentIsolateThreshold();
			} catch (_) {
				threshold = 1024;
			}
			final useIsolate = payloadBytes > threshold;
		if (!useIsolate) {
					if (kDebugMode) {
						// ignore: avoid_print
						print('[ASYNC_PARSE] Trips payload ${payloadBytes}B (sync parse)');
					}
					return timeSync<List<Trip>>("[TripService] parse.sync", () => _parseTripsIsolate(data));
		}

		if (kDebugMode) {
			// ignore: avoid_print
		print('[ASYNC_PARSE] Trips payload ${payloadBytes}B (compute, threshold=${threshold}B)');
		}
		return timeAsync<List<Trip>>("[TripService] parse.compute",
				() => compute(_parseTripsIsolate, data));
	}
}

/// Provider for TripService.
final tripServiceProvider = Provider<TripService>((ref) => TripService());

