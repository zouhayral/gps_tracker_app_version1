import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../services/auth_service.dart';
import '../../../features/dashboard/controller/devices_notifier.dart';
import 'auth_state.dart';

final authNotifierProvider = StateNotifierProvider<AuthNotifier, AuthState>((ref) {
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
			final user = await _service.login(email, password);
			final prefs = await SharedPreferences.getInstance();
			await prefs.setString(_lastEmailKey, email);
			state = AuthAuthenticated(email: email, userId: user['id'] as int, userJson: user);
			
			// Clear old devices data and refresh for new user
			_ref.read(devicesNotifierProvider.notifier).clear();
			// Delay slightly to ensure auth state is updated before fetching devices
			Future.delayed(const Duration(milliseconds: 100), () {
				_ref.read(devicesNotifierProvider.notifier).refresh();
			});
		} catch (e) {
			state = AuthUnauthenticated(message: 'Login failed: ${e.toString()}', lastEmail: email);
		}
	}

	/// Attempt to restore session from stored cookie (manual operation)
	Future<void> tryRestoreSession() async {
		final current = state;
		if (current is! AuthInitial || current.lastEmail == null) return;
		
		try {
			await _service.rehydrateSessionCookie();
			final user = await _service.getSession();
			state = AuthAuthenticated(email: current.lastEmail!, userId: user['id'] as int, userJson: user);
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
		
		// Clear devices data when logging out
		_ref.read(devicesNotifierProvider.notifier).clear();
		
		state = AuthUnauthenticated(lastEmail: lastEmail);
	}
}
