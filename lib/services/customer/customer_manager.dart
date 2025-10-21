/// CustomerManager offers high-level login/logout that coordinates AuthService
/// and local credential storage for examples.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_app_gps/services/auth_service.dart';
import 'package:my_app_gps/services/customer/customer_credentials.dart';
import 'package:my_app_gps/services/customer/customer_session.dart';

class CustomerManager {
  CustomerManager(this._ref);
  final Ref _ref;

  /// Perform login via AuthService and persist credentials for convenience.
  Future<void> loginCustomer({required String email, required String password}) async {
    final auth = _ref.read(authServiceProvider);

    if (kDebugMode) {
      // ignore: avoid_print
      print('[CustomerManager] Login attempt for $email');
    }

    // Clear any stale session/cookies before a new login
    await auth.clearStoredSession();

    // Execute login; AuthService stores JSESSIONID on success and returns user JSON
    final _ = await auth.login(email, password);

    // Save credentials to provider for UX convenience
    _ref.read(customerCredentialsProvider.notifier).state =
        CustomerCredentials(email: email, password: password);

    // Trigger session recomputation for dependents
    _ref.invalidate(customerSessionProvider);
  }

  /// Logout: clear session on server and local secure storage; invalidate dependents.
  Future<void> logoutCustomer() async {
    final auth = _ref.read(authServiceProvider);
    try {
      await auth.logout();
    } finally {
      _ref.read(customerCredentialsProvider.notifier).state = null;
      _ref.invalidate(customerSessionProvider);
    }
    if (kDebugMode) {
      // ignore: avoid_print
      print('[CustomerManager] Logged out');
    }
  }
}

final customerManagerProvider = Provider<CustomerManager>(CustomerManager.new);
