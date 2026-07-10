class AppNotification {
  final String id;
  final String type; // like / comment / follow / mention / system
  final String? title;
  final String? content;
  final String? fromUsername;
  final String? fromAvatar;
  final String? tutorialTitle;
  final String? tutorialId;
  final String? commentId;
  bool isRead;
  final int createdAt; // 毫秒

  AppNotification({
    required this.id,
    required this.type,
    this.title,
    this.content,
    this.fromUsername,
    this.fromAvatar,
    this.tutorialTitle,
    this.tutorialId,
    this.commentId,
    required this.isRead,
    required this.createdAt,
  });

  factory AppNotification.fromJson(Map<String, dynamic> j) => AppNotification(
    id: j['id'].toString(),
    type: j['type']?.toString() ?? 'system',
    title: j['title']?.toString(),
    content: j['content']?.toString(),
    fromUsername: j['from_username']?.toString(),
    fromAvatar: j['from_avatar']?.toString(),
    tutorialTitle: j['tutorial_title']?.toString(),
    tutorialId: j['tutorial_id']?.toString(),
    commentId: j['comment_id']?.toString(),
    isRead: j['is_read'] == 1 || j['is_read'] == true,
    // 后端时间戳是秒级，×1000 转毫秒
    createdAt: ((j['created_at'] as num?) ?? 0).toInt() * 1000,
  );
}
