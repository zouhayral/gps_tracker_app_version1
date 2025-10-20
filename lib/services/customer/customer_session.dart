/// Customer session provider
///
/// Exposes a lightweight session model derived from AuthService.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_app_gps/services/auth_service.dart';

class CustomerSession {
  const CustomerSession({
    required this.isAuthenticated,
    required this.userData,
    this.sessionId,
  });

  final bool isAuthenticated;
  final Map<String, dynamic>? userData;
  final String? sessionId; // JSESSIONID if available
}

/// Attempts to restore/validate session using AuthService and secure storage.
final customerSessionProvider = FutureProvider.autoDispose<CustomerSession>((ref) async {
  final auth = ref.watch(authServiceProvider);

  try {
    // Rehydrate cookie into Dio's cookie jar (no-op if absent)
    await auth.rehydrateSessionCookie();

    // Validate current session on server. If valid, returns user data.
    final user = await auth.validateSession();

    // Expose basic information; sessionId is pulled from secure storage
    final js = await auth.getStoredJSessionId();

    if (kDebugMode) {
      // ignore: avoid_print
      print('[CustomerSession] validated. user keys: ${user.keys.take(5).join(',')}');
    }

    return CustomerSession(
      isAuthenticated: true,
      userData: user,
      sessionId: js,
    );
  } catch (e) {
    if (kDebugMode) {
      // ignore: avoid_print
      print('[CustomerSession] not authenticated: $e');
    }
    return const CustomerSession(isAuthenticated: false, userData: null);
  }
});
