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

class AuthAuthenticated extends AuthState {
  final String email;
  final int userId;
  final Map<String, dynamic> userJson;
  const AuthAuthenticated({
    required this.email,
    required this.userId,
    required this.userJson,
  });
}

class AuthUnauthenticated extends AuthState {
  final String? message;
  final String? lastEmail;
  const AuthUnauthenticated({this.message, this.lastEmail});
}
