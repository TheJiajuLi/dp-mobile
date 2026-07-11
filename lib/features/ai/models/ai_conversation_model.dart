class AiConversation {
  final String id;
  final String title;
  final int createdAt; // 毫秒
  final int updatedAt; // 毫秒

  const AiConversation({
    required this.id,
    required this.title,
    required this.createdAt,
    required this.updatedAt,
  });

  factory AiConversation.fromJson(Map<String, dynamic> j) => AiConversation(
    id: j['id'].toString(),
    title: j['title']?.toString() ?? '新对话',
    // 后端时间戳是秒级，×1000 转毫秒——跟这个项目其它模型的约定一致
    createdAt: ((j['created_at'] as num?) ?? 0).toInt() * 1000,
    updatedAt: ((j['updated_at'] as num?) ?? 0).toInt() * 1000,
  );
}
