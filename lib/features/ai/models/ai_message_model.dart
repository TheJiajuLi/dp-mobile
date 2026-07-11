class AiMessage {
  final String id;
  final String role; // 'user' | 'assistant'
  final String content;
  final int createdAt; // 毫秒

  const AiMessage({
    required this.id,
    required this.role,
    required this.content,
    required this.createdAt,
  });

  bool get isUser => role == 'user';

  factory AiMessage.fromJson(Map<String, dynamic> j) => AiMessage(
    id: j['id']?.toString() ?? '',
    role: j['role']?.toString() ?? 'user',
    content: j['content']?.toString() ?? '',
    createdAt: ((j['created_at'] as num?) ?? 0).toInt() * 1000,
  );
}
