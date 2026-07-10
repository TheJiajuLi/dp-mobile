import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_client.dart';
import '../../../features/auth/auth_service.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../models/notification_model.dart';
import '../providers/messages_provider.dart';
import '../utils/message_avatar.dart';

// 通知分 4 个 tab——评论/点赞是后端真实会产生的 type（见
// tutorial.controller.ts/user.controller.ts 里 createNotification 的调用
// 点）；关注也是真实类型，但跟"邀请回答"这类还没有后端数据模型的内容一起
// 并进"系统"这个兜底 tab，不单独占一个位置（对齐提问功能的邀请回答设计稿，
// 只有 4 个 tab）
enum _NotifFilter { comment, like, inviteAnswer, system }

class NotificationsScreen extends ConsumerStatefulWidget {
  final String? initialTab;
  const NotificationsScreen({super.key, this.initialTab});
  @override
  ConsumerState<NotificationsScreen> createState() =>
      _NotificationsScreenState();
}

class _NotificationsScreenState extends ConsumerState<NotificationsScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabCtrl;

  List<Map<String, dynamic>> _invites = [];
  bool _loadingInvites = false;

  // Tab 顺序跟 TabBar/TabBarView 里手写的四个 Tab 一一对应：
  // 0=评论 1=点赞 2=邀请回答 3=系统
  static const _tabIndexByName = {
    'comment': 0,
    'like': 1,
    'invites': 2,
    'system': 3,
  };

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(
      length: 4,
      vsync: this,
      initialIndex: _tabIndexByName[widget.initialTab] ?? 0,
    );
    _loadInvites();
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadInvites() async {
    setState(() => _loadingInvites = true);
    debugPrint('[invites] current user id: ${ref.read(currentUserProvider)?.id}');
    final res = await ref.read(apiClientProvider).get('/auth/questions/invites');
    debugPrint('[invites] success=${res.success} statusCode=${res.statusCode} message=${res.message}');
    debugPrint('[invites] raw data: ${res.data}');
    if (!mounted) return;
    setState(() {
      _loadingInvites = false;
      if (res.success && res.data != null) {
        _invites = ((res.data['invites'] as List?) ?? [])
            .map((i) => Map<String, dynamic>.from(i as Map))
            .toList();
      }
    });
    debugPrint('[invites] parsed count: ${_invites.length}');
  }

  Future<void> _respondInvite(Map<String, dynamic> inv, String action) async {
    setState(() => _invites.remove(inv));
    final res = await ref
        .read(apiClientProvider)
        .post('/auth/questions/invites/${inv['id']}/respond', data: {'action': action});
    if (!mounted || res.success) return;
    // 失败就把邀请加回列表——不能让用户以为已经处理成功了
    setState(() => _invites.add(inv));
  }

  void _acceptInvite(Map<String, dynamic> inv) {
    context.push(
      '/answer-question',
      extra: {
        'questionId': inv['question_id'],
        'questionText': inv['question_text'],
        'domain': inv['domain'],
      },
    );
    _respondInvite(inv, 'accept');
  }

  void _ignoreInvite(Map<String, dynamic> inv) {
    _respondInvite(inv, 'ignore');
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

  List<AppNotification> _filtered(List<AppNotification> all, _NotifFilter f) {
    switch (f) {
      case _NotifFilter.comment:
        return all.where((n) => n.type == 'comment').toList();
      case _NotifFilter.like:
        return all.where((n) => n.type == 'like').toList();
      case _NotifFilter.inviteAnswer:
        return const [];
      case _NotifFilter.system:
        // invite_answer/answer_posted 分别有自己的专属展示位置（邀请回答
        // Tab 用的是 question_invites 那份独立数据源，answer_posted 靠
        // 通知本身跳问题详情）——系统Tab是给没有专属去处的类型兜底，这两种
        // 不该在这也重复出现一遍
        return all
            .where(
              (n) =>
                  n.type != 'comment' &&
                  n.type != 'like' &&
                  n.type != 'invite_answer' &&
                  n.type != 'answer_posted',
            )
            .toList();
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final notifications = ref.watch(notificationsProvider);

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
            TabBar(
              controller: _tabCtrl,
              labelColor: Theme.of(context).textTheme.bodyLarge?.color,
              unselectedLabelColor: Colors.grey,
              labelStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
              unselectedLabelStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w400),
              indicatorColor: kMessagesPrimary,
              indicatorSize: TabBarIndicatorSize.label,
              dividerColor: Colors.transparent,
              tabs: [
                Tab(text: l10n.notifFilterComments),
                Tab(text: l10n.notifFilterLikes),
                Tab(
                  // 4个固定宽度的tab里，"邀请回答"比"评论/点赞/系统"多两个字，
                  // 加上未读徽标后在等分宽度下会溢出——用 FittedBox 让它在
                  // 塞不下时整体缩小，而不是继续走 isScrollable（那样4个tab
                  // 就不再是等分铺满，跟其余三个tab的视觉节奏不一致了）
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(l10n.notifFilterInviteAnswer),
                        if (_invites.isNotEmpty) ...[
                          const SizedBox(width: 4),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                            decoration: BoxDecoration(
                              color: Colors.red,
                              borderRadius: BorderRadius.circular(99),
                            ),
                            child: Text(
                              '${_invites.length}',
                              style: const TextStyle(
                                fontSize: 9,
                                color: Colors.white,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                Tab(text: l10n.notifFilterSystem),
              ],
            ),
            Expanded(
              child: TabBarView(
                controller: _tabCtrl,
                children: [
                  _notifListTab(l10n, _filtered(notifications, _NotifFilter.comment)),
                  _notifListTab(l10n, _filtered(notifications, _NotifFilter.like)),
                  _inviteAnswerTab(l10n),
                  _notifListTab(l10n, _filtered(notifications, _NotifFilter.system)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _notifListTab(AppLocalizations l10n, List<AppNotification> filtered) {
    if (filtered.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.notifications_none, size: 56, color: Colors.grey),
            const SizedBox(height: 12),
            Text(
              l10n.noNotificationsYet,
              style: const TextStyle(color: Colors.grey, fontSize: 15),
            ),
          ],
        ),
      );
    }
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      physics: const AlwaysScrollableScrollPhysics(),
      children: [_notificationGroupCard(context, l10n, filtered)],
    );
  }

  Widget _inviteAnswerTab(AppLocalizations l10n) {
    debugPrint('[invites] render: loading=$_loadingInvites isEmpty=${_invites.isEmpty} _invites=$_invites');
    if (_loadingInvites && _invites.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    return RefreshIndicator(
      onRefresh: _loadInvites,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(12),
        children: [
          ..._invites.map(
            (inv) => _InviteCard(
              invite: inv,
              onAccept: () => _acceptInvite(inv),
              onIgnore: () => _ignoreInvite(inv),
            ),
          ),
          if (_invites.isEmpty)
            Center(
              child: Padding(
                padding: const EdgeInsets.only(top: 60),
                child: Column(
                  children: [
                    Icon(
                      Icons.mark_email_read_outlined,
                      size: 48,
                      color: Colors.grey[300],
                    ),
                    const SizedBox(height: 12),
                    Text(l10n.inviteAnswerEmpty, style: TextStyle(color: Colors.grey[400])),
                  ],
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.only(top: 16),
            child: Text(
              l10n.inviteAnswerFooter,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 11, color: Colors.grey[400], height: 1.7),
            ),
          ),
        ],
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
        // answer_posted 通知复用 tutorialId 这个字段传 questionId（后端
        // createAnswer 目前发通知时还没传这个参数，没传的话这里点了也
        // 没地方可跳，是待后端补的一环，见任务小结）
        onTap: n.type == 'answer_posted' && n.tutorialId != null
            ? () => context.push('/questions/${n.tutorialId}')
            : null,
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

}

// 邀请回答卡片——问题原文+匹配原因+接受/忽略，跟极索提问功能共用同一批
// mock 数据（后端还没有对应的邀请模型）
class _InviteCard extends StatelessWidget {
  final Map<String, dynamic> invite;
  final VoidCallback onAccept;
  final VoidCallback onIgnore;
  const _InviteCard({
    required this.invite,
    required this.onAccept,
    required this.onIgnore,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF1A0E2E), Color(0xFF0D1A38)],
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: kMessagesPrimary.withValues(alpha: 0.3),
          width: 0.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: kMessagesPrimary.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.phone_in_talk,
                  size: 16,
                  color: kMessagesPrimary,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.notifFilterInviteAnswer,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                    Text(
                      '极索系统 · ${messageTimeAgo(l10n, ((invite['question_created_at'] as num?)?.toInt() ?? 0) * 1000)}',
                      style: TextStyle(
                        fontSize: 10,
                        color: Colors.white.withValues(alpha: 0.4),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            '「${invite['question_text']}」',
            style: TextStyle(
              fontSize: 13,
              fontStyle: FontStyle.italic,
              color: Colors.white.withValues(alpha: 0.8),
              height: 1.5,
            ),
          ),
          const SizedBox(height: 6),
          RichText(
            text: TextSpan(
              style: TextStyle(fontSize: 11, color: Colors.white.withValues(alpha: 0.4)),
              children: [
                const TextSpan(text: '来自用户 '),
                TextSpan(
                  text: '@${invite['asker_name']}',
                  style: const TextStyle(
                    color: Color(0xFF818CF8),
                    fontWeight: FontWeight.w500,
                  ),
                ),
                TextSpan(text: ' · ${invite['reason']}'),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: GestureDetector(
                  onTap: onAccept,
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 9),
                    decoration: BoxDecoration(
                      color: kMessagesPrimary,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Center(
                      child: Text(
                        l10n.inviteAnswerAccept,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: GestureDetector(
                  onTap: onIgnore,
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 9),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.1),
                        width: 0.5,
                      ),
                    ),
                    child: Center(
                      child: Text(
                        l10n.inviteAnswerIgnore,
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.white.withValues(alpha: 0.5),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
