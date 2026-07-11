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
  final bool isFollowing;
  final int colorIdx;
  // forums 表目前还没有这一列，getForums/getForum 返回的 j['avatar']
  // 恒为 null，这个字段先摆着——等后端加了列，这里跟渲染那边都不用再改
  final String? avatar;

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
    this.isFollowing = false,
    this.colorIdx = 0,
    this.avatar,
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
    isFollowing: j['is_following'] == 1 || j['is_following'] == true,
    // 0-5，超出这个范围（脏数据/未来加了更多渐变色但客户端还没更新表）
    // 用 .clamp 兜底，不让下标越界崩溃
    colorIdx: ((j['color_index'] as num?)?.toInt() ?? 0).clamp(0, 5),
    avatar: j['avatar']?.toString(),
  );
}
