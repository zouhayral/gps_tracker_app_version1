import 'package:my_app_gps/core/utils/app_logger.dart';
import 'package:my_app_gps/data/models/trip.dart';

/// Cached response for trip requests
class CachedTripResponse {
  CachedTripResponse({
    required this.trips,
    required this.timestamp,
  });

  final List<Trip> trips;
  final DateTime timestamp;

  bool isExpired(Duration ttl) {
    return DateTime.now().difference(timestamp) > ttl;
  }
}

/// Manages in-memory caching for trip data with TTL and cleanup.
/// 
/// Responsibilities:
/// - Store and retrieve cached trip responses
/// - Track ongoing requests to prevent duplicates
/// - Cleanup expired cache entries
/// - Provide cache statistics
class TripCacheManager {
  static final _log = 'TripCacheManager'.logger;

  // In-memory cache for network responses
  final Map<String, CachedTripResponse> _cache = {};
  
  // Track ongoing requests to prevent duplicates
  final Map<String, Future<List<Trip>>> _ongoingRequests = {};
  
  // Cache TTL: 2 minutes
  static const Duration _cacheTTL = Duration(minutes: 2);

  /// Get cache TTL duration
  Duration get cacheTTL => _cacheTTL;

  /// Build cache key from request parameters
  String buildCacheKey(int deviceId, DateTime from, DateTime to) {
    return '$deviceId|${_toUtcIso(from)}|${_toUtcIso(to)}';
  }

  /// Get cached trips if available and not expired
  List<Trip>? getCached(String cacheKey) {
    final cached = _cache[cacheKey];
    if (cached != null && !cached.isExpired(_cacheTTL)) {
      final age = DateTime.now().difference(cached.timestamp).inSeconds;
      _log.debug('🎯 Cache hit for $cacheKey (age: ${age}s, TTL: ${_cacheTTL.inSeconds}s)');
      return cached.trips;
    }
    return null;
  }

  /// Get stale cache (even if expired) for fallback scenarios
  List<Trip>? getStaleCached(String cacheKey) {
    final stale = _cache[cacheKey];
    if (stale != null) {
      final age = DateTime.now().difference(stale.timestamp).inSeconds;
      _log.debug('🔄 Returning stale cache (${stale.trips.length} trips, age: ${age}s)');
      return stale.trips;
    }
    return null;
  }

  /// Store trips in cache
  void store(String cacheKey, List<Trip> trips) {
    _cache[cacheKey] = CachedTripResponse(
      trips: trips,
      timestamp: DateTime.now(),
    );
    _log.debug('💾 Stored ${trips.length} trips (key: $cacheKey)');
  }

  /// Check if a request is already ongoing
  bool isRequestOngoing(String cacheKey) {
    return _ongoingRequests.containsKey(cacheKey);
  }

  /// Get ongoing request future
  Future<List<Trip>>? getOngoingRequest(String cacheKey) {
    return _ongoingRequests[cacheKey];
  }

  /// Track an ongoing request
  void trackRequest(String cacheKey, Future<List<Trip>> future) {
    _ongoingRequests[cacheKey] = future;
  }

  /// Remove ongoing request tracking
  void removeRequest(String cacheKey) {
    _ongoingRequests.remove(cacheKey);
  }

  /// Remove expired entries from memory cache
  /// OPTIMIZATION: Skip cleanup if no expired entries exist
  void cleanupExpiredCache() {
    // OPTIMIZATION: Guard clause - check for expired entries before cleanup
    final expired = _cache.entries
        .where((entry) => entry.value.isExpired(_cacheTTL))
        .toList();
    
    if (expired.isEmpty) {
      _log.debug('No expired entries (${_cache.length} cached)');
      return;
    }
    
    // Proceed with cleanup
    final before = _cache.length;
    _cache.removeWhere((key, cached) => cached.isExpired(_cacheTTL));
    final after = _cache.length;
    
    _log.debug('🧹 Removed ${before - after} expired entries ($after remain)');
  }

  /// Get cache statistics
  Map<String, dynamic> getStats() {
    final expired = _cache.values.where((v) => v.isExpired(_cacheTTL)).length;
    return {
      'total': _cache.length,
      'expired': expired,
      'valid': _cache.length - expired,
      'ongoing': _ongoingRequests.length,
    };
  }

  /// Clear all cache
  void clear() {
    final count = _cache.length;
    _cache.clear();
    _ongoingRequests.clear();
    _log.debug('🗑️ Cleared $count cache entries');
  }

  // Format to second precision (no fractional seconds) per Traccar expectations
  String _toUtcIso(DateTime d) {
    final dt = d.toUtc();
    String pad2(int n) => n.toString().padLeft(2, '0');
    final y = dt.year.toString().padLeft(4, '0');
    final m = pad2(dt.month);
    final day = pad2(dt.day);
    final h = pad2(dt.hour);
    final min = pad2(dt.minute);
    final s = pad2(dt.second);
    return '$y-$m-$day' 'T' '$h:$min:$s' 'Z';
  }
}
