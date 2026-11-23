import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_web_auth_2/flutter_web_auth_2.dart';

import '../config/env.dart';
import '../net/api_error.dart';
import 'google_auth.dart';
import 'session.dart';

/// Sign-in calls. Uses a bare Dio (no auth interceptor) so refreshing can never recurse.
class AuthRepository {
  AuthRepository(this._dio);

  final Dio _dio;

  Future<T> _call<T>(Future<T> Function() f) async {
    try {
      return await f();
    } catch (e) {
      throw ApiException.from(e);
    }
  }

  Future<Session> _session(Future<Response<dynamic>> req) =>
      _call(() async => Session.fromAuthResponse((await req).data as Map<String, dynamic>));

  Future<Session> login(String username, String password) => _session(_dio.post(
        '/login',
        data: {'username': username, 'password': password},
        options: Options(contentType: Headers.formUrlEncodedContentType),
      ));

  Future<void> register({
    required String fullname,
    required String username,
    required String email,
    required String password,
    required DateTime dateOfBirth,
    String? bio,
  }) =>
      _call(() => _dio.post('/register', data: {
            'fullname': fullname,
            'username': username,
            'email': email,
            'password': password,
            'bio': bio ?? '',
            'date_of_birth': dateOfBirth.toIso8601String().substring(0, 10),
          }));

  /// Native: Google ID token -> POST /auth/google.
  Future<Session> googleNative() async {
    final idToken = await GoogleAuth.idToken();
    return _session(_dio.post('/auth/google', data: {'id_token': idToken, 'nonce': GoogleAuth.rawNonce}));
  }

  /// Fallback: the web's Supabase PKCE flow in a Custom Tab, back via `<scheme>://auth-callback`.
  /// Needs that callback URL in the Supabase project's Auth redirect allow-list.
  Future<Session> googleBrowser() async {
    final providers = await _call(() => _dio.get('/auth/providers'));
    final supabaseUrl = (providers.data as Map)['supabase_url'] as String?;
    if (supabaseUrl == null) throw ApiException('Google sign-in is not available right now');

    final verifier = randomUrlSafe(32);
    final challenge = base64Url.encode(sha256.convert(utf8.encode(verifier)).bytes).replaceAll('=', '');
    final callback = '${Env.authScheme}://auth-callback';
    final url = Uri.parse('$supabaseUrl/auth/v1/authorize').replace(queryParameters: {
      'provider': 'google',
      'redirect_to': callback,
      'code_challenge': challenge,
      'code_challenge_method': 's256',
    });

    final String result;
    try {
      result = await FlutterWebAuth2.authenticate(url: url.toString(), callbackUrlScheme: Env.authScheme);
    } on PlatformException catch (e) {
      if (e.code == 'CANCELED') throw const SignInCancelled();
      rethrow;
    }
    final back = Uri.parse(result);
    final params = {...back.queryParameters, ...Uri.splitQueryString(back.fragment)};
    final error = params['error_description'] ?? params['error'];
    if (error != null) throw ApiException(error);
    final code = params['code'];
    if (code == null) throw ApiException('Sign-in did not complete, please try again');
    return _session(_dio.post('/auth/supabase', data: {'auth_code': code, 'code_verifier': verifier}));
  }

  Future<Session> refresh(String refreshToken) =>
      _session(_dio.post('/auth/refresh', data: {'refresh_token': refreshToken}));

  Future<void> logout(String refreshToken) async {
    try {
      await _dio.post('/auth/logout', data: {'refresh_token': refreshToken});
    } catch (_) {
      // Best effort: the local sign-out happens regardless.
    }
  }
}
