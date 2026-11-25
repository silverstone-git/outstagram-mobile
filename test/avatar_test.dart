import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:outstagram/core/ui/avatar.dart';
import 'package:outstagram/features/account/account_api.dart';
import 'package:outstagram/features/feed/models.dart';

void main() {
  test('avatar urls are parsed everywhere they appear', () {
    final post = Post.fromJson({
      'post_id': 'p',
      'author': 'asha',
      'author_user_id': 1,
      'post_category': 'Academic',
      'datetime_posted': '2026-11-25T10:00:00',
      'author_avatar_url': 'https://r2.example/avatars/1-a.webp?X-Amz-Signature=1',
    });
    expect(post.authorAvatar, contains('avatars/1-a.webp'));
    expect(
      Comment.fromJson({
        'comment_id': 1,
        'author': 'b',
        'content': 'hi',
        'datetime_commented': '2026-11-25T10:00:00',
        'author_avatar_url': 'u',
      }).authorAvatar,
      'u',
    );
    expect(UserSummary.fromJson({'username': 'a', 'fullname': 'A', 'avatar_url': 'x'}).avatar, 'x');
    expect(
      Profile.fromJson({
        'username': 'a',
        'fullname': 'A',
        'posts_count': 0,
        'followers_count': 0,
        'following_count': 0,
        'you_follow_them': 0,
        'they_follow_you': 0,
        'avatar_url': 'y',
      }).avatar,
      'y',
    );
    expect(FollowRequest.fromJson({'request_id': 1, 'requester_username': 'a', 'requester_avatar_url': 'z'}).avatar, 'z');
    expect(Me.fromJson({'user_id': 1, 'username': 'a', 'email': 'e', 'email_verified': true}).avatar, isNull);
    // older servers: no avatar field at all
    expect(UserSummary.fromJson({'username': 'a', 'fullname': 'A'}).avatar, isNull);
  });

  test('re-signed links share one cache entry', () {
    expect(
      Avatar.cacheKey('https://r2.example/avatars/1.webp?X-Amz-Signature=aaa'),
      Avatar.cacheKey('https://r2.example/avatars/1.webp?X-Amz-Signature=bbb'),
    );
  });

  testWidgets('letter avatar without a photo, image provider with one', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: Column(children: [Avatar(name: 'asha'), Avatar(name: 'bo', url: 'https://x.test/a.webp')])),
    ));
    final avatars = tester.widgetList<CircleAvatar>(find.byType(CircleAvatar)).toList();
    expect(avatars[0].foregroundImage, isNull);
    expect(avatars[1].foregroundImage, isNotNull);
    expect(find.text('A'), findsOneWidget);
  });
}
