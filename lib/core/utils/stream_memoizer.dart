/// Stream memoization utility to prevent duplicate stream subscriptions.
/// 
/// Caches streams by key to ensure multiple UI widgets watching the same
/// data source share a single underlying subscription, reducing CPU/memory overhead.
/// 
/// **Benefits:**
/// - Eliminates redundant async operations
/// - Reduces memory pressure from duplicate subscriptions
/// - Maintains reactive semantics (all subscribers still get updates)
/// 
/// **Usage:**
/// ```dart
/// final _memoizer = StreamMemoizer<Position>();
/// 
/// Stream<Position> getPositionStream(int deviceId) {
///   return _memoizer.memoize(
///     'device_$deviceId',
///     () => _createPositionStream(deviceId),
///   );
/// }
/// ```
class StreamMemoizer<T> {
  final Map<String, Stream<T>> _cache = {};
  
  /// Returns an existing stream for [key] or creates and stores a new one.
  /// 
  /// The [create] function is only called once per unique key. Subsequent
  /// calls with the same key return the cached stream.
  /// 
  /// **Thread-safety:** This implementation is not thread-safe. Use from
  /// a single isolate only (standard for Flutter apps).
  Stream<T> memoize(String key, Stream<T> Function() create) {
    return _cache.putIfAbsent(key, create);
  }
  
  /// Checks if a stream is cached for the given [key].
  bool contains(String key) => _cache.containsKey(key);
  
  /// Returns the number of cached streams.
  int get size => _cache.length;
  
  /// Removes the cached stream for [key] if it exists.
  /// 
  /// Returns `true` if a stream was removed, `false` if the key didn't exist.
  bool remove(String key) => _cache.remove(key) != null;
  
  /// Clears all memoized streams.
  /// 
  /// Call this when:
  /// - User logs out (reset session state)
  /// - Manual cache invalidation needed
  /// - Testing scenarios requiring clean state
  void clear() => _cache.clear();
  
  /// Returns cache statistics for diagnostics.
  Map<String, dynamic> getStats() {
    return {
      'cacheSize': _cache.length,
      'cachedKeys': _cache.keys.toList(),
    };
  }
}
