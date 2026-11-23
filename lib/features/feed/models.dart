/// outsie post categories: the API takes the label ("Exam Result") or the slug ("exam_result").
enum PostCategory {
  academic('Academic', '📚'),
  achievement('Achievement', '🏆'),
  examResult('Exam Result', '📊'),
  studyGroup('Study Group', '👥'),
  project('Project', '🛠️'),
  tech('Technology', '💻'),
  lifestyle('Lifestyle', '🌿'),
  vlog('Vlog', '🎬'),
  entertainment('Entertainment', '🎉'),
  business('Business', '💼');

  const PostCategory(this.label, this.emoji);

  final String label;
  final String emoji;

  static PostCategory? parse(String? s) {
    if (s == null) return null;
    final key = s.toLowerCase().replaceAll(' ', '_');
    for (final c in values) {
      if (c.label == s || c.label.toLowerCase().replaceAll(' ', '_') == key) return c;
    }
    return key == 'tech' ? tech : null;
  }
}

class Media {
  const Media(this.url, this.isVideo);

  final String url;
  final bool isVideo;

  factory Media.fromJson(Object j) {
    if (j is String) return Media(j, _videoExt.hasMatch(j));
    final m = j as Map<String, dynamic>;
    final url = m['url'] as String;
    return Media(url, m['media_type'] == 'video' || _videoExt.hasMatch(url));
  }

  static final _videoExt = RegExp(r'\.(mp4|mov|webm|avi)(\?|$)', caseSensitive: false);
}

class Post {
  Post({
    required this.id,
    required this.author,
    required this.authorId,
    required this.caption,
    required this.category,
    required this.postedAt,
    required this.media,
    required this.isLiked,
    required this.likeCount,
    required this.commentCount,
  });

  final String id;
  final String author;
  final int authorId;
  final String caption;
  final PostCategory? category;
  final DateTime postedAt;
  final List<Media> media;
  bool isLiked;
  int likeCount;
  int commentCount;

  factory Post.fromJson(Map<String, dynamic> j) => Post(
        id: j['post_id'] as String,
        author: j['author'] as String,
        authorId: j['author_user_id'] as int,
        caption: (j['caption'] as String?) ?? '',
        category: PostCategory.parse(j['post_category'] as String?),
        // The server sends naive UTC timestamps.
        postedAt: DateTime.parse(_asUtc(j['datetime_posted'] as String)).toLocal(),
        media: [for (final m in (j['media_urls'] as List?) ?? const []) Media.fromJson(m as Object)],
        isLiked: j['is_liked'] == true,
        likeCount: (j['like_count'] as int?) ?? 0,
        commentCount: (j['comment_count'] as int?) ?? 0,
      );
}

class Comment {
  const Comment({required this.id, required this.author, required this.content, required this.at});

  final int id;
  final String author;
  final String content;
  final DateTime at;

  factory Comment.fromJson(Map<String, dynamic> j) => Comment(
        id: j['comment_id'] as int,
        author: (j['author'] as String?) ?? 'someone',
        content: j['content'] as String,
        at: DateTime.parse(_asUtc(j['datetime_commented'] as String)).toLocal(),
      );
}

class UserSummary {
  const UserSummary({required this.username, required this.fullname, this.bio});

  final String username;
  final String fullname;
  final String? bio;

  factory UserSummary.fromJson(Map<String, dynamic> j) =>
      UserSummary(username: j['username'] as String, fullname: j['fullname'] as String, bio: j['bio'] as String?);
}

/// `GET /users/{username}`. Follow fields: 0 none, 0.5 requested, 1 following.
class Profile {
  const Profile({
    required this.username,
    required this.fullname,
    this.bio,
    required this.posts,
    required this.followers,
    required this.following,
    required this.youFollow,
    required this.theyFollow,
  });

  final String username;
  final String fullname;
  final String? bio;
  final int posts;
  final int followers;
  final int following;
  final double youFollow;
  final double theyFollow;

  factory Profile.fromJson(Map<String, dynamic> j) => Profile(
        username: j['username'] as String,
        fullname: j['fullname'] as String,
        bio: j['bio'] as String?,
        posts: j['posts_count'] as int,
        followers: j['followers_count'] as int,
        following: j['following_count'] as int,
        youFollow: (j['you_follow_them'] as num).toDouble(),
        theyFollow: (j['they_follow_you'] as num).toDouble(),
      );
}

class FollowRequest {
  const FollowRequest({required this.id, required this.username, required this.at});

  final int id;
  final String username;
  final DateTime? at;

  factory FollowRequest.fromJson(Map<String, dynamic> j) => FollowRequest(
        id: j['request_id'] as int,
        username: j['requester_username'] as String,
        at: j['datetime_requested'] == null ? null : DateTime.tryParse(_asUtc(j['datetime_requested'] as String))?.toLocal(),
      );
}

String _asUtc(String s) => RegExp(r'(Z|[+-]\d\d:?\d\d)$').hasMatch(s) ? s : '${s}Z';

/// "now", "5m", "3h", "2d", then a date.
String timeAgo(DateTime t) {
  final d = DateTime.now().difference(t);
  if (d.inMinutes < 1) return 'now';
  if (d.inHours < 1) return '${d.inMinutes}m';
  if (d.inDays < 1) return '${d.inHours}h';
  if (d.inDays < 7) return '${d.inDays}d';
  const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  final sameYear = t.year == DateTime.now().year;
  return '${t.day} ${months[t.month - 1]}${sameYear ? '' : ' ${t.year}'}';
}
