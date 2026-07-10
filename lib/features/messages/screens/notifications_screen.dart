import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_client.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../auth/auth_service.dart';
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
  // 并不代表点了那个按钮，红点因此一直不消——本地先乐观清零，
  // 不等接口返回，体验更顺
  Future<void> _markAllRead() async {
    final notifs = ref.read(notificationsProvider);
    // 消息Tab红点现在是"通知+群组消息"的合计（total字段），这里只标记
    // 通知已读，不能直接把整个红点清零——不然还没读的群消息也会被
    // 一起隐藏，等下一次轮询才会"诡异地"重新冒出来。只减掉通知未读的
    // 那一部分，群消息的部分保留
    final unreadNotifCount = notifs.where((n) => !n.isRead).length;
    if (unreadNotifCount > 0) {
      final current = ref.read(unreadCountProvider);
      ref.read(unreadCountProvider.notifier).state =
          (current - unreadNotifCount).clamp(0, current);
    }
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

  // group_invite 通知复用 tutorial_id 这个字段存 group_id（跟
  // invite_answer/answer_posted 是同一个FK槽位复用套路）。标记已读走的
  // 是页面级的 _markAllRead()，这里不用再单独标一次
  Future<void> _handleGroupInvite(AppNotification n) async {
    final groupId = n.tutorialId;
    if (groupId == null) return;

    final res = await ref.read(apiClientProvider).get('/auth/groups/$groupId');
    if (!mounted) return;
    if (!res.success || res.data is! Map) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('群组不存在或已解散')));
      return;
    }

    final data = res.data as Map;
    final group = Map<String, dynamic>.from(data['group'] as Map? ?? {});
    final members = ((data['members'] as List?) ?? [])
        .map((m) => Map<String, dynamic>.from(m as Map))
        .toList();
    final myId = ref.read(currentUserProvider)?.id;
    final alreadyJoined = members.any((m) => m['user_id']?.toString() == myId);

    if (alreadyJoined) {
      context.push(
        '/group/$groupId',
        extra: {
          'name': group['name'],
          'memberCount': (group['member_count'] as num?)?.toInt(),
        },
      );
    } else {
      _showJoinGroupSheet(group);
    }
  }

  void _showJoinGroupSheet(Map<String, dynamic> group) {
    final groupId = group['id']?.toString() ?? '';
    final name = group['name'] as String? ?? '';
    final description = group['description'] as String?;
    final memberCount = (group['member_count'] as num?)?.toInt() ?? 0;
    final isPublic = group['is_public'] == 1 || group['is_public'] == true;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final isDark = Theme.of(ctx).brightness == Brightness.dark;
        return Container(
          decoration: BoxDecoration(
            color: Theme.of(ctx).cardColor,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 36,
                height: 3,
                margin: const EdgeInsets.only(top: 10, bottom: 16),
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Center(
                  child: Text(
                    name.isNotEmpty ? name.substring(0, 1) : '群',
                    style: const TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                name,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '$memberCount 名成员 · ${isPublic ? "公开群" : "私密群"}',
                style: TextStyle(
                  fontSize: 13,
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.4)
                      : Colors.grey[500],
                ),
              ),
              if (description?.isNotEmpty ?? false) ...[
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Text(
                    description!,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      color: isDark
                          ? Colors.white.withValues(alpha: 0.5)
                          : Colors.grey[600],
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 24),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Column(
                  children: [
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: ElevatedButton(
                        onPressed: () async {
                          Navigator.pop(ctx);
                          await _joinAndEnterGroup(groupId, name, memberCount);
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF6366F1),
                          foregroundColor: Colors.white,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: const Text(
                          '加入并进入群聊',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: TextButton(
                        onPressed: () => Navigator.pop(ctx),
                        style: TextButton.styleFrom(
                          backgroundColor: Colors.grey.withValues(alpha: 0.08),
                          foregroundColor: Colors.grey[600],
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: const Text('忽略', style: TextStyle(fontSize: 14)),
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(height: MediaQuery.of(ctx).padding.bottom + 8),
            ],
          ),
        );
      },
    );
  }

  // 后端 group.routes.ts 目前只有 invite/leave/disband，没有"自己申请
  // 加入"这个接口（跟搜索页群组Tab那个"加入"按钮是同一个缺口）——真调用
  // 真实但目前会失败的 POST /:id/join，失败给明确提示，不假装加入成功
  Future<void> _joinAndEnterGroup(
    String groupId,
    String name,
    int memberCount,
  ) async {
    final res = await ref
        .read(apiClientProvider)
        .post('/auth/groups/$groupId/join');
    if (!mounted) return;
    if (!res.success) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(res.message ?? '加入失败，请稍后重试')));
      return;
    }
    context.push(
      '/group/$groupId',
      extra: {'name': name, 'memberCount': memberCount + 1},
    );
  }

  Color _typeColor(String type) {
    switch (type) {
      case 'like':
        return Colors.red;
      case 'comment':
        return kMessagesPrimary;
      case 'follow':
        return const Color(0xFF34C759);
      case 'group_invite':
        return const Color(0xFF6366F1);
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
      case 'group_invite':
        return Icons.groups;
      default:
        return Icons.notifications;
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final notifications = ref.watch(notificationsProvider);
    // invite_answer 有自己专属的汇总卡+列表页，mention 有消息主页的"提及"
    // 入口+专属页，都不在这重复出现；answer_posted 没有专属入口，得留在
    // "最新动态"里，点击跳问题详情（之前重构成汇总卡布局时误把
    // invite_answer/answer_posted 一起过滤掉了，导致 answer_posted 完全
    // 找不到地方点开——2026-07-10 修复，只过滤 invite_answer 一个）
    final feed = notifications
        .where((n) => n.type != 'invite_answer' && n.type != 'mention')
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
    final isGroupInvite = n.type == 'group_invite';

    return Container(
      color: n.isRead ? null : kMessagesPrimary.withValues(alpha: 0.07),
      child: ListTile(
        // answer_posted 复用 tutorialId 传 questionId（后端 createAnswer
        // 目前发通知时还没传这个参数，没传的话这里点了也没地方可跳，是
        // 待后端补的一环）；group_invite 复用 tutorialId 传 group_id
        onTap: isGroupInvite && n.tutorialId != null
            ? () => _handleGroupInvite(n)
            : n.type == 'answer_posted' && n.tutorialId != null
            ? () => context.push('/questions/${n.tutorialId}')
            : null,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        leading: GestureDetector(
          onTap: isGroupInvite
              ? null
              : (n.fromUsername?.isNotEmpty ?? false)
              ? () => context.push('/users/${n.fromUsername}')
              : null,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              // 群邀请通知没有群名字段可用（后端目前只塞了固定文案，
              // 没有把群名一起存进 content），先用一个通用的群组渐变头像
              // 占位，不展示邀请人头像——邀请人身份不是这条通知的重点，
              // "邀请你加入哪个群"才是
              if (isGroupInvite)
                Container(
                  width: 44,
                  height: 44,
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.groups,
                    color: Colors.white,
                    size: 20,
                  ),
                )
              else
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
        trailing: isGroupInvite
            ? Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: const Color(0xFF6366F1).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.groups_outlined,
                  color: Color(0xFF6366F1),
                  size: 20,
                ),
              )
            : n.tutorialId != null
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
