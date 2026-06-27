class AuthUser {
  const AuthUser({
    required this.id,
    required this.email,
    required this.displayName,
    required this.trustedModeEnabled,
    this.emailVerifiedAt,
  });

  final String id;
  final String email;
  final String displayName;
  final bool trustedModeEnabled;
  final String? emailVerifiedAt;

  factory AuthUser.fromJson(Map<String, Object?> json) {
    return AuthUser(
      id: json['id'] as String,
      email: json['email'] as String,
      displayName: json['displayName'] as String,
      trustedModeEnabled: json['trustedModeEnabled'] as bool,
      emailVerifiedAt: json['emailVerifiedAt'] as String?,
    );
  }
}

class AuthSession {
  const AuthSession({
    required this.accessToken,
    required this.refreshToken,
    required this.user,
  });

  final String accessToken;
  final String refreshToken;
  final AuthUser user;

  factory AuthSession.fromJson(Map<String, Object?> json) {
    return AuthSession(
      accessToken: json['accessToken'] as String,
      refreshToken: json['refreshToken'] as String,
      user: AuthUser.fromJson(json['user'] as Map<String, Object?>),
    );
  }
}
