import 'package:dio/dio.dart';

import 'http_cache_interceptor.dart';
import 'forced_cache_interceptor.dart';

/// Builds a Dio instance with common interceptors.
///
/// Note: This file was empty; if your app constructs Dio elsewhere (e.g., in
/// AuthService), you can call [attachCoreInterceptors] on that Dio to avoid
/// creating another instance and preserve cookie/auth behavior.
class DioClient {
	DioClient();

	Dio build({required String baseUrl, Duration? connectTimeout, Duration? receiveTimeout}) {
		final dio = Dio(BaseOptions(
			baseUrl: baseUrl,
			connectTimeout: connectTimeout ?? const Duration(seconds: 8),
			receiveTimeout: receiveTimeout ?? const Duration(seconds: 12),
		));
		attachCoreInterceptors(dio);
		return dio;
	}
}

/// Registers core interceptors (order matters for request/response processing).
void attachCoreInterceptors(Dio dio) {
	// Forced local cache (TTL-based) for static GET endpoints
	if (!_contains<ForcedLocalCacheInterceptor>(dio.interceptors)) {
		dio.interceptors.insert(0, ForcedLocalCacheInterceptor());
	}
	// HTTP conditional cache (ETag/If-Modified-Since) for revalidation when TTL expires
	if (!_contains<HttpCacheInterceptor>(dio.interceptors)) {
		dio.interceptors.add(HttpCacheInterceptor());
	}
}

bool _contains<T>(Interceptors interceptors) {
	return interceptors.any((i) => i is T);
}

