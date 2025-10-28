import 'dart:convert';

import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:dio_cookie_manager/dio_cookie_manager.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:my_app_gps/core/network/dio_client.dart';
import 'package:my_app_gps/core/storage/secure_storage.dart';
// Platform-specific Dio creation and emulator adjustments
import 'package:my_app_gps/services/platform_dio_stub.dart'
    if (dart.library.io) 'platform_dio_io.dart';

// Providers
final authCookieJarProvider = Provider<CookieJar>((_) => CookieJar());

final dioProvider = Provider<Dio>((ref) {
  // Use the remote server as default since localhost won't work in emulator
  const rawBase = String.fromEnvironment(
    'TRACCAR_BASE_URL',
    defaultValue: 'http://37.60.238.215:8082',
  );
  const allowInsecure = bool.fromEnvironment('ALLOW_INSECURE');
  final effectiveBase = adjustBaseForEmulator(rawBase);
  final dio = createPlatformDio(
    BaseOptions(
      baseUrl: effectiveBase,
      // Increase defaults to accommodate slow report endpoints (Traccar trips)
      connectTimeout: const Duration(seconds: 30),
      receiveTimeout: const Duration(seconds: 60),
      sendTimeout: const Duration(seconds: 15),
    ),
    allowInsecure: allowInsecure,
  );
  // Register core interceptors FIRST so forced cache (TTL) short-circuits before cookie manager.
  attachCoreInterceptors(dio);
  final cookieJar = ref.watch(authCookieJarProvider);
  dio.interceptors.add(CookieManager(cookieJar));
  return dio;
});

final authServiceProvider = Provider<AuthService>((ref) {
  final dio = ref.watch(dioProvider);
  final jar = ref.watch(authCookieJarProvider);
  return AuthService(dio, jar, ref);
});

final authDebugProvider = StateProvider<List<Map<String, dynamic>>>(
  (_) => const [],
);

class AuthService {
  AuthService(this._dio, this._cookieJar, this._ref);
  final Dio _dio;
  final CookieJar _cookieJar;
  final Ref _ref;
  final _secure = createSecureStorage();
  static const _sessionKey = 'session_cookie_jsessionid';

  /// Attempts to log in; stores only the JSESSIONID value (not entire Set-Cookie headers)
  Future<Map<String, dynamic>> login(String email, String password) async {
    // RESET attempts list immediately so UI shows fresh state
    _ref.read(authDebugProvider.notifier).state = const [];
    final attempts = <Map<String, dynamic>>[];
    void logAttempt(
      String step, {
      int? status,
      String? error,
      String? detail,
      bool success = false,
      Object? dataSample,
    }) {
      attempts.add({
        'step': step,
        'status': status,
        'success': success,
        if (error != null) 'error': error,
        if (detail != null) 'detail': detail,
        if (dataSample != null) 'data': dataSample,
      });
      _ref.read(authDebugProvider.notifier).state =
          List<Map<String, dynamic>>.unmodifiable(attempts);
    }

    Future<Map<String, dynamic>?> tryPost({
      required String label,
      required Map<String, String> body,
      required bool form,
      bool trailingSlash = false,
    }) async {
      final path = trailingSlash ? '/api/session/' : '/api/session';
      try {
        final r = await _dio.post<Map<String, dynamic>>(
          path,
          data: body,
          options: Options(
            contentType: form
                ? Headers.formUrlEncodedContentType
                : 'application/json; charset=UTF-8',
            headers: const {'Accept': 'application/json'},
          ),
        );
        await _storeSessionCookieFromResponseHeaders(r.headers);
        if (r.data is Map) {
          logAttempt(
            label,
            status: r.statusCode,
            success: true,
            dataSample: (r.data! as Map).keys.take(5).join(','),
          );
          return Map<String, dynamic>.from(r.data! as Map);
        }
        logAttempt(
          label,
          status: r.statusCode,
          error: 'non-map ${r.data.runtimeType}',
        );
      } on DioException catch (e) {
        logAttempt(
          label,
          status: e.response?.statusCode,
          error: _shortErr(e),
          detail: e.error?.toString(),
        );
      }
      return null;
    }

    Future<Map<String, dynamic>?> tryBasic({bool trailingSlash = false}) async {
      final path = trailingSlash ? '/api/session/' : '/api/session';
      try {
        final basic = base64Encode(utf8.encode('$email:$password'));
        final r = await _dio.get<Map<String, dynamic>>(
          path,
          options: Options(
            headers: {
              'Authorization': 'Basic $basic',
              'Accept': 'application/json',
            },
          ),
        );
        await _storeSessionCookieFromResponseHeaders(r.headers);
        if (r.data is Map) {
          logAttempt(
            'basic-get${trailingSlash ? '-slash' : ''}',
            status: r.statusCode,
            success: true,
            dataSample: (r.data! as Map).keys.take(5).join(','),
          );
          return Map<String, dynamic>.from(r.data! as Map);
        }
        logAttempt(
          'basic-get${trailingSlash ? '-slash' : ''}',
          status: r.statusCode,
          error: 'non-map',
        );
      } on DioException catch (e) {
        logAttempt(
          'basic-get${trailingSlash ? '-slash' : ''}',
          status: e.response?.statusCode,
          error: _shortErr(e),
          detail: e.error?.toString(),
        );
      }
      return null;
    }

    // Sequence of strategies
    Map<String, dynamic>? userJson;
    userJson ??= await tryPost(
      label: 'form-email',
      body: {'email': email, 'password': password},
      form: true,
    );
    userJson ??= await tryPost(
      label: 'form-user',
      body: {'user': email, 'password': password},
      form: true,
    );
    userJson ??= await tryPost(
      label: 'json-email',
      body: {'email': email, 'password': password},
      form: false,
    );
    userJson ??= await tryPost(
      label: 'json-user',
      body: {'user': email, 'password': password},
      form: false,
    );
    userJson ??= await tryPost(
      label: 'form-email-slash',
      body: {'email': email, 'password': password},
      form: true,
      trailingSlash: true,
    );
    userJson ??= await tryBasic();
    userJson ??= await tryBasic(trailingSlash: true);

    if (userJson != null) {
      // Return the user data from the login response directly
      // Don't call getSession() again as it might return cached/old user data
      return userJson;
    }

    final any401 = attempts.any(
      (a) => a['status'] == 401 || a['status'] == 403,
    );
    final statuses = attempts.map((a) {
      final base =
          '${a['step']}:${a['status']}${a['error'] != null ? '(${a['error']})' : ''}';
      final detail = a['detail'];
      return detail != null ? '$base[$detail]' : base;
    }).join(', ');
    final reason = any401
        ? 'Invalid credentials (401/403). Confirm via web UI.'
        : 'All strategies failed.';
    throw Exception('$reason Attempts: $statuses');
  }

  Future<void> _storeSessionCookieFromHeaders(List<String>? headers) async {
    if (headers == null) return;
    final jsValue = _extractJSessionId(headers);
    if (jsValue != null) {
      await _secure.write(key: _sessionKey, value: jsValue);
    }
  }

  Future<void> _storeSessionCookieFromResponseHeaders(Headers headers) async {
    // Find any header key that case-insensitively matches 'set-cookie'
    final setCookieKey = headers.map.keys.firstWhere(
      (k) => k.toLowerCase() == 'set-cookie',
      orElse: () => '',
    );
    if (setCookieKey.isEmpty) return;
    await _storeSessionCookieFromHeaders(headers.map[setCookieKey]);
  }

  // (retained for possible future centralized mapping if needed)
  // ignore: unused_element
  String _mapDioError(DioException e) => e.message ?? 'network error';

  String _shortErr(DioException e) {
    final code = e.response?.statusCode;
    if (code != null) return '$code:${e.type.name}';
    return e.type.name;
  }

  Future<Map<String, dynamic>> getSession() async {
    final response = await _dio.get<Map<String, dynamic>>('/api/session');
    final data = response.data ?? <String, dynamic>{};
    return Map<String, dynamic>.from(data);
  }

  /// Validate if the current session is still active
  /// Returns user data if session is valid, throws if session is expired/invalid
  Future<Map<String, dynamic>> validateSession() async {
    try {
      // First, rehydrate the session cookie from secure storage
      await rehydrateSessionCookie();

      // Attempt to get session info from server
      final response = await _dio.get<Map<String, dynamic>>(
        '/api/session',
        options: Options(
          validateStatus: (status) => status != null && status < 500,
        ),
      );

      // 401/403 means session is invalid/expired
      if (response.statusCode == 401 || response.statusCode == 403) {
        throw Exception('Session expired or invalid');
      }

      // 200 means session is valid
      if (response.statusCode == 200 && response.data is Map) {
        return Map<String, dynamic>.from(response.data! as Map);
      }

      throw Exception('Unexpected response: ${response.statusCode}');
    } on DioException catch (e) {
      // Network errors, 401, 403, etc.
      if (e.response?.statusCode == 401 || e.response?.statusCode == 403) {
        throw Exception('Session expired or invalid');
      }
      throw Exception('Session validation failed: ${_shortErr(e)}');
    }
  }

  /// Check if we have a stored session token
  Future<bool> hasStoredSession() async {
    final token = await _secure.read(key: _sessionKey);
    return token != null && token.isNotEmpty;
  }

  /// Debug helper: perform raw GET /api/session returning status & type without throwing
  Future<Map<String, dynamic>> debugRawSessionGet() async {
    try {
      final r = await _dio.get<Map<String, dynamic>>('/api/session');
      return {
        'status': r.statusCode,
        'rawType': r.data.runtimeType.toString(),
        'isMap': r.data is Map,
      };
    } on DioException catch (e) {
      return {
        'error': _shortErr(e),
        'underlying': e.error?.toString(),
        'code': e.response?.statusCode,
      };
    } catch (e) {
      return {'error': e.toString()};
    }
  }

  /// Lightweight connectivity / auth preflight: hits /api/server (doesn't require auth)
  Future<String> preflightPing() async {
    try {
      final r = await _dio.get<Map<String, dynamic>>('/api/server');
      if (r.statusCode == 200) {
        return 'OK';
      }
      return 'Unexpected status: ${r.statusCode}';
    } on DioException catch (e) {
      return 'Ping failed: ${e.message}';
    }
  }

  /// Deep diagnostics: raw TCP socket connect + HTTP ping
  Future<Map<String, dynamic>> lowLevelDiagnostics() async {
    final base = _dio.options.baseUrl;
    final uri = Uri.parse(base);
    final host = uri.host;
    final port = uri.hasPort ? uri.port : (uri.scheme == 'https' ? 443 : 80);
    final result = <String, dynamic>{
      'baseUrl': base,
      'host': host,
      'port': port,
    };
    // Socket test (IO only; stubbed on web)
    final probe = await socketProbe(host, port);
    result.addAll(probe);
    // HTTP ping
    try {
      final ping = await preflightPing();
      result['httpPing'] = ping;
    } catch (e) {
      result['httpPing'] = 'error: $e';
    }
    return result;
  }

  Future<void> logout() async {
    try {
      await _dio.delete<void>('/api/session');
    } finally {
      await _secure.delete(key: _sessionKey);
      try {
        // Also clear cookies from the cookie jar to remove any residual session state
        await _cookieJar.deleteAll();
      } catch (e) {
        debugPrint('[AuthService] ⚠️ Failed to clear cookie jar during logout: $e');
      }
    }
  }

  /// Clear stored session cookie and reset cookie jar (useful before new login attempts)
  Future<void> clearStoredSession() async {
    await _secure.delete(key: _sessionKey);
    // Clear all cookies from the jar to ensure fresh login
    try {
      await _cookieJar.deleteAll();
    } catch (_) {
      // Ignore cookie jar clear errors
    }
    // Also clear any debug attempts
    _ref.read(authDebugProvider.notifier).state = const [];
  }

  /// Rehydrate cookie jar from secure storage before making requests (silent session restore)
  Future<void> rehydrateSessionCookie() async {
    final jsValue = await _secure.read(key: _sessionKey);
    if (jsValue == null) return;
    try {
      final uri = Uri.parse(_dio.options.baseUrl);
      final cookie = Cookie('JSESSIONID', jsValue)
        ..domain = uri.host
        ..path = '/';
      // Add cookie to jar (host-specific)
      await _cookieJar.saveFromResponse(
        Uri(scheme: uri.scheme, host: uri.host, port: uri.port, path: '/'),
        [cookie],
      );
    } catch (_) {
      // Ignore malformed base URL or cookie errors.
    }
  }

  /// Extracts JSESSIONID value from Set-Cookie header lines
  String? _extractJSessionId(List<String> headers) {
    for (final line in headers) {
      final parts = line.split(';');
      if (parts.isEmpty) continue;
      final kv = parts.first.trim();
      final idx = kv.indexOf('=');
      if (idx == -1) continue;
      final name = kv.substring(0, idx);
      final value = kv.substring(idx + 1);
      if (name.toUpperCase() == 'JSESSIONID') {
        return value;
      }
    }
    return null;
  }

  /// Exposes the stored JSESSIONID value (if any). Useful for WebSocket Cookie auth.
  Future<String?> getStoredJSessionId() async {
    try {
      return await _secure.read(key: _sessionKey);
    } catch (_) {
      return null;
    }
  }
}
