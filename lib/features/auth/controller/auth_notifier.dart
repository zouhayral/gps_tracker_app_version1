import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
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
  static const _secure = FlutterSecureStorage();
  static const _lastEmailKey = 'last_email';
  static const _storedEmailKey = 'stored_email';
  // REMOVED: _storedPasswordKey - we no longer store passwords!

  // Safe wrappers around FlutterSecureStorage to avoid plugin exceptions
  Future<String?> _readStoredEmailSafe() async {
    try {
      return await _secure.read(key: _storedEmailKey);
    } catch (_) {
      return null;
    }
  }

  Future<void> _writeStoredEmailSafe(String email) async {
    try {
      await _secure.write(key: _storedEmailKey, value: email);
    } catch (_) {
      // Ignore in environments without secure storage (tests)
    }
  }

  Future<void> _deleteStoredEmailSafe() async {
    try {
      await _secure.delete(key: _storedEmailKey);
    } catch (_) {
      // Ignore in environments without secure storage (tests)
    }
  }

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

  /// Bootstrap: Auto-login with stored session token if available
  Future<void> _bootstrap() async {
    final prefs = await SharedPreferences.getInstance();
    final lastEmail = prefs.getString(_lastEmailKey);

    // Try to retrieve stored email (for display purposes), tolerate plugin absence
    final storedEmail = await _readStoredEmailSafe();

    // Check if we have a stored session token (defensive against unexpected errors)
    var hasSession = false;
    try {
      hasSession = await _service.hasStoredSession();
    } catch (_) {
      hasSession = false;
    }

    // If we have a stored session token, attempt to validate it
    if (hasSession && storedEmail != null && storedEmail.isNotEmpty) {
      state = AuthValidatingSession(storedEmail);

      try {
        // Validate the session token with the server
        final user = await _service.validateSession();

        state = AuthAuthenticated(
          email: storedEmail,
          userId: user['id'] as int,
          userJson: user,
        );

        // Fetch devices immediately after successful session validation
        await _ref.read(devicesNotifierProvider.notifier).refresh();
        return;
      } catch (e) {
        // Session validation failed - token is expired or invalid
        await _clearStoredCredentials();
        state = AuthSessionExpired(
          email: storedEmail,
          message: 'Your session has expired. Please login again.',
        );
        return;
      }
    }

    // No stored session - show login screen with last email
    state = AuthInitial(lastEmail: lastEmail ?? storedEmail);
  }

  /// Clear stored credentials from secure storage
  /// Note: We only store email now, not passwords. Session token is managed by AuthService.
  Future<void> _clearStoredCredentials() async {
    await _deleteStoredEmailSafe();
    // Clear the session token as well
    await _service.clearStoredSession();
  }

  Future<void> login(String email, String password) async {
    state = AuthAuthenticating(email);
    try {
      // Clear any existing session cookie before attempting new login
      await _service.clearStoredSession();

      // CRITICAL: Clear all caches to prevent serving old user's data
      await _clearAllCaches();

      // Login and get user data - session token is automatically stored by AuthService
      final user = await _service.login(email, password);

  // Store only the email securely (NOT the password!).
  // Use a safe wrapper to avoid plugin exceptions in unsupported environments.
  await _writeStoredEmailSafe(email);

      // Store last email in SharedPreferences (for UI convenience)
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
      // Clear any partially stored data on login failure
      await _clearStoredCredentials();

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

  /// Re-authenticate after session expiry
  /// Used when session expires and user needs to login again
  Future<void> reAuthenticate(String password) async {
    final current = state;
  String? email;

    if (current is AuthSessionExpired) {
      email = current.email;
    } else if (current is AuthUnauthenticated && current.lastEmail != null) {
      email = current.lastEmail;
    }

    if (email == null || email.isEmpty) {
      state = const AuthUnauthenticated(
        message: 'Email not found. Please login again.',
      );
      return;
    }

    // Use the regular login flow
    await login(email, password);
  }

  /// Validate current session (useful for checking before critical operations)
  Future<bool> validateCurrentSession() async {
    try {
      await _service.validateSession();
      return true;
    } catch (_) {
      // Session is invalid - transition to expired state
      final current = state;
      if (current is AuthAuthenticated) {
        state = AuthSessionExpired(
          email: current.email,
          message: 'Your session has expired. Please login again.',
        );
      }
      return false;
    }
  }

  Future<void> logout() async {
    try {
      await _service.logout();
    } catch (_) {}
    String? lastEmail;
    final current = state;
    if (current is AuthAuthenticated) lastEmail = current.email;

    // Clear stored credentials to prevent auto-login
    await _clearStoredCredentials();

    // CRITICAL: Clear all caches to prevent next user seeing old data
    await _clearAllCaches();

    state = AuthUnauthenticated(lastEmail: lastEmail);
  }
}
