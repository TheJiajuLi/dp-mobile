class Conversation {
  final String id;
  final String otherUserId;
  final String otherUsername;
  final String? otherAvatar;
  final String? lastMessage;
  final int? lastMessageAt; // 毫秒
  final int unreadCount;

  Conversation({
    required this.id,
    required this.otherUserId,
    required this.otherUsername,
    this.otherAvatar,
    this.lastMessage,
    this.lastMessageAt,
    required this.unreadCount,
  });

  factory Conversation.fromJson(Map<String, dynamic> j) => Conversation(
    id: j['id'].toString(),
    otherUserId: j['other_user_id']?.toString() ?? '',
    otherUsername: j['other_username']?.toString() ?? '用户',
    otherAvatar: j['other_avatar']?.toString(),
    lastMessage: j['last_message']?.toString(),
    // 后端时间戳是秒级，×1000 转毫秒
    lastMessageAt: j['last_message_at'] != null
        ? (j['last_message_at'] as num).toInt() * 1000
        : null,
    unreadCount: (j['unread_count'] as num?)?.toInt() ?? 0,
  );
}
