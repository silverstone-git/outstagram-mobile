import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/net/api_client.dart';
import '../../core/net/api_error.dart';
import 'models.dart';

final socialApiProvider = Provider<SocialApi>((ref) => SocialApi(ref.watch(apiProvider)));

/// A file ready to upload (already compressed).
class UploadFile {
  const UploadFile({required this.bytes, required this.filename, required this.mime});

  final Uint8List bytes;
  final String filename;
  final String mime;
}

class SocialApi {
  SocialApi(this._api);

  final Api _api;

  List<Post> _posts(List<dynamic> l) => [for (final p in l) Post.fromJson(p as Map<String, dynamic>)];

  Future<List<Post>> feed(int page, {PostCategory? category}) async => _posts(await _api.get<List<dynamic>>(
      '/feed', query: {'page': page, 'category': ?category?.label}));

  Future<List<Post>> explore(int page, {PostCategory? category}) async => _posts(await _api.get<List<dynamic>>(
      '/explore', query: {'page': page, 'category': ?category?.label}));

  Future<List<Post>> userPosts(String username, int page) async =>
      _posts(await _api.get<List<dynamic>>('/users/${Uri.encodeComponent(username)}/posts/$page'));

  Future<void> like(String postId) => _api.post<dynamic>('/posts/$postId/like');

  Future<void> unlike(String postId) => _api.delete<dynamic>('/posts/$postId/like');

  Future<void> deletePost(String postId) => _api.delete<dynamic>('/posts/$postId');

  Future<List<Comment>> comments(String postId, int page) async => [
        for (final c in await _api.get<List<dynamic>>('/posts/$postId/comments/$page'))
          Comment.fromJson(c as Map<String, dynamic>),
      ];

  /// Returns the new comment's id (so it can be deleted right away).
  Future<int?> addComment(String postId, String content) async {
    final r = await _api.post<dynamic>('/posts/$postId/comment', data: {'content': content});
    return r is Map ? r['comment_id'] as int? : null;
  }

  /// The comment's author or the post's author.
  Future<void> deleteComment(String postId, int commentId) =>
      _api.delete<dynamic>('/posts/$postId/comments/$commentId');

  /// One post (counts included), e.g. from a shared link.
  Future<Post> post(String postId) async =>
      Post.fromJson(await _api.get<Map<String, dynamic>>('/posts/${Uri.encodeComponent(postId)}'));

  Future<List<UserSummary>> searchUsers(String q) async => [
        for (final u in await _api.get<List<dynamic>>('/users/search', query: {'q': q}))
          UserSummary.fromJson(u as Map<String, dynamic>),
      ];

  Future<Profile> profile(String username) async =>
      Profile.fromJson(await _api.get<Map<String, dynamic>>('/users/${Uri.encodeComponent(username)}'));

  Future<void> follow(String username) => _api.post<dynamic>('/users/${Uri.encodeComponent(username)}/follow');

  Future<List<FollowRequest>> followRequests() async => [
        for (final r in await _api.get<List<dynamic>>('/follow-requests'))
          FollowRequest.fromJson(r as Map<String, dynamic>),
      ];

  Future<void> approve(int requestId) => _api.post<dynamic>('/request-approve/$requestId');

  /// Decline a request addressed to you (they can ask again later).
  Future<void> reject(int requestId) => _api.post<dynamic>('/request-reject/$requestId');

  /// Unfollow, or cancel a pending request.
  Future<void> unfollow(String username) => _api.delete<dynamic>('/users/${Uri.encodeComponent(username)}/follow');

  /// Make someone stop following you.
  Future<void> removeFollower(String username) =>
      _api.delete<dynamic>('/me/followers/${Uri.encodeComponent(username)}');

  /// `which` is `followers` or `following`; 30 per page.
  Future<List<UserSummary>> followList(String username, String which, int page) async => [
        for (final u in await _api.get<List<dynamic>>('/users/${Uri.encodeComponent(username)}/$which/$page'))
          UserSummary.fromJson(u as Map<String, dynamic>),
      ];

  /// Edit your name and/or bio ("" clears the bio).
  Future<void> updateProfile({String? fullname, String? bio}) =>
      _api.put<dynamic>('/me', data: {'fullname': ?fullname, 'bio': ?bio});

  Future<List<String>> trending() async {
    try {
      final l = await _api.get<List<dynamic>>('/trending', query: {'days': 30});
      return [for (final t in l) (t as Map)['tag'] as String];
    } on ApiException {
      return const [];
    }
  }

  /// Uploads media and returns the URLs to store in the post. Prefers the permanent `public_url`;
  /// `presigned_url` expires after 7 days.
  Future<List<Map<String, String>>> upload(List<UploadFile> files, {void Function(double)? onProgress}) async {
    // One file per request: a post's photos together can pass Cloud Run's 32 MB request cap
    // (Contributor photos may be up to 20 MB each).
    if (files.length > 1) {
      final total = files.fold<int>(0, (n, f) => n + f.bytes.length).clamp(1, 1 << 62);
      var done = 0;
      final out = <Map<String, String>>[];
      for (final f in files) {
        out.addAll(await upload([f], onProgress: (p) => onProgress?.call((done + p * f.bytes.length) / total)));
        done += f.bytes.length;
      }
      return out;
    }
    final form = FormData();
    for (final f in files) {
      form.files.add(MapEntry(
        'files',
        MultipartFile.fromBytes(f.bytes, filename: f.filename, contentType: DioMediaType.parse(f.mime)),
      ));
    }
    try {
      final r = await _api.dio.post<List<dynamic>>(
        '/media-upload/bulk',
        data: form,
        onSendProgress: (sent, total) => onProgress?.call(total <= 0 ? 0 : sent / total),
      );
      return [
        for (final m in r.data!.cast<Map<String, dynamic>>())
          {
            'url': (m['public_url'] ?? m['presigned_url']) as String,
            'media_type': (m['media_type'] as String?) ?? 'image',
          },
      ];
    } catch (e) {
      throw ApiException.from(e);
    }
  }

  /// A video straight to the bucket: `POST /media-upload/video` (the server checks the plan's video limit
  /// and signs the length), then a streamed PUT from the file. Returns the media entry for the post.
  Future<Map<String, String>> uploadVideo(String path, int size,
      {required String mime, void Function(int sent)? onSent}) async {
    final name = path.split(RegExp(r'[\\/]')).last;
    final slot = await _api.post<Map<String, dynamic>>('/media-upload/video',
        data: {'filename': name, 'content_type': mime, 'bytes': size});
    final headers = {
      for (final e in Map<String, dynamic>.from(slot['headers'] as Map? ?? const {}).entries) e.key: '${e.value}',
      Headers.contentLengthHeader: '$size',
    };
    try {
      // A bare Dio: no base URL, no auth header (the URL is presigned).
      await Dio().put<void>(
        slot['upload_url'] as String,
        data: File(path).openRead(),
        options: Options(headers: headers, sendTimeout: const Duration(minutes: 30)),
        onSendProgress: (sent, _) => onSent?.call(sent),
      );
    } catch (e) {
      throw ApiException.from(e);
    }
    return {'url': slot['url'] as String, 'media_type': 'video'};
  }

  Future<void> createPost({
    required List<Map<String, String>> media,
    required String caption,
    required PostCategory category,
    bool highlighted = false,
  }) =>
      _api.post<dynamic>('/posts', data: {
        'media_urls': media,
        'caption': caption,
        'post_category': category.label,
        'highlighted_by_author': highlighted,
      });
}
