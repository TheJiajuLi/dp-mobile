import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_client.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../models/notification_model.dart';
import '../providers/messages_provider.dart';
import '../utils/message_avatar.dart';
import '../widgets/invite_summary_card.dart';

// 之前是评论/点赞/邀请回答/系统四个Tab，邀请回答现在改成汇总卡+专属
// 列表页（invite_list_screen.dart）单独承接，这个页面收窄成"最近通知"：
// 顶部"需要你处理"（邀请汇总卡）+"最新动态"（除 invite_answer 外的
// 普通通知，扁平列表，不分type）。汇总卡之前只在 count>0 时才渲染，
// 结果是没有待处理邀请时整块入口直接从页面消失——找不到"查看所有
// 邀请回答"的入口正是这个原因，现在改成常驻显示（count==0 时是空态
// 提示），保证入口位置固定
class NotificationsScreen extends ConsumerStatefulWidget {
  const NotificationsScreen({super.key});
  @override
  ConsumerState<NotificationsScreen> createState() =>
      _NotificationsScreenState();
}

class _NotificationsScreenState extends ConsumerState<NotificationsScreen> {
  List<Map<String, dynamic>> _invites = [];
  bool _loadingInvites = false;

  @override
  void initState() {
    super.initState();
    _loadInvites();
    _markAllRead();
  }

  // 后端标记已读接口一直都在（POST /auth/notifications/read），但之前
  // 只有消息首页"全部已读"按钮会调用它——用户点进"最近通知"整页浏览完
  // 并不代表点了那个按钮，红点因此一直不消——本地先乐观置 0，
  // 不等接口返回，体验更顺
  Future<void> _markAllRead() async {
    ref.read(unreadCountProvider.notifier).state = 0;
    final notifs = ref.read(notificationsProvider);
    if (notifs.any((n) => !n.isRead)) {
      await ref.read(notificationsProvider.notifier).markAllRead();
    }
  }

  Future<void> _loadInvites() async {
    setState(() => _loadingInvites = true);
    final res = await ref
        .read(apiClientProvider)
        .get('/auth/questions/invites');
    if (!mounted) return;
    setState(() {
      _loadingInvites = false;
      if (res.success && res.data != null) {
        _invites = ((res.data['invites'] as List?) ?? [])
            .map((i) => Map<String, dynamic>.from(i as Map))
            .toList();
      }
    });
  }

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

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final notifications = ref.watch(notificationsProvider);
    // invite_answer 有自己专属的汇总卡+列表页，不在这重复出现；
    // answer_posted 没有专属入口，得留在"最新动态"里，点击跳问题详情
    // （之前重构成汇总卡布局时误把它也一起过滤掉了，导致这类通知完全
    // 找不到地方点开——2026-07-10 修复）
    final feed = notifications.where((n) => n.type != 'invite_answer').toList();

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
                    l10n.recentNotificationsTitle,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: RefreshIndicator(
                onRefresh: () => Future.wait([
                  _loadInvites(),
                  ref.read(notificationsProvider.notifier).fetch(),
                ]),
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  children: [
                    if (!_loadingInvites) ...[
                      _sectionLabel('需要你处理'),
                      const SizedBox(height: 6),
                      InviteSummaryCard(
                        count: _invites.length,
                        invites: _invites,
                        onTap: () => context.push('/invite-list'),
                      ),
                      const SizedBox(height: 16),
                    ],
                    _sectionLabel('最新动态'),
                    const SizedBox(height: 6),
                    if (feed.isEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 40),
                        child: Center(
                          child: Column(
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
                        ),
                      )
                    else
                      _notificationGroupCard(context, l10n, feed),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionLabel(String text) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 4),
    child: Text(
      text,
      style: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w600,
        color: Colors.grey[500],
      ),
    ),
  );

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
        // answer_posted 复用 tutorialId 这个字段传 questionId（后端
        // createAnswer 目前发通知时还没传这个参数，没传的话这里点了
        //也没地方可跳，是待后端补的一环）
        onTap: n.type == 'answer_posted' && n.tutorialId != null
            ? () => context.push('/questions/${n.tutorialId}')
            : null,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
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
}
