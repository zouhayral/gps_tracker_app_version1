import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_app_gps/features/dashboard/controller/devices_notifier.dart';

/// Debounced device search with optional isolate offloading for large lists.
///
/// Goals delivered:
/// - Debounce input 200–300ms before filtering (250ms chosen).
/// - Pre-normalize device names (lowercased cache).
/// - For lists > 500 items, use compute() for filtering.
/// - Apply prefix match for queries < 3 chars; fuzzy match for >= 3.
/// - Emit filtered results via Riverpod provider.
///
/// Public API:
/// - [debouncedDeviceSearchProvider]: StreamProvider.family<List<Map<String, dynamic>>, String>
///   Returns filtered device maps, debounced and possibly computed in an isolate.
///
/// Usage:
/// ```dart
/// final results = ref.watch(debouncedDeviceSearchProvider(query)).value ?? const [];
/// ```

/// Internal lightweight index structure to avoid repeated lowercasing.
class IndexedDevice {
  final int id;
  final String name;
  final String lowerName;
  final Map<String, dynamic> original; // Keep original Map for UI consumers

  const IndexedDevice({
    required this.id,
    required this.name,
    required this.lowerName,
    required this.original,
  });
}

/// Build and cache a normalized index of devices with lowercased names.
final _deviceIndexProvider = Provider<List<IndexedDevice>>((ref) {
  final devicesValue = ref.watch(devicesNotifierProvider);
  return devicesValue.maybeWhen(
    data: (devices) {
      return devices.map((d) {
        final id = d['id'] as int? ?? -1;
        final name = (d['name'] as String?)?.trim() ?? '';
        return IndexedDevice(
          id: id,
          name: name,
          lowerName: name.toLowerCase(),
          original: d,
        );
      }).toList(growable: false);
    },
    orElse: () => const <IndexedDevice>[],
  );
});

/// Debounced, isolate-powered search provider.
///
/// Design notes:
/// - The provider is a StreamProvider.family so we can internally debounce with
///   a short delay before emitting the results.
/// - Each new query param recreates the provider; we still apply a delay so
///   quick successive changes collapse into one compute.
/// - For very large lists (>500), we offload filtering to a background isolate
///   using [compute] with a top-level function.
final debouncedDeviceSearchProvider =
    StreamProvider.family<List<Map<String, dynamic>>, String>((ref, query) async* {
  // Clamp debounce between 200–300ms; choose 250ms by default.
  const debounce = Duration(milliseconds: 250);

  // Pull the normalized index once per query evaluation.
  final index = ref.watch(_deviceIndexProvider);

  // If no devices or query empty → emit full list quickly after debounce
  final trimmed = query.trim();

  // Debounce to avoid re-filtering on every keystroke
  await Future<void>.delayed(debounce);

  if (trimmed.isEmpty) {
    yield index.map((e) => e.original).toList(growable: false);
    return;
  }

  // Decide matching strategy
  final usePrefix = trimmed.length < 3;
  final lowerQ = trimmed.toLowerCase();

  // Offload to isolate if list is large
  if (index.length > 500) {
    final payload = _SearchPayload(
      entries: index
          .map((e) => _SearchEntry(e.id, e.name, e.lowerName, e.original))
          .toList(growable: false),
      lowerQuery: lowerQ,
      usePrefix: usePrefix,
    );

    final results = await compute(_filterDevicesIsolate, payload);
    yield results;
    return;
  }

  // Local filtering on main isolate for small/medium lists
  final results = _filterSync(index, lowerQ, usePrefix);
  yield results;
});

/// Top-level payload class for compute() (must be simple/serializable types).
class _SearchPayload {
  final List<_SearchEntry> entries;
  final String lowerQuery;
  final bool usePrefix;
  const _SearchPayload({
    required this.entries,
    required this.lowerQuery,
    required this.usePrefix,
  });
}

/// Lightweight entry for isolate payload.
class _SearchEntry {
  final int id;
  final String name;
  final String lowerName;
  final Map<String, dynamic> original;
  const _SearchEntry(this.id, this.name, this.lowerName, this.original);
}

/// Isolate function: filters devices by prefix (short queries) or fuzzy (>=3).
Future<List<Map<String, dynamic>>> _filterDevicesIsolate(_SearchPayload p) async {
  final results = <Map<String, dynamic>>[];
  for (final e in p.entries) {
    final ok = p.usePrefix
        ? e.lowerName.startsWith(p.lowerQuery)
        : _isFuzzyMatch(e.lowerName, p.lowerQuery);
    if (ok) results.add(e.original);
  }
  // Optional: stable sort by best match (prefix-first, then shorter name)
  if (!p.usePrefix) {
    results.sort((a, b) {
      final an = (a['name'] as String? ?? '').toLowerCase();
      final bn = (b['name'] as String? ?? '').toLowerCase();
      final ap = an.startsWith(p.lowerQuery) ? 0 : 1;
      final bp = bn.startsWith(p.lowerQuery) ? 0 : 1;
      return ap != bp ? ap - bp : an.length - bn.length;
    });
  }
  return results;
}

/// Synchronous filtering path for small/medium lists.
List<Map<String, dynamic>> _filterSync(
  List<IndexedDevice> index,
  String lowerQuery,
  bool usePrefix,
) {
  final results = <Map<String, dynamic>>[];
  for (final e in index) {
    final ok = usePrefix
        ? e.lowerName.startsWith(lowerQuery)
        : _isFuzzyMatch(e.lowerName, lowerQuery);
    if (ok) results.add(e.original);
  }
  if (!usePrefix) {
    results.sort((a, b) {
      final an = (a['name'] as String? ?? '').toLowerCase();
      final bn = (b['name'] as String? ?? '').toLowerCase();
      final ap = an.startsWith(lowerQuery) ? 0 : 1;
      final bp = bn.startsWith(lowerQuery) ? 0 : 1;
      return ap != bp ? ap - bp : an.length - bn.length;
    });
  }
  return results;
}

/// Simple fuzzy match: checks if all query chars appear in order in the target.
/// Example: 'abc' matches 'aXbYc', but not 'acb'.
bool _isFuzzyMatch(String lowerName, String lowerQuery) {
  if (lowerQuery.isEmpty) return true;
  var qi = 0;
  for (var i = 0; i < lowerName.length && qi < lowerQuery.length; i++) {
    if (lowerName.codeUnitAt(i) == lowerQuery.codeUnitAt(qi)) {
      qi++;
    }
  }
  return qi == lowerQuery.length;
}
