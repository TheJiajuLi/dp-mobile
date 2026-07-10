import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_client.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../models/notification_model.dart';
import '../providers/messages_provider.dart';
import '../utils/message_avatar.dart';

// 之前是评论/点赞/邀请回答/系统四个Tab，邀请回答现在改成汇总卡+专属
// 列表页（invite_list_screen.dart）单独承接，这个页面收窄成"最近通知"：
// 顶部"需要你处理"（邀请汇总卡，count>0才显示）+"最新动态"（除
// invite_answer 外的普通通知，扁平列表，不分type）
class NotificationsScreen extends ConsumerStatefulWidget {
  const NotificationsScreen({super.key});
  @override
  ConsumerState<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends ConsumerState<NotificationsScreen> {
  List<Map<String, dynamic>> _invites = [];
  bool _loadingInvites = false;

  @override
  void initState() {
    super.initState();
    _loadInvites();
  }

  Future<void> _loadInvites() async {
    setState(() => _loadingInvites = true);
    final res = await ref.read(apiClientProvider).get('/auth/questions/invites');
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
    // invite_answer 有自己的汇总卡+专属列表页；answer_posted 靠这条通知
    // 本身跳问题详情，两种都不该在"最新动态"这个通用兜底列表里再出现一遍
    final feed = notifications
        .where((n) => n.type != 'invite_answer' && n.type != 'answer_posted')
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
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
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
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  children: [
                    if (!_loadingInvites && _invites.isNotEmpty) ...[
                      _sectionLabel('需要你处理'),
                      const SizedBox(height: 6),
                      _InviteSummaryCard(
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
                              const Icon(Icons.notifications_none, size: 56, color: Colors.grey),
                              const SizedBox(height: 12),
                              Text(
                                l10n.noNotificationsYet,
                                style: const TextStyle(color: Colors.grey, fontSize: 15),
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
      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey[500]),
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
        border: isDark ? Border.all(color: Theme.of(context).dividerColor, width: 0.5) : null,
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
            if (i > 0) Divider(height: 0.5, indent: 68, color: Theme.of(context).dividerColor),
            _notificationTile(context, l10n, items[i]),
          ],
        ],
      ),
    );
  }

  Widget _notificationTile(BuildContext context, AppLocalizations l10n, AppNotification n) {
    return Container(
      color: n.isRead ? null : kMessagesPrimary.withValues(alpha: 0.07),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        leading: GestureDetector(
          onTap: (n.fromUsername?.isNotEmpty ?? false)
              ? () => context.push('/users/${n.fromUsername}')
              : null,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              buildMessageAvatar(n.fromAvatar, n.fromUsername ?? l10n.systemNotificationInitial, radius: 22),
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
          style: TextStyle(fontSize: 14, fontWeight: n.isRead ? FontWeight.w400 : FontWeight.w500),
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
                child: const Icon(Icons.article_outlined, color: kMessagesPrimary, size: 20),
              )
            : n.isRead
            ? null
            : Container(
                width: 8,
                height: 8,
                decoration: const BoxDecoration(color: kMessagesPrimary, shape: BoxShape.circle),
              ),
      ),
    );
  }
}

// 邀请回答汇总卡——点击进 /invite-list 专属列表页，不在这个页面里直接
// 接受/忽略
class _InviteSummaryCard extends StatelessWidget {
  final int count;
  final List<Map<String, dynamic>> invites;
  final VoidCallback onTap;

  const _InviteSummaryCard({required this.count, required this.invites, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    if (count == 0) return const SizedBox.shrink();

    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: isDark ? Colors.white.withValues(alpha: 0.04) : Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isDark ? Colors.white.withValues(alpha: 0.08) : const Color(0xFFEBEBEB),
            width: 0.5,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
              child: Row(
                children: [
                  Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Container(
                        width: 42,
                        height: 42,
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFFEEF0FF), Color(0xFFE0E7FF)],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(Icons.question_answer_outlined, size: 20, color: Color(0xFF6366F1)),
                      ),
                      Positioned(
                        top: -4,
                        right: -4,
                        child: Container(
                          constraints: const BoxConstraints(minWidth: 18),
                          height: 18,
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          decoration: BoxDecoration(
                            color: const Color(0xFFEF4444),
                            borderRadius: BorderRadius.circular(99),
                            border: Border.all(
                              color: isDark ? const Color(0xFF0A0A1A) : Colors.white,
                              width: 1.5,
                            ),
                          ),
                          child: Center(
                            child: Text(
                              '$count',
                              style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: Colors.white),
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
                        const Text('邀请回答', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                        const SizedBox(height: 2),
                        Text(
                          '有 $count 个问题等待你的见解',
                          style: TextStyle(
                            fontSize: 12,
                            color: isDark ? Colors.white.withValues(alpha: 0.4) : Colors.grey[500],
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    Icons.chevron_right,
                    size: 18,
                    color: isDark ? Colors.white.withValues(alpha: 0.3) : Colors.grey[400],
                  ),
                ],
              ),
            ),
            if (invites.isNotEmpty)
              SizedBox(
                height: 30,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.fromLTRB(14, 0, 14, 0),
                  itemCount: invites.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 6),
                  itemBuilder: (ctx, i) {
                    final q = (invites[i]['question_text'] as String?) ?? '';
                    return Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: const Color(0xFF6366F1).withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(99),
                        border: Border.all(color: const Color(0xFF6366F1).withValues(alpha: 0.2), width: 0.5),
                      ),
                      child: Text(
                        q.length > 14 ? '${q.substring(0, 14)}...' : q,
                        style: const TextStyle(fontSize: 11, color: Color(0xFF6366F1)),
                      ),
                    );
                  },
                ),
              ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }
}
