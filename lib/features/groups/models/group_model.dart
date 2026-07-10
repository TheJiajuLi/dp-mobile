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
  final int createdAt;

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
    createdAt: (j['created_at'] as num?)?.toInt() ?? 0,
  );
}
