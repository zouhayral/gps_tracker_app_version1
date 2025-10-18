import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:my_app_gps/features/map/clustering/cluster_badge_cache.dart';

void main() {
  test('ClusterBadgeCache stores and retrieves bytes with LRU-ish behavior', () {
    ClusterBadgeCache.clear();

    // Insert 55 entries to exceed cap (50)
    for (var i = 0; i < 55; i++) {
      final key = 'k$i';
      final bytes = Uint8List.fromList([i]);
      ClusterBadgeCache.put(key, bytes);
    }

    // First key should have been evicted
    expect(ClusterBadgeCache.get('k0'), isNull);

    // Recent keys should exist
    expect(ClusterBadgeCache.get('k54')!.first, 54);

    // Hit/miss accounting
    final hitsBefore = ClusterBadgeCache.hits;
    final missesBefore = ClusterBadgeCache.misses;

    ClusterBadgeCache.get('k54'); // hit
    ClusterBadgeCache.get('nope'); // miss

    expect(ClusterBadgeCache.hits, hitsBefore + 1);
    expect(ClusterBadgeCache.misses, missesBefore + 1);

    // Hit rate should be between 0 and 1
    expect(ClusterBadgeCache.hitRate(), inInclusiveRange(0.0, 1.0));
  });
}
