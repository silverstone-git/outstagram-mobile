/// outsie `UserPublic`.
class AppUser {
  const AppUser({required this.userId, required this.username, required this.fullname, this.bio});

  final int userId;
  final String username;
  final String fullname;
  final String? bio;

  factory AppUser.fromJson(Map<String, dynamic> j) => AppUser(
        userId: j['user_id'] as int,
        username: j['username'] as String,
        fullname: j['fullname'] as String,
        bio: j['bio'] as String?,
      );

  Map<String, dynamic> toJson() => {'user_id': userId, 'username': username, 'fullname': fullname, 'bio': bio};
}

/// A signed-in device: short-lived access token + rotating refresh token.
class Session {
  const Session({required this.accessToken, required this.refreshToken, required this.expiresAt, required this.user});

  final String accessToken;
  final String? refreshToken;
  final DateTime expiresAt;
  final AppUser user;

  /// Refresh a minute early so a request never leaves with a token that dies in flight.
  bool get needsRefresh => DateTime.now().isAfter(expiresAt.subtract(const Duration(minutes: 1)));

  /// From a sign-in or refresh response: {access_token, expires_in, refresh_token, user}.
  factory Session.fromAuthResponse(Map<String, dynamic> j) => Session(
        accessToken: j['access_token'] as String,
        refreshToken: j['refresh_token'] as String?,
        expiresAt: DateTime.now().add(Duration(seconds: (j['expires_in'] as int?) ?? 1800)),
        user: AppUser.fromJson(j['user'] as Map<String, dynamic>),
      );

  factory Session.fromJson(Map<String, dynamic> j) => Session(
        accessToken: j['access_token'] as String,
        refreshToken: j['refresh_token'] as String?,
        expiresAt: DateTime.parse(j['expires_at'] as String),
        user: AppUser.fromJson(j['user'] as Map<String, dynamic>),
      );

  Map<String, dynamic> toJson() => {
        'access_token': accessToken,
        'refresh_token': refreshToken,
        'expires_at': expiresAt.toIso8601String(),
        'user': user.toJson(),
      };
}
