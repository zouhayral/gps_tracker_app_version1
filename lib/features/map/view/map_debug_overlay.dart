import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Debug information container for FMTC tile diagnostics
class MapDebugData {
  final String tileSource;
  final double cacheHitRate;
  final String networkStatus;
  final int totalRequests;
  final int cacheHits;
  final String lastTileUrl;

  const MapDebugData({
    required this.tileSource,
    required this.cacheHitRate,
    required this.networkStatus,
    required this.totalRequests,
    required this.cacheHits,
    required this.lastTileUrl,
  });

  MapDebugData copyWith({
    String? tileSource,
    double? cacheHitRate,
    String? networkStatus,
    int? totalRequests,
    int? cacheHits,
    String? lastTileUrl,
  }) {
    return MapDebugData(
      tileSource: tileSource ?? this.tileSource,
      cacheHitRate: cacheHitRate ?? this.cacheHitRate,
      networkStatus: networkStatus ?? this.networkStatus,
      totalRequests: totalRequests ?? this.totalRequests,
      cacheHits: cacheHits ?? this.cacheHits,
      lastTileUrl: lastTileUrl ?? this.lastTileUrl,
    );
  }
}

/// Singleton for tracking FMTC diagnostics
class MapDebugInfo {
  MapDebugInfo._();
  
  static final MapDebugInfo instance = MapDebugInfo._();
  
  final ValueNotifier<MapDebugData> _notifier = ValueNotifier(
    const MapDebugData(
      tileSource: 'Unknown',
      cacheHitRate: 0,
      networkStatus: 'Checking...',
      totalRequests: 0,
      cacheHits: 0,
      lastTileUrl: 'No tiles loaded yet',
    ),
  );
  
  ValueNotifier<MapDebugData> get notifier => _notifier;
  MapDebugData get current => _notifier.value;
  
  /// Update tile source
  void updateTileSource(String source) {
    _notifier.value = _notifier.value.copyWith(tileSource: source);
  }
  
  /// Update network status
  void updateNetworkStatus(String status) {
    _notifier.value = _notifier.value.copyWith(networkStatus: status);
  }
  
  /// Record a cache hit
  void recordCacheHit(String tileUrl) {
    final current = _notifier.value;
    final newHits = current.cacheHits + 1;
    final newTotal = current.totalRequests + 1;
    final newRate = (newHits / newTotal) * 100.0;
    
    _notifier.value = current.copyWith(
      cacheHits: newHits,
      totalRequests: newTotal,
      cacheHitRate: newRate,
      lastTileUrl: tileUrl,
    );
  }
  
  /// Record a cache miss
  void recordCacheMiss(String tileUrl) {
    final current = _notifier.value;
    final newTotal = current.totalRequests + 1;
    final newRate = (current.cacheHits / newTotal) * 100.0;
    
    _notifier.value = current.copyWith(
      totalRequests: newTotal,
      cacheHitRate: newRate,
      lastTileUrl: tileUrl,
    );
  }
  
  /// Reset statistics
  void reset() {
    final current = _notifier.value;
    _notifier.value = MapDebugData(
      tileSource: current.tileSource,
      cacheHitRate: 0,
      networkStatus: current.networkStatus,
      totalRequests: 0,
      cacheHits: 0,
      lastTileUrl: 'Reset',
    );
  }
}

/// FMTC Diagnostics Overlay (debug-only)
/// Displays live tile source, cache hit rate, and network status
class MapDebugOverlay extends StatelessWidget {
  const MapDebugOverlay({super.key});

  @override
  Widget build(BuildContext context) {
    // Only show in debug mode
    if (kReleaseMode) return const SizedBox.shrink();
    
    return Positioned(
      left: 8,
      bottom: 8,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.black87,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0xFFA6CD27)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: ValueListenableBuilder<MapDebugData>(
            valueListenable: MapDebugInfo.instance.notifier,
            builder: (context, info, _) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    '🗺️ FMTC DEBUG',
                    style: TextStyle(
                      color: Color(0xFFA6CD27),
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Source: ${info.tileSource}',
                    style: const TextStyle(color: Colors.white, fontSize: 10),
                  ),
                  Text(
                    'Cache hit: ${info.cacheHitRate.toStringAsFixed(1)}% (${info.cacheHits}/${info.totalRequests})',
                    style: const TextStyle(color: Colors.white, fontSize: 10),
                  ),
                  Text(
                    'Status: ${info.networkStatus}',
                    style: TextStyle(
                      color: info.networkStatus == 'Online' 
                          ? Colors.greenAccent 
                          : Colors.redAccent,
                      fontSize: 10,
                    ),
                  ),
                  if (info.lastTileUrl.isNotEmpty && info.lastTileUrl != 'No tiles loaded yet')
                    Text(
                      'Last: ${_truncateUrl(info.lastTileUrl)}',
                      style: const TextStyle(color: Colors.white70, fontSize: 9),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
  
  String _truncateUrl(String url) {
    if (url.length <= 40) return url;
    return '...${url.substring(url.length - 37)}';
  }
}
