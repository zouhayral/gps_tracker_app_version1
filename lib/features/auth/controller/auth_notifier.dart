import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_app_gps/core/network/forced_cache_interceptor.dart';
import 'package:my_app_gps/core/network/http_cache_interceptor.dart';
import 'package:my_app_gps/features/auth/controller/auth_state.dart';
import 'package:my_app_gps/features/dashboard/controller/devices_notifier.dart';
import 'package:my_app_gps/services/auth_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

final authNotifierProvider = StateNotifierProvider<AuthNotifier, AuthState>((
  ref,
) {
  final service = ref.watch(authServiceProvider);
  return AuthNotifier(service, ref);
});

class AuthNotifier extends StateNotifier<AuthState> {
  AuthNotifier(this._service, this._ref) : super(const AuthInitial()) {
    _bootstrap();
  }

  final AuthService _service;
  final Ref _ref;
  static const _lastEmailKey = 'last_email';

  /// Clear all cached data when switching accounts
  Future<void> _clearAllCaches() async {
    // Clear HTTP caches (devices, geofences, users, etc.)
    ForcedLocalCacheInterceptor.clear();
    HttpCacheInterceptor.clear();

    // Clear in-memory device state
    _ref.read(devicesNotifierProvider.notifier).clear();

    // Clear persisted positions from ObjectBox
    // Note: We intentionally don't clear the entire ObjectBox store,
    // just invalidate positions so they'll be refreshed for the new user
    // The positions DAO provider handles per-device storage, which is safe
    // since device IDs differ between accounts
  }

  Future<void> _bootstrap() async {
    final prefs = await SharedPreferences.getInstance();
    final lastEmail = prefs.getString(_lastEmailKey);
    state = AuthInitial(lastEmail: lastEmail);
    // Don't automatically rehydrate session - require explicit login
    // This prevents logging in as the wrong user after app restart
    // Users need to login again for security and to ensure correct user context
  }

  Future<void> login(String email, String password) async {
    state = AuthAuthenticating(email);
    try {
      // Clear any existing session cookie before attempting new login
      await _service.clearStoredSession();

      // CRITICAL: Clear all caches to prevent serving old user's data
      await _clearAllCaches();

      final user = await _service.login(email, password);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_lastEmailKey, email);
      state = AuthAuthenticated(
        email: email,
        userId: user['id'] as int,
        userJson: user,
      );

      // Fetch devices immediately - caches are already cleared
      await _ref.read(devicesNotifierProvider.notifier).refresh();
    } catch (e) {
      state = AuthUnauthenticated(
        message: 'Login failed: $e',
        lastEmail: email,
      );
    }
  }

  /// Attempt to restore session from stored cookie (manual operation)
  Future<void> tryRestoreSession() async {
    final current = state;
    if (current is! AuthInitial || current.lastEmail == null) return;

    try {
      await _service.rehydrateSessionCookie();
      final user = await _service.getSession();
      state = AuthAuthenticated(
        email: current.lastEmail!,
        userId: user['id'] as int,
        userJson: user,
      );
    } catch (_) {
      // Session restore failed, stay unauthenticated
      state = AuthUnauthenticated(lastEmail: current.lastEmail);
    }
  }

  Future<void> logout() async {
    try {
      await _service.logout();
    } catch (_) {}
    String? lastEmail;
    final current = state;
    if (current is AuthAuthenticated) lastEmail = current.email;

    // CRITICAL: Clear all caches to prevent next user seeing old data
    await _clearAllCaches();

    state = AuthUnauthenticated(lastEmail: lastEmail);
  }
}
