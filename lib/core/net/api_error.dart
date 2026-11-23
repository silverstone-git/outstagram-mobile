import 'package:dio/dio.dart';

/// Any failed outsie call, with FastAPI's `detail` decoded.
///
/// `detail` is a string, a list (422 validation errors) or an object; paywall responses carry
/// `{code, message, upgrade: true, ...}` (429 ai_quota, 402 tutor_threads|tutor_storage, 413 media_too_large).
class ApiException implements Exception {
  ApiException(this.message, {this.status, this.code, this.detail});

  final String message;
  final int? status;
  final String? code;
  final Object? detail;

  bool get isPaywall => detail is Map && (detail as Map)['upgrade'] == true;
  bool get isUnauthorized => status == 401;
  bool get isNetwork => status == null;

  factory ApiException.from(Object error) {
    if (error is ApiException) return error;
    if (error is! DioException) return ApiException(error.toString());
    final res = error.response;
    if (res == null) {
      return ApiException(switch (error.type) {
        DioExceptionType.connectionTimeout || DioExceptionType.receiveTimeout => 'The server is taking too long. Try again.',
        _ => 'No connection. Check your internet and try again.',
      });
    }
    final data = res.data;
    final detail = data is Map ? data['detail'] : null;
    return ApiException(
      _message(detail) ?? 'Something went wrong (${res.statusCode})',
      status: res.statusCode,
      code: detail is Map ? detail['code'] as String? : null,
      detail: detail,
    );
  }

  static String? _message(Object? detail) => switch (detail) {
        String s => s,
        Map m => (m['message'] ?? m['detail'])?.toString(),
        List l when l.isNotEmpty && l.first is Map => _validation(l.first as Map),
        _ => null,
      };

  static String _validation(Map e) {
    final loc = (e['loc'] as List?)?.lastOrNull;
    return loc == null ? '${e['msg']}' : '$loc: ${e['msg']}';
  }

  @override
  String toString() => message;
}
