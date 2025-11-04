import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

/// Network efficiency monitoring interceptor for Dio
/// 
/// Tracks:
/// - Request/response latency
/// - Status code distribution
/// - Retry attempts
/// - Concurrent request count
/// - Response size
class NetworkEfficiencyMonitor extends Interceptor {
  NetworkEfficiencyMonitor({this.maxConcurrency = 3});

  final int maxConcurrency;
  int _activeRequests = 0;
  int _totalRequests = 0;
  int _successfulRequests = 0;
  int _retryCount = 0;
  int _totalBytesTransferred = 0;
  final List<int> _latencySamples = [];
  
  static const _sampleLimit = 100;

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    _activeRequests++;
    _totalRequests++;
    
    // Track request start time
    options.extra['start_time'] = DateTime.now().millisecondsSinceEpoch;
    
    if (_activeRequests > maxConcurrency) {
      if (kDebugMode) {
        debugPrint(
          '[Network] ⚠️ Concurrency exceeded: $_activeRequests active (max: $maxConcurrency)',
        );
      }
    }
    
    if (kDebugMode) {
      debugPrint(
        '[Network] 🚀 ${options.method} ${options.uri.path} '
        '(active: $_activeRequests/$maxConcurrency)',
      );
    }
    
    handler.next(options);
  }

  @override
  void onResponse(Response<dynamic> response, ResponseInterceptorHandler handler) {
    _activeRequests--;
    
    // Calculate latency
    final startTime = response.requestOptions.extra['start_time'] as int?;
    if (startTime != null) {
      final latency = DateTime.now().millisecondsSinceEpoch - startTime;
      _latencySamples.add(latency);
      
      // Keep sample size manageable
      if (_latencySamples.length > _sampleLimit) {
        _latencySamples.removeAt(0);
      }
      
      // Track response size
      final responseSize = _estimateResponseSize(response);
      _totalBytesTransferred += responseSize;
      
      if (response.statusCode == 200) {
        _successfulRequests++;
      }
      
      if (kDebugMode) {
        debugPrint(
          '[Network] ✅ ${response.statusCode} ${response.requestOptions.uri.path} '
          '(${latency}ms, ${_formatBytes(responseSize)})',
        );
      }
    }
    
    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    _activeRequests--;
    
    // Check if this is a retry
    final retryCount = err.requestOptions.extra['retry_count'] as int? ?? 0;
    if (retryCount > 0) {
      _retryCount++;
      
      if (kDebugMode) {
        debugPrint(
          '[Network] 🔄 Retry attempt $retryCount for ${err.requestOptions.uri.path}',
        );
      }
    }
    
    if (kDebugMode) {
      debugPrint(
        '[Network] ❌ ${err.response?.statusCode ?? 'ERROR'} '
        '${err.requestOptions.uri.path} (${err.message})',
      );
    }
    
    handler.next(err);
  }

  /// Get current network efficiency statistics
  Map<String, dynamic> get stats {
    final avgLatency = _latencySamples.isNotEmpty
        ? _latencySamples.reduce((a, b) => a + b) / _latencySamples.length
        : 0.0;
    
    final maxLatency = _latencySamples.isNotEmpty
        ? _latencySamples.reduce((a, b) => a > b ? a : b)
        : 0;
    
    return {
      'total_requests': _totalRequests,
      'successful_requests': _successfulRequests,
      'active_requests': _activeRequests,
      'retry_count': _retryCount,
      'avg_latency_ms': avgLatency,
      'max_latency_ms': maxLatency,
      'total_bytes_transferred': _totalBytesTransferred,
      'success_rate_percent': _totalRequests > 0
          ? (_successfulRequests / _totalRequests * 100).toStringAsFixed(1)
          : '0.0',
    };
  }

  /// Reset statistics
  void reset() {
    _totalRequests = 0;
    _successfulRequests = 0;
    _retryCount = 0;
    _totalBytesTransferred = 0;
    _latencySamples.clear();
    
    if (kDebugMode) {
      debugPrint('[Network] 🔄 Statistics reset');
    }
  }

  /// Log current statistics
  void logStats() {
    final s = stats;
    
    if (kDebugMode) {
      debugPrint('\n========================================');
      debugPrint('📊 Network Efficiency Report');
      debugPrint('========================================');
      debugPrint('🛰️  Requests:');
      debugPrint('   • Total: ${s['total_requests']}');
      debugPrint('   • Successful: ${s['successful_requests']}');
      debugPrint('   • Active: ${s['active_requests']}');
      debugPrint('   • Success Rate: ${s['success_rate_percent']}%');
      debugPrint('');
      debugPrint('⏱️  Latency:');
      debugPrint('   • Average: ${(s['avg_latency_ms'] as double).toStringAsFixed(0)}ms');
      debugPrint('   • Max: ${s['max_latency_ms']}ms');
      debugPrint('');
      debugPrint('🔄 Retries:');
      debugPrint('   • Total: ${s['retry_count']}');
      debugPrint('');
      debugPrint('📦 Data Transfer:');
      debugPrint('   • Total: ${_formatBytes(s['total_bytes_transferred'] as int)}');
      debugPrint('========================================\n');
    }
  }

  int _estimateResponseSize(Response<dynamic> response) {
    if (response.data == null) return 0;
    
    // Estimate based on data type
    if (response.data is String) {
      return (response.data as String).length;
    } else if (response.data is List) {
      // Rough estimate: 100 bytes per list item
      return (response.data as List).length * 100;
    } else if (response.data is Map) {
      // Rough estimate: 500 bytes per map
      return 500;
    }
    
    return 0;
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '${bytes}B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)}KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)}MB';
  }
}

/// Provider singleton for network monitor
class NetworkMonitor {
  static final _instance = NetworkEfficiencyMonitor();
  
  /// Get the global network monitor instance
  static NetworkEfficiencyMonitor get instance => _instance;
}
