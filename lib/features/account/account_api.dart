import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/auth_controller.dart';
import '../../core/net/api_client.dart';

/// `GET /me`: the signed-in account, with its email and whether it's confirmed.
class Me {
  const Me({
    required this.userId,
    required this.username,
    required this.email,
    required this.emailVerified,
    this.verificationRequired = true,
  });

  factory Me.fromJson(Map<String, dynamic> j) => Me(
    userId: (j['user_id'] as num).toInt(),
    username: '${j['username']}',
    email: '${j['email'] ?? ''}',
    emailVerified: j['email_verified'] == true,
    verificationRequired: j['verification_required'] != false,
  );

  final int userId;
  final String username;
  final String email;
  final bool emailVerified;

  /// The server refuses posting / uploads / the tutor until the email is confirmed.
  final bool verificationRequired;

  /// Show the warning badge and banners.
  bool get needsVerification => verificationRequired && !emailVerified;
}

/// Re-fetched per signed-in user. Null while signed out.
final meProvider = FutureProvider<Me?>((ref) async {
  final uid = ref.watch(authControllerProvider.select((s) => s.value?.user.userId));
  if (uid == null) return null;
  return Me.fromJson(await ref.read(apiProvider).get<Map<String, dynamic>>('/me'));
});

final accountApiProvider = Provider<AccountApi>((ref) => AccountApi(ref));

class AccountApi {
  AccountApi(this._ref);

  final Ref _ref;
  Api get _api => _ref.read(apiProvider);

  /// Emails a code to the account's current address.
  Future<void> sendVerifyCode() => _api.post<dynamic>('/me/email/verify/start');

  Future<Me> verify(String code) async {
    final me = Me.fromJson(await _api.post<Map<String, dynamic>>('/me/email/verify', data: {'code': code}));
    _ref.invalidate(meProvider);
    return me;
  }

  /// Emails a code to the new address (409 if another account has it).
  Future<void> sendChangeCode(String email) =>
      _api.post<dynamic>('/me/email/change/start', data: {'email': email.trim().toLowerCase()});

  Future<Me> changeEmail(String email, String code) async {
    final me = Me.fromJson(
      await _api.post<Map<String, dynamic>>(
        '/me/email/change',
        data: {'email': email.trim().toLowerCase(), 'code': code},
      ),
    );
    _ref.invalidate(meProvider);
    return me;
  }
}
