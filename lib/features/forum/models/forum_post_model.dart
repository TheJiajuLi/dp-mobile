class ForumPost {
  final String id;
  final String forumId;
  final String authorId;
  final String authorName;
  final String? authorAvatar;
  final bool isAuroraCreator;
  final String title;
  final String content;
  final List<String> tags;
  final bool isPinned;
  final bool isFeatured;
  final bool isLocked;
  final int viewCount;
  final int replyCount;
  final int likeCount;
  final int createdAt;

  const ForumPost({
    required this.id,
    required this.forumId,
    required this.authorId,
    required this.authorName,
    this.authorAvatar,
    required this.isAuroraCreator,
    required this.title,
    required this.content,
    required this.tags,
    required this.isPinned,
    required this.isFeatured,
    required this.isLocked,
    required this.viewCount,
    required this.replyCount,
    required this.likeCount,
    required this.createdAt,
  });

  // 后端 id/计数字段可能是 int 或 String，这里统一防御性转换，避免 as 崩溃
  factory ForumPost.fromJson(Map<String, dynamic> j) => ForumPost(
    id: j['id']?.toString() ?? '',
    forumId: j['forum_id']?.toString() ?? '',
    authorId: j['author_id']?.toString() ?? '',
    authorName: j['author_name']?.toString() ?? '',
    authorAvatar: j['author_avatar'] as String?,
    isAuroraCreator:
        j['is_aurora_creator'] == 1 || j['is_aurora_creator'] == true,
    title: j['title']?.toString() ?? '',
    content: j['content']?.toString() ?? '',
    tags: (j['tags'] as List?)?.map((e) => e.toString()).toList() ?? const [],
    isPinned: j['is_pinned'] == 1 || j['is_pinned'] == true,
    isFeatured: j['is_featured'] == 1 || j['is_featured'] == true,
    isLocked: j['is_locked'] == 1 || j['is_locked'] == true,
    viewCount: (j['view_count'] as num?)?.toInt() ?? 0,
    replyCount: (j['reply_count'] as num?)?.toInt() ?? 0,
    likeCount: (j['like_count'] as num?)?.toInt() ?? 0,
    createdAt: (j['created_at'] as num?)?.toInt() ?? 0,
  );

  // 详情页发回复后本地 +1 回复数用——原样回灌 fromJson，键名跟后端一致
  Map<String, dynamic> toJson() => {
    'id': id,
    'forum_id': forumId,
    'author_id': authorId,
    'author_name': authorName,
    'author_avatar': authorAvatar,
    'is_aurora_creator': isAuroraCreator ? 1 : 0,
    'title': title,
    'content': content,
    'tags': tags,
    'is_pinned': isPinned ? 1 : 0,
    'is_featured': isFeatured ? 1 : 0,
    'is_locked': isLocked ? 1 : 0,
    'view_count': viewCount,
    'reply_count': replyCount,
    'like_count': likeCount,
    'created_at': createdAt,
  };
}
