import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

/// A lightweight in-memory HTTP cache interceptor for static endpoints.
///
/// What it does
/// - On GET to whitelisted endpoints, it sends conditional headers:
///   - If-None-Match: using the previously returned ETag
///   - If-Modified-Since: using the previously returned Last-Modified
/// - When the server replies 304 Not Modified, it serves the last cached
///   response body instead of propagating an empty response.
/// - On 200 OK, caches response headers (ETag/Last-Modified) and body.
///
/// Why this helps (Traccar context)
/// - Traccar exposes relatively static lists like devices, geofences, users.
///   These don’t change often per session. Using conditional requests prevents
///   sending full payloads repeatedly and reduces server load and bandwidth.
///
/// How ETag works
/// - Server returns ETag: "opaque-token" with 200 OK.
/// - Client re-requests with If-None-Match: "opaque-token".
/// - If unchanged, server replies 304 Not Modified with no body.
///
/// How If-Modified-Since works
/// - Server returns Last-Modified: <HTTP-date> with 200 OK.
/// - Client re-requests with If-Modified-Since: <same date>.
/// - If no newer version is available, server replies 304 Not Modified.
class HttpCacheInterceptor extends Interceptor {
  HttpCacheInterceptor();

  static const _allowedPaths = <String>{
    '/api/devices',
    '/api/geofences',
    '/api/users',
  };

  /// In-memory cache. Keyed by full request URI string.
  static final Map<String, _CacheEntry> _cache = {};

  bool _shouldHandle(RequestOptions options) {
    if (options.method.toUpperCase() != 'GET') return false;
    final path = options.uri.path; // normalized path without query
    return _allowedPaths.contains(path);
  }

  String _key(RequestOptions options) => options.uri.toString();

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    if (_shouldHandle(options)) {
      final key = _key(options);
      final hit = _cache[key];
      if (hit != null) {
        // Add conditional headers if available.
        if (hit.eTag != null && hit.eTag!.isNotEmpty) {
          options.headers['If-None-Match'] = hit.eTag;
        }
        if (hit.lastModified != null && hit.lastModified!.isNotEmpty) {
          options.headers['If-Modified-Since'] = hit.lastModified;
        }
      }
    }
    handler.next(options);
  }

  @override
  void onResponse(Response response, ResponseInterceptorHandler handler) {
    final options = response.requestOptions;
    final isHandled = _shouldHandle(options);
    final status = response.statusCode ?? 0;

    if (isHandled && status == 304) {
      // 304 Not Modified → serve cached body if present
      final key = _key(options);
      final hit = _cache[key];
      if (hit != null) {
        if (kDebugMode) {
          // ignore: avoid_print
          print('[HTTP-CACHE] 304 for ${options.uri} → serving cached body');
        }
        final cached = Response(
          requestOptions: options,
          statusCode: 200,
          data: hit.data,
          headers: hit.headers,
        );
        handler.resolve(cached);
        return;
      }
    }

    if (isHandled && status == 200) {
      // Cache fresh response
      final headers = response.headers;
      final eTag = headers.value('etag') ?? headers.value('ETag');
      final lastModified = headers.value('last-modified') ?? headers.value('Last-Modified');
      final key = _key(options);
      final dataClone = _deepClone(response.data);
      _cache[key] = _CacheEntry(
        data: dataClone,
        headers: headers,
        eTag: eTag,
        lastModified: lastModified,
      );
      if (kDebugMode) {
        // ignore: avoid_print
        print('[HTTP-CACHE] cached ${options.uri} (ETag=$eTag, Last-Modified=$lastModified)');
      }
    }

    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    // For completeness: if server delivers 304 as an error (some proxies), attempt cache.
    final status = err.response?.statusCode ?? 0;
    final options = err.requestOptions;
    if (status == 304 && _shouldHandle(options)) {
      final key = _key(options);
      final hit = _cache[key];
      if (hit != null) {
        if (kDebugMode) {
          // ignore: avoid_print
          print('[HTTP-CACHE] 304(error) for ${options.uri} → serving cached body');
        }
        handler.resolve(Response(
          requestOptions: options,
          statusCode: 200,
          data: hit.data,
          headers: hit.headers,
        ));
        return;
      }
    }
    handler.next(err);
  }

  dynamic _deepClone(dynamic data) {
    // Best-effort deep clone for JSON-like structures
    try {
      if (data is Map || data is List) {
        final text = jsonEncode(data);
        return jsonDecode(text);
      }
    } catch (_) {}
    // Fallback: return as-is (caller should treat as read-only)
    return data;
  }
}

class _CacheEntry {
  _CacheEntry({
    required this.data,
    required this.headers,
    this.eTag,
    this.lastModified,
  });

  final dynamic data;
  final Headers headers;
  final String? eTag;
  final String? lastModified;
}
