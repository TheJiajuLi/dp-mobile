import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import '../models/notification_model.dart';

// 通知"内容"点击的统一跳转：
// - 评论/提及 → 文章详情，并带 scrollToCommentId 定位到那条评论
// - 点赞/收藏 → 文章详情
// - 回答通知  → 问题详情（answer_posted 复用 tutorialId 传 questionId）
// - 关注      → 发信人主页（只有关注类才应该跳用户主页）
// - 群聊@提及 → 群聊页（group_message_mention 复用 tutorialId 传 group_id，
//   跟 group_invite 是同一个FK槽位复用套路）
// - 论坛回复  → 帖子详情（forum_reply 复用 tutorialId 传 post_id）
// 返回 true 表示已经处理跳转；false 表示这个类型不归它管（如 group_invite
// 有各自的专属处理，system 类无处可跳），交给调用方兜底
bool openNotificationTarget(BuildContext context, AppNotification n) {
  switch (n.type) {
    case 'comment':
    case 'mention':
      if (n.tutorialId == null) return false;
      context.push(
        '/tutorial/${n.tutorialId}',
        extra: n.commentId != null ? {'scrollToCommentId': n.commentId} : null,
      );
      return true;
    case 'like':
    case 'save':
      if (n.tutorialId == null) return false;
      context.push('/tutorial/${n.tutorialId}');
      return true;
    case 'answer_posted':
      if (n.tutorialId == null) return false;
      context.push('/questions/${n.tutorialId}');
      return true;
    case 'follow':
      if (n.fromUsername?.isNotEmpty ?? false) {
        context.push('/users/${n.fromUsername}');
        return true;
      }
      return false;
    case 'group_message_mention':
      if (n.tutorialId == null) return false;
      context.push('/group/${n.tutorialId}');
      return true;
    case 'forum_reply':
      if (n.tutorialId == null) return false;
      context.push('/forum/post/${n.tutorialId}');
      return true;
    default:
      return false;
  }
}
