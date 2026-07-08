import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../l10n/generated/app_localizations.dart';
import '../models/notification_model.dart';
import '../providers/messages_provider.dart';
import '../utils/message_avatar.dart';

// 通知类型过滤——评论/点赞/关注是后端真实会产生的 type（见
// tutorial.controller.ts/user.controller.ts 里 createNotification 的调用
// 点），@提及和 AI 目前完全没有对应的后端类型（没有评论 @人 的解析逻辑，
// 也没有 AI 专属通知），选中这两个 tab 一定是空列表——用专门的
// "即将上线" 提示跟"你真的还没有这类通知"区分开，不假装有数据
enum _NotifFilter { all, comment, like, follow, mention, ai }

class NotificationsScreen extends ConsumerStatefulWidget {
  const NotificationsScreen({super.key});
  @override
  ConsumerState<NotificationsScreen> createState() =>
      _NotificationsScreenState();
}

class _NotificationsScreenState extends ConsumerState<NotificationsScreen> {
  _NotifFilter _filter = _NotifFilter.all;

  Color _typeColor(String type) {
    switch (type) {
      case 'like':
        return Colors.red;
      case 'comment':
        return kMessagesPrimary;
      case 'follow':
        return const Color(0xFF34C759);
      default:
        return Colors.orange;
    }
  }

  IconData _typeIcon(String type) {
    switch (type) {
      case 'like':
        return Icons.favorite;
      case 'comment':
        return Icons.chat_bubble;
      case 'follow':
        return Icons.person_add;
      default:
        return Icons.notifications;
    }
  }

  List<AppNotification> _filtered(List<AppNotification> all) {
    switch (_filter) {
      case _NotifFilter.all:
        return all;
      case _NotifFilter.comment:
        return all.where((n) => n.type == 'comment').toList();
      case _NotifFilter.like:
        return all.where((n) => n.type == 'like').toList();
      case _NotifFilter.follow:
        return all.where((n) => n.type == 'follow').toList();
      case _NotifFilter.mention:
      case _NotifFilter.ai:
        return const [];
    }
  }

  bool get _isComingSoonFilter =>
      _filter == _NotifFilter.mention || _filter == _NotifFilter.ai;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final notifications = ref.watch(notificationsProvider);
    final filtered = _filtered(notifications);

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
                    l10n.tabNotifications,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: SizedBox(
                height: 32,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  children: [
                    _filterChip(l10n.notifFilterAll, _NotifFilter.all),
                    _filterChip(l10n.notifFilterComments, _NotifFilter.comment),
                    _filterChip(l10n.notifFilterLikes, _NotifFilter.like),
                    _filterChip(l10n.notifFilterFollows, _NotifFilter.follow),
                    _filterChip(l10n.notifFilterMentions, _NotifFilter.mention),
                    _filterChip(l10n.notifFilterAi, _NotifFilter.ai),
                  ],
                ),
              ),
            ),
            Expanded(
              child: _isComingSoonFilter
                  ? _ComingSoonNotice(
                      message: l10n.notifFilterComingSoonMessage,
                    )
                  : filtered.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(
                            Icons.notifications_none,
                            size: 56,
                            color: Colors.grey,
                          ),
                          const SizedBox(height: 12),
                          Text(
                            l10n.noNotificationsYet,
                            style: const TextStyle(
                              color: Colors.grey,
                              fontSize: 15,
                            ),
                          ),
                        ],
                      ),
                    )
                  : ListView(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      physics: const AlwaysScrollableScrollPhysics(),
                      children: [_notificationGroupCard(context, l10n, filtered)],
                    ),
            ),
          ],
        ),
      ),
    );
  }

  // 通知列表原来是"一条一条"的独立小卡片，改成消息主页 _PreviewCard
  // 那套惯例：一整块圆角大卡片，里面用 Divider 分隔每一行——这才是这个
  // App 里"列表型卡片"的标准做法，不是每一行单独套一层圆角
  Widget _notificationGroupCard(
    BuildContext context,
    AppLocalizations l10n,
    List<AppNotification> items,
  ) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(16),
        border: isDark
            ? Border.all(color: Theme.of(context).dividerColor, width: 0.5)
            : null,
        boxShadow: isDark
            ? null
            : [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.03),
                  blurRadius: 10,
                  offset: const Offset(0, 3),
                ),
              ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (var i = 0; i < items.length; i++) ...[
            if (i > 0)
              Divider(
                height: 0.5,
                indent: 68,
                color: Theme.of(context).dividerColor,
              ),
            _notificationTile(context, l10n, items[i]),
          ],
        ],
      ),
    );
  }

  Widget _notificationTile(
    BuildContext context,
    AppLocalizations l10n,
    AppNotification n,
  ) {
    return Container(
      color: n.isRead ? null : kMessagesPrimary.withValues(alpha: 0.07),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 6,
        ),
        leading: GestureDetector(
          onTap: (n.fromUsername?.isNotEmpty ?? false)
              ? () => context.push('/users/${n.fromUsername}')
              : null,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              buildMessageAvatar(
                n.fromAvatar,
                n.fromUsername ?? l10n.systemNotificationInitial,
                radius: 22,
              ),
              Positioned(
                top: -2,
                right: -2,
                child: Container(
                  width: 18,
                  height: 18,
                  decoration: BoxDecoration(
                    color: _typeColor(n.type),
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 1.5),
                  ),
                  child: Icon(_typeIcon(n.type), size: 10, color: Colors.white),
                ),
              ),
            ],
          ),
        ),
        title: Text(
          n.content ?? n.title ?? '',
          style: TextStyle(
            fontSize: 14,
            fontWeight: n.isRead ? FontWeight.w400 : FontWeight.w500,
          ),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(
          messageTimeAgo(l10n, n.createdAt),
          style: const TextStyle(fontSize: 12, color: Colors.grey),
        ),
        trailing: n.tutorialId != null
            ? Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: kMessagesPrimary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.article_outlined,
                  color: kMessagesPrimary,
                  size: 20,
                ),
              )
            : n.isRead
            ? null
            : Container(
                width: 8,
                height: 8,
                decoration: const BoxDecoration(
                  color: kMessagesPrimary,
                  shape: BoxShape.circle,
                ),
              ),
      ),
    );
  }

  Widget _filterChip(String label, _NotifFilter value) {
    final selected = _filter == value;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: GestureDetector(
        onTap: () => setState(() => _filter = value),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? kMessagesPrimary : Theme.of(context).cardColor,
            borderRadius: BorderRadius.circular(16),
            border: selected
                ? null
                : Border.all(color: Theme.of(context).dividerColor),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: selected
                  ? Colors.white
                  : Theme.of(context).textTheme.bodyLarge?.color,
            ),
          ),
        ),
      ),
    );
  }
}

class _ComingSoonNotice extends StatelessWidget {
  final String message;
  const _ComingSoonNotice({required this.message});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: kMessagesPrimary.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.hourglass_top_outlined,
              color: kMessagesPrimary,
              size: 28,
            ),
          ),
          const SizedBox(height: 14),
          Text(
            message,
            style: const TextStyle(color: Colors.grey, fontSize: 14),
          ),
        ],
      ),
    );
  }
}
