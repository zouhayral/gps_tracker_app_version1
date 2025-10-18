import 'dart:collection';
import 'dart:typed_data';

/// Simple in-memory LRU-ish cache for cluster badge PNG bytes.
/// We keep a small cap to avoid unbounded memory growth.
class ClusterBadgeCache {
  ClusterBadgeCache._();
  
  static final _cache = LinkedHashMap<String, Uint8List>();
  static int hits = 0;
  static int misses = 0;

  static Uint8List? get(String key) {
    final value = _cache.remove(key);
    if (value != null) {
      // Reinsert to mark as most-recently-used
      _cache[key] = value;
      hits++;
    } else {
      misses++;
    }
    return value;
  }

  static void put(String key, Uint8List bytes) {
    // Cap at ~50 entries
    if (_cache.length >= 50 && _cache.isNotEmpty) {
      _cache.remove(_cache.keys.first);
    }
    _cache[key] = bytes;
  }

  static double hitRate() {
    final total = hits + misses;
    if (total == 0) return 0;
    return hits / total;
  }

  static void clear() {
    _cache.clear();
    hits = 0;
    misses = 0;
  }
}
