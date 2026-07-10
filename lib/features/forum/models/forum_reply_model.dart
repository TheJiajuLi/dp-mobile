class ForumReply {
  final String id;
  final String postId;
  final String authorId;
  final String authorName;
  final String? authorAvatar;
  final bool isAuroraCreator;
  final String content;
  final String? quoteContent;
  final String? quoteAuthor;
  final int likeCount;
  final int floorNumber;
  final int createdAt;

  const ForumReply({
    required this.id,
    required this.postId,
    required this.authorId,
    required this.authorName,
    this.authorAvatar,
    required this.isAuroraCreator,
    required this.content,
    this.quoteContent,
    this.quoteAuthor,
    required this.likeCount,
    required this.floorNumber,
    required this.createdAt,
  });

  factory ForumReply.fromJson(Map<String, dynamic> j) => ForumReply(
    id: j['id']?.toString() ?? '',
    postId: j['post_id']?.toString() ?? '',
    authorId: j['author_id']?.toString() ?? '',
    authorName: j['author_name']?.toString() ?? '',
    authorAvatar: j['author_avatar'] as String?,
    isAuroraCreator:
        j['is_aurora_creator'] == 1 || j['is_aurora_creator'] == true,
    content: j['content']?.toString() ?? '',
    quoteContent: j['quote_content'] as String?,
    quoteAuthor: j['quote_author'] as String?,
    likeCount: (j['like_count'] as num?)?.toInt() ?? 0,
    floorNumber: (j['floor_number'] as num?)?.toInt() ?? 1,
    createdAt: (j['created_at'] as num?)?.toInt() ?? 0,
  );
}
