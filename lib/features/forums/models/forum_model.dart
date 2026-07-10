class ForumModel {
  final String id;
  final String name;
  final String? description;
  final String creatorId;
  final List<String> tags;
  final int memberCount;
  final int followerCount;
  final int postCount;
  final int createdAt; // 毫秒

  const ForumModel({
    required this.id,
    required this.name,
    this.description,
    required this.creatorId,
    required this.tags,
    required this.memberCount,
    required this.followerCount,
    required this.postCount,
    required this.createdAt,
  });

  factory ForumModel.fromJson(Map<String, dynamic> j) => ForumModel(
    id: j['id'].toString(),
    name: j['name']?.toString() ?? '',
    description: j['description']?.toString(),
    creatorId: j['creator_id']?.toString() ?? '',
    tags: List<String>.from((j['tags'] as List?) ?? const []),
    memberCount: (j['member_count'] as num?)?.toInt() ?? 0,
    followerCount: (j['follower_count'] as num?)?.toInt() ?? 0,
    postCount: (j['post_count'] as num?)?.toInt() ?? 0,
    // 后端时间戳是秒级，×1000 转毫秒——跟 GroupModel 同一个约定
    createdAt: ((j['created_at'] as num?) ?? 0).toInt() * 1000,
  );
}
