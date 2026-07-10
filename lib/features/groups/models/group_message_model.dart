enum GroupMessageType { text, shareTutorial, shareQuestion }

class GroupMessage {
  final String id;
  final String groupId;
  final String senderId;
  final String senderName;
  final String? senderAvatar;
  final GroupMessageType type;
  final String content;
  final String? refId; // 分享内容ID
  final String? refTitle; // 分享内容标题
  final String? refMeta; // 分享内容副标题
  final bool isRecalled;
  final int createdAt; // 毫秒
  final bool isMe;

  const GroupMessage({
    required this.id,
    required this.groupId,
    required this.senderId,
    required this.senderName,
    this.senderAvatar,
    required this.type,
    required this.content,
    this.refId,
    this.refTitle,
    this.refMeta,
    this.isRecalled = false,
    required this.createdAt,
    required this.isMe,
  });

  factory GroupMessage.fromJson(Map<String, dynamic> j, String myUserId) {
    final typeStr = j['type']?.toString() ?? 'text';
    final type = switch (typeStr) {
      'share_tutorial' => GroupMessageType.shareTutorial,
      'share_question' => GroupMessageType.shareQuestion,
      _ => GroupMessageType.text,
    };
    final senderId = j['sender_id']?.toString() ?? '';
    return GroupMessage(
      id: j['id'].toString(),
      groupId: j['group_id']?.toString() ?? '',
      senderId: senderId,
      senderName: j['sender_name']?.toString() ?? '',
      senderAvatar: j['sender_avatar']?.toString(),
      type: type,
      content: j['content']?.toString() ?? '',
      refId: j['ref_id']?.toString(),
      refTitle: j['ref_title']?.toString(),
      refMeta: j['ref_meta']?.toString(),
      isRecalled: j['is_recalled'] == 1 || j['is_recalled'] == true,
      // 后端时间戳是秒级，×1000 转毫秒——跟这个项目其它模型
      // （AppNotification/TutorialComment）的约定一致
      createdAt: ((j['created_at'] as num?) ?? 0).toInt() * 1000,
      isMe: senderId == myUserId,
    );
  }
}
