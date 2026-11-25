import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/auth_controller.dart';
import '../config/device_tz.dart';
import '../config/env.dart';
import 'api_error.dart';

/// Attaches the access token, refreshes it ahead of expiry, and on a 401 refreshes once and retries.
class AuthInterceptor extends Interceptor {
  AuthInterceptor(this._ref, this._dio);

  final Ref _ref;
  final Dio _dio;

  AuthController get _auth => _ref.read(authControllerProvider.notifier);

  @override
  Future<void> onRequest(RequestOptions options, RequestInterceptorHandler handler) async {
    var s = _auth.current;
    if (s != null && s.needsRefresh) s = await _auth.refresh();
    if (s != null) options.headers['Authorization'] = 'Bearer ${s.accessToken}';
    handler.next(options);
  }

  @override
  Future<void> onError(DioException err, ErrorInterceptorHandler handler) async {
    final opts = err.requestOptions;
    final sent = opts.headers['Authorization'] as String?;
    if (err.response?.statusCode != 401 || sent == null || opts.extra['retried'] == true) {
      return handler.next(err);
    }
    // Another request may already have refreshed; only refresh if we sent the current token.
    var s = _auth.current;
    if (s == null) return handler.next(err);
    if (sent == 'Bearer ${s.accessToken}') s = await _auth.refresh();
    if (s == null) return handler.next(err); // signed out; the router takes the user to sign-in
    try {
      opts.extra['retried'] = true;
      opts.headers['Authorization'] = 'Bearer ${s.accessToken}';
      handler.resolve(await _dio.fetch<dynamic>(opts));
    } on DioException catch (e) {
      handler.next(e);
    }
  }
}

final dioProvider = Provider<Dio>((ref) {
  final dio = Dio(
    BaseOptions(
      baseUrl: Env.apiBase,
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 60),
      headers: {'X-Timezone': DeviceTimezone.name}, // streak days follow the user's calendar
    ),
  );
  dio.interceptors.add(AuthInterceptor(ref, dio));
  return dio;
});

final apiProvider = Provider<Api>((ref) => Api(ref.watch(dioProvider)));

/// Thin wrapper: returns decoded JSON, throws [ApiException].
class Api {
  Api(this.dio);

  final Dio dio;

  Future<T> _wrap<T>(Future<Response<dynamic>> req) async {
    try {
      return (await req).data as T;
    } catch (e) {
      throw ApiException.from(e);
    }
  }

  Future<T> get<T>(String path, {Map<String, dynamic>? query}) => _wrap(dio.get(path, queryParameters: query));
  Future<T> post<T>(String path, {Object? data, Map<String, dynamic>? query}) =>
      _wrap(dio.post(path, data: data, queryParameters: query));
  Future<T> put<T>(String path, {Object? data}) => _wrap(dio.put(path, data: data));
  Future<T> delete<T>(String path, {Map<String, dynamic>? query}) => _wrap(dio.delete(path, queryParameters: query));
}
