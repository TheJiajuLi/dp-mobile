class ChatMessage {
  final String id;
  final String conversationId;
  final String senderId;
  final String senderUsername;
  final String? senderAvatar;
  final String type; // text / code / image / tutorial
  final String content;
  final Map<String, dynamic>? metadata;
  final bool isRead;
  final int createdAt; // 毫秒

  ChatMessage({
    required this.id,
    required this.conversationId,
    required this.senderId,
    required this.senderUsername,
    this.senderAvatar,
    required this.type,
    required this.content,
    this.metadata,
    required this.isRead,
    required this.createdAt,
  });

  factory ChatMessage.fromJson(Map<String, dynamic> j) => ChatMessage(
    id: j['id'].toString(),
    conversationId: j['conversation_id']?.toString() ?? '',
    senderId: j['sender_id']?.toString() ?? '',
    senderUsername: j['sender_username']?.toString() ?? '用户',
    senderAvatar: j['sender_avatar']?.toString(),
    type: j['type']?.toString() ?? 'text',
    content: j['content']?.toString() ?? '',
    metadata: j['metadata'] != null
        ? Map<String, dynamic>.from(j['metadata'] as Map)
        : null,
    isRead: j['is_read'] == 1 || j['is_read'] == true,
    // 后端时间戳是秒级，×1000 转毫秒
    createdAt: ((j['created_at'] as num?) ?? 0).toInt() * 1000,
  );
}
