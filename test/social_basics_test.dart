import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:outstagram/core/net/api_client.dart';
import 'package:outstagram/features/activity/activity_screen.dart';
import 'package:outstagram/features/feed/models.dart';
import 'package:outstagram/features/feed/post_card.dart';
import 'package:outstagram/features/feed/social_api.dart';
import 'package:outstagram/features/profile/edit_profile_screen.dart';

/// Records every request and answers from a route table ("METHOD /path" -> (status, json)).
class Router implements HttpClientAdapter {
  Router(this.routes);

  final Map<String, (int, Object?)> routes;
  final calls = <String>[];
  final bodies = <String, Object?>{};

  @override
  Future<ResponseBody> fetch(RequestOptions o, Stream<Uint8List>? body, Future<void>? cancel) async {
    final key = '${o.method} ${o.path}';
    calls.add(key);
    bodies[key] = o.data;
    final (status, json) = routes[key] ?? (404, {'detail': 'Not Found'});
    return ResponseBody.fromString(jsonEncode(json), status, headers: {
      Headers.contentTypeHeader: ['application/json'],
    });
  }

  @override
  void close({bool force = false}) {}
}

Api apiWith(Router r) => Api(Dio(BaseOptions(baseUrl: 'https://api.test'))..httpClientAdapter = r);

void main() {
  test('follow lists parse the viewer state; old payloads default to not following', () {
    final u = UserSummary.fromJson({'username': 'a', 'fullname': 'A', 'you_follow_them': 0.5, 'is_you': false});
    expect(u.youFollow, 0.5);
    expect(UserSummary.fromJson({'username': 'a', 'fullname': 'A', 'is_you': true}).isYou, isTrue);
    expect(UserSummary.fromJson({'username': 'a', 'fullname': 'A'}).youFollow, 0);
  });

  test('SocialApi hits the new endpoints', () async {
    final r = Router({
      'DELETE /users/bo%20b/follow': (204, null),
      'DELETE /me/followers/cy': (204, null),
      'POST /request-reject/7': (204, null),
      'GET /users/asha/followers/2': (200, [
        {'username': 'bo', 'fullname': 'Bo', 'you_follow_them': 1, 'is_you': false},
      ]),
      'PUT /me': (200, {'user_id': 1, 'username': 'asha'}),
      'DELETE /posts/p1/comments/5': (204, null),
      'POST /posts/p1/comment': (201, {'comment_id': 42, 'content': 'hi'}),
      'GET /posts/p1': (200, {
        'post_id': 'p1',
        'author': 'asha',
        'author_user_id': 1,
        'datetime_posted': '2026-11-25T10:00:00',
        'like_count': 3,
        'comment_count': 2,
        'media_urls': [
          {'url': 'https://x.test/v.mp4', 'media_type': 'video'},
        ],
      }),
    });
    final api = SocialApi(apiWith(r));
    await api.unfollow('bo b');
    await api.removeFollower('cy');
    await api.reject(7);
    final list = await api.followList('asha', 'followers', 2);
    expect(list.single.youFollow, 1);
    await api.updateProfile(fullname: 'Asha V.', bio: '');
    expect(r.bodies['PUT /me'], {'fullname': 'Asha V.', 'bio': ''});
    await api.updateProfile(bio: 'x');
    expect(r.bodies['PUT /me'], {'bio': 'x'}, reason: 'omitted fields are not sent');
    await api.deleteComment('p1', 5);
    expect(await api.addComment('p1', 'hi'), 42);
    final p = await api.post('p1');
    expect((p.likeCount, p.commentCount, p.media.single.isVideo), (3, 2, true));
    expect(r.calls, contains('DELETE /users/bo%20b/follow'));
  });

  test('post links point at the web /p/<id> page', () {
    final p = Post.fromJson({'post_id': 'abc', 'author': 'a', 'author_user_id': 1, 'datetime_posted': '2026-11-25T10:00:00'});
    expect(postLink(p), endsWith('/p/?id=abc'));
  });

  testWidgets('edit profile: an empty name is refused before any request', (tester) async {
    final r = Router({});
    await tester.pumpWidget(ProviderScope(
      overrides: [apiProvider.overrideWithValue(apiWith(r))],
      child: const MaterialApp(
        home: EditProfileForm(
          profile: Profile(
            username: 'asha',
            fullname: 'Asha',
            bio: 'hi',
            posts: 0,
            followers: 0,
            following: 0,
            youFollow: 0,
            theyFollow: 0,
          ),
        ),
      ),
    ));
    await tester.enterText(find.widgetWithText(TextFormField, 'Name'), '   ');
    await tester.tap(find.text('Save'));
    await tester.pump();
    expect(find.text("Your name can't be empty"), findsOneWidget);
    expect(r.calls, isEmpty);
  });

  testWidgets('activity: decline a request', (tester) async {
    final r = Router({
      'GET /follow-requests': (200, [
        {'request_id': 9, 'requester_username': 'cyto', 'datetime_requested': '2026-11-25T10:00:00'},
      ]),
      'POST /request-reject/9': (204, null),
    });
    await tester.pumpWidget(ProviderScope(
      overrides: [apiProvider.overrideWithValue(apiWith(r))],
      child: const MaterialApp(home: ActivityScreen()),
    ));
    await tester.pumpAndSettle();
    expect(find.text('cyto'), findsOneWidget);
    await tester.tap(find.byTooltip('Decline'));
    await tester.pumpAndSettle();
    expect(r.calls, contains('POST /request-reject/9'));
    expect(find.text('Declined'), findsOneWidget);
    expect(find.text('Approve'), findsNothing);
  });
}
