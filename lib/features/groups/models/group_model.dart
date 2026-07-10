class GroupModel {
  final String id;
  final String name;
  final String? description;
  final String? avatar;
  final String ownerId;
  final bool isPublic;
  final String joinType; // free/approve/invite
  final int memberCount;
  final List<String> tags;
  final int createdAt; // 毫秒

  const GroupModel({
    required this.id,
    required this.name,
    this.description,
    this.avatar,
    required this.ownerId,
    required this.isPublic,
    required this.joinType,
    required this.memberCount,
    required this.tags,
    required this.createdAt,
  });

  factory GroupModel.fromJson(Map<String, dynamic> j) => GroupModel(
    id: j['id'].toString(),
    name: j['name']?.toString() ?? '',
    description: j['description']?.toString(),
    avatar: j['avatar']?.toString(),
    ownerId: j['owner_id']?.toString() ?? '',
    isPublic: j['is_public'] == 1 || j['is_public'] == true,
    joinType: j['join_type']?.toString() ?? 'free',
    memberCount: (j['member_count'] as num?)?.toInt() ?? 1,
    tags: List<String>.from((j['tags'] as List?) ?? const []),
    // 后端时间戳是秒级，×1000 转毫秒——跟这个项目其它模型的约定一致
    createdAt: ((j['created_at'] as num?) ?? 0).toInt() * 1000,
  );
}
