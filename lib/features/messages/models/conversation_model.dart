class Conversation {
  final String id;
  final String otherUserId;
  final String otherUsername;
  final String? otherAvatar;
  final String? lastMessage;
  final int? lastMessageAt; // 毫秒
  final int unreadCount;
  final bool isMuted;

  Conversation({
    required this.id,
    required this.otherUserId,
    required this.otherUsername,
    this.otherAvatar,
    this.lastMessage,
    this.lastMessageAt,
    required this.unreadCount,
    this.isMuted = false,
  });

  Conversation copyWith({int? unreadCount, bool? isMuted}) => Conversation(
    id: id,
    otherUserId: otherUserId,
    otherUsername: otherUsername,
    otherAvatar: otherAvatar,
    lastMessage: lastMessage,
    lastMessageAt: lastMessageAt,
    unreadCount: unreadCount ?? this.unreadCount,
    isMuted: isMuted ?? this.isMuted,
  );

  // 免打扰是按会话双方各自一列存的（is_muted_a 对应 user1_id 视角，
  // is_muted_b 对应 user2_id 视角）——GET /auth/conversations 用 `c.*`
  // 把两列都原样吐出来，这里要拿 currentUserId 跟 user1_id 比对才知道
  // "我" 对应哪一列，不传 currentUserId 时保守按未开启处理
  factory Conversation.fromJson(
    Map<String, dynamic> j, {
    String? currentUserId,
  }) {
    final isUser1 =
        currentUserId != null && j['user1_id']?.toString() == currentUserId;
    final mutedRaw = isUser1 ? j['is_muted_a'] : j['is_muted_b'];
    return Conversation(
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
      isMuted: mutedRaw == 1 || mutedRaw == true,
    );
  }
}
