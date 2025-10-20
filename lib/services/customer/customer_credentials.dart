/// Customer credentials model and provider
///
/// Holds the last-used email/password for convenience (optional).
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Simple immutable credentials model
class CustomerCredentials {
  const CustomerCredentials({required this.email, required this.password});
  final String email;
  final String password;

  CustomerCredentials copyWith({String? email, String? password}) =>
      CustomerCredentials(
        email: email ?? this.email,
        password: password ?? this.password,
      );

  @override
  String toString() => 'CustomerCredentials(email: $email, password: ***)';
}

/// Optional credentials store; may be null when user is logged out
final customerCredentialsProvider =
    StateProvider<CustomerCredentials?>((_) => null);
