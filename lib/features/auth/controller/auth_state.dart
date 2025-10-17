sealed class AuthState {
  const AuthState();
}

class AuthInitial extends AuthState {
  final String? lastEmail;
  const AuthInitial({this.lastEmail});
}

class AuthAuthenticating extends AuthState {
  final String email;
  const AuthAuthenticating(this.email);
}

class AuthValidatingSession extends AuthState {
  final String email;
  const AuthValidatingSession(this.email);
}

class AuthAuthenticated extends AuthState {
  final String email;
  final int userId;
  final Map<String, dynamic> userJson;
  final DateTime? sessionExpiresAt;
  const AuthAuthenticated({
    required this.email,
    required this.userId,
    required this.userJson,
    this.sessionExpiresAt,
  });
}

class AuthSessionExpired extends AuthState {
  final String email;
  final String? message;
  const AuthSessionExpired({
    required this.email,
    this.message,
  });
}

class AuthUnauthenticated extends AuthState {
  final String? message;
  final String? lastEmail;
  final bool isSessionExpired;
  const AuthUnauthenticated({
    this.message,
    this.lastEmail,
    this.isSessionExpired = false,
  });
}
