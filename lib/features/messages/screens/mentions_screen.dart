import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../l10n/generated/app_localizations.dart';
import '../models/notification_model.dart';
import '../providers/messages_provider.dart';
import '../utils/message_avatar.dart';

// "提及"是消息主页的独立入口（跟"邀请回答"一个套路），不是靠通用
// notificationsProvider 的预览过滤器凑出来的——mention 类型本来就存在
// notifications 表里，跟其它通知共用同一个 fetch()，这里只是按 type
// 筛出来单独展示，不需要再调一个专属接口
class MentionsScreen extends ConsumerStatefulWidget {
  const MentionsScreen({super.key});

  @override
  ConsumerState<MentionsScreen> createState() => _MentionsScreenState();
}

class _MentionsScreenState extends ConsumerState<MentionsScreen> {
  @override
  void initState() {
    super.initState();
    ref.read(notificationsProvider.notifier).fetch().then((_) => _markRead());
  }

  Future<void> _markRead() async {
    final unreadIds = ref
        .read(notificationsProvider)
        .where((n) => n.type == 'mention' && !n.isRead)
        .map((n) => n.id)
        .toList();
    if (unreadIds.isEmpty) return;
    ref.read(mentionUnreadCountProvider.notifier).state = 0;
    final total = ref.read(unreadCountProvider);
    ref.read(unreadCountProvider.notifier).state = (total - unreadIds.length)
        .clamp(0, total);
    await ref.read(notificationsProvider.notifier).markRead(unreadIds);
  }

  void _onTapMention(AppNotification n) {
    if (n.tutorialId == null) return;
    context.push(
      '/tutorial/${n.tutorialId}',
      extra: {'scrollToCommentId': n.commentId},
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final mentions = ref
        .watch(notificationsProvider)
        .where((n) => n.type == 'mention')
        .toList();

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 16, 0),
              child: Row(
                children: [
                  IconButton(
                    onPressed: () => context.pop(),
                    icon: const Icon(Icons.arrow_back_ios, size: 18),
                  ),
                  Text(
                    l10n.mentionsPageTitle,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: mentions.isEmpty
                  ? _emptyState(l10n)
                  : RefreshIndicator(
                      onRefresh: () =>
                          ref.read(notificationsProvider.notifier).fetch(),
                      child: ListView.builder(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        itemCount: mentions.length,
                        itemBuilder: (ctx, i) => _MentionCard(
                          notification: mentions[i],
                          onTap: () => _onTapMention(mentions[i]),
                        ),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _emptyState(AppLocalizations l10n) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.alternate_email, size: 40, color: Colors.grey[300]),
          const SizedBox(height: 12),
          Text(
            l10n.noMentionsYet,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: Colors.grey[400],
            ),
          ),
          const SizedBox(height: 5),
          Text(
            l10n.mentionsEmptyHint,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              color: Colors.grey[400],
              height: 1.6,
            ),
          ),
        ],
      ),
    );
  }
}

class _MentionCard extends StatelessWidget {
  final AppNotification notification;
  final VoidCallback onTap;

  const _MentionCard({required this.notification, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final n = notification;
    final isUnread = !n.isRead;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(13),
        decoration: BoxDecoration(
          color: isUnread
              ? (isDark ? const Color(0xFF0D0D1A) : const Color(0xFFFAFAFF))
              : Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isDark
                ? Colors.white.withValues(alpha: 0.08)
                : const Color(0xFFEBEBEB),
            width: 0.5,
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                buildMessageAvatar(
                  n.fromAvatar,
                  n.fromUsername ?? l10n.systemNotificationInitial,
                  radius: 18,
                ),
                if (isUnread)
                  Positioned(
                    top: 0,
                    right: 0,
                    child: Container(
                      width: 9,
                      height: 9,
                      decoration: BoxDecoration(
                        color: const Color(0xFF8B5CF6),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: isDark
                              ? const Color(0xFF0A0A1A)
                              : Colors.white,
                          width: 1.5,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  RichText(
                    text: TextSpan(
                      style: TextStyle(
                        fontSize: 13,
                        color: isDark
                            ? Colors.white.withValues(alpha: 0.9)
                            : const Color(0xFF1A1A1A),
                      ),
                      children: [
                        TextSpan(
                          text:
                              n.fromUsername ?? l10n.systemNotificationInitial,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        TextSpan(text: ' ${l10n.mentionedYouInComment}'),
                      ],
                    ),
                  ),
                  const SizedBox(height: 6),
                  Container(
                    padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
                    decoration: BoxDecoration(
                      color: isDark
                          ? const Color(0xFF8B5CF6).withValues(alpha: 0.08)
                          : const Color(0xFFF5F0FF),
                      border: const Border(
                        left: BorderSide(color: Color(0xFF8B5CF6), width: 2.5),
                      ),
                    ),
                    child: Text(
                      n.content ?? '',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        height: 1.5,
                        color: isDark
                            ? Colors.white.withValues(alpha: 0.6)
                            : const Color(0xFF555555),
                      ),
                    ),
                  ),
                  const SizedBox(height: 5),
                  Row(
                    children: [
                      if (n.tutorialTitle != null)
                        Expanded(
                          child: Text(
                            n.tutorialTitle!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 10,
                              color: isUnread
                                  ? const Color(0xFF8B5CF6)
                                  : Colors.grey[400],
                            ),
                          ),
                        )
                      else
                        const Spacer(),
                      Text(
                        messageTimeAgo(l10n, n.createdAt),
                        style: TextStyle(fontSize: 10, color: Colors.grey[400]),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
