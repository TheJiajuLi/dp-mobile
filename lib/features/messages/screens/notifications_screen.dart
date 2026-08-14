import 'dart:async';
import '../../../core/theme/app_colors.dart';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_client.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../auth/auth_service.dart';
import '../models/notification_model.dart';
import '../providers/messages_provider.dart';
import '../utils/message_avatar.dart';
import '../utils/notification_nav.dart';
import '../widgets/invite_summary_card.dart';

// 通知页（2026-07 重设计）：顶栏（返回 + 通知 + 全部已读 + 筛选占位）→
// 「需要你处理」邀请汇总卡（/invite-list 的唯一入口，保留在筛选 chips 上方）
// → 分类筛选 chips（全部/点赞/评论/关注/提及/系统）→ 按 今天/昨天/更早
// 分组的通知列表。base feed 排除 invite_answer / forum_reply（各有专属页），
// mention / group_message_mention 纳入本页（对应「提及」筛选）。
//
// 已读模型改为"显式"：进页面不再自动全部已读，未读蓝点常驻，直到用户点
// 单条（顺手标该条已读）或点顶部「全部已读」主动清——所以这版才看得到
// 未读点。
class NotificationsScreen extends ConsumerStatefulWidget {
  // HD 根标签内嵌时（HdNotificationsPage）传 false 隐藏返回键——根标签没有可
  // pop 的路由，写死 context.pop() 会抛「nothing to pop」。手机端 push 进来不传
  final bool showBackButton;
  const NotificationsScreen({super.key, this.showBackButton = true});
  @override
  ConsumerState<NotificationsScreen> createState() =>
      _NotificationsScreenState();
}

class _NotificationsScreenState extends ConsumerState<NotificationsScreen> {
  static const _primary = AppColors.primary;

  List<Map<String, dynamic>> _invites = [];
  bool _loadingInvites = false;

  // 「回关」按钮状态：通知不带 fromUserId，靠 fromUsername 现查一次解析出
  // userId + 我是否已关注（isFollowing），点按钮就在原地关注/取关，切换成
  // 绿色「已回关」。都按 username 缓存，同一个人只查一次。
  final Map<String, String> _followUserId = {}; // username -> userId
  final Map<String, bool> _isFollowing = {}; // username -> 我是否已关注
  final Set<String> _resolvingFollow = {}; // 正在解析状态的 username
  final Set<String> _togglingFollow = {}; // 关注/取关请求在途的 username

  String _activeFilter = 'all';
  // 顶部「排序/筛选」（tune 图标）落地：时间倒序/正序 + 只看未读
  bool _newestFirst = true;
  bool _unreadOnly = false;
  static const _filters = [
    {'key': 'all', 'label': '全部'},
    {'key': 'like', 'label': '点赞'},
    {'key': 'comment', 'label': '评论'},
    {'key': 'follow', 'label': '关注'},
    {'key': 'mention', 'label': '提及'},
    {'key': 'system', 'label': '系统'},
  ];

  @override
  void initState() {
    super.initState();
    _loadInvites();
    // 进页面拉最新通知，但不再自动"全部已读"——未读点交给用户点单条或点
    // 顶部「全部已读」主动清（跟这次重设计的显式已读模型一致）
    unawaited(ref.read(notificationsProvider.notifier).fetch());
  }

  // 顶部「全部已读」按钮：本地立刻清 nav 红点 + 后端标记全部已读（markAllRead
  // 会把本地每条 isRead 置 true，未读蓝点随之消失）
  Future<void> _markAllRead() async {
    _applyUnreadDelta(ref.read(notificationsProvider));
    unawaited(_syncMarkAllRead());
  }

  // 真正的已读标记必须先老老实实 fetch 一次拿到服务端当前的真实数据，
  // 不能直接信本地缓存——缓存为空/滞后时用它判断"有没有未读"，算出来的
  // 结果会是假的"没有未读"，markAllRead() 根本不会被调用，这条通知会
  // 永久卡在服务端"未读"状态
  Future<void> _syncMarkAllRead() async {
    await ref.read(notificationsProvider.notifier).fetch();
    if (!mounted) return;
    final notifs = ref.read(notificationsProvider);
    if (notifs.any((n) => !n.isRead)) {
      await ref.read(notificationsProvider.notifier).markAllRead();
    }
  }

  // 消息Tab红点是"通知+群组消息"的合计（total字段），这里只减掉通知未读
  // 的那一部分，不能直接把整个红点清零——不然还没读的群消息也会被一起
  // 隐藏，等下一次轮询才会"诡异地"重新冒出来
  void _applyUnreadDelta(List<AppNotification> notifs) {
    final unreadCount = notifs.where((n) => !n.isRead).length;
    if (unreadCount == 0) return;
    final current = ref.read(unreadCountProvider);
    ref.read(unreadCountProvider.notifier).state = (current - unreadCount)
        .clamp(0, current);
  }

  // 点开单条通知顺手标记这一条已读——本地先乐观标记，未读点/红点立刻消失，
  // 不等网络；真正的已读请求在后台异步发
  void _openNotification(AppNotification n) {
    if (!n.isRead) {
      setState(() => n.isRead = true);
      final current = ref.read(unreadCountProvider);
      if (current > 0) {
        ref.read(unreadCountProvider.notifier).state = current - 1;
      }
      unawaited(ref.read(notificationsProvider.notifier).markRead([n.id]));
    }
    openNotificationTarget(context, n);
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

  // group_invite 通知复用 tutorial_id 这个字段存 group_id。标记已读走的是
  // 页面级的 _markAllRead()/点击标记，这里不用再单独标一次
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
                    colors: [AppColors.primary, Color(0xFF8B5CF6)],
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
                          backgroundColor: AppColors.primary,
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

  // 后端 group.routes.ts 目前只有 invite/leave/disband，没有"自己申请加入"
  // 这个接口——真调用真实但目前会失败的 POST /:id/join，失败给明确提示，
  // 不假装加入成功
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

  // ── 通知类型 → 展示辅助 ──────────────────────────────────────────
  IconData _badgeIcon(String type) {
    switch (type) {
      case 'like':
        return Icons.favorite;
      case 'comment':
        return Icons.chat_bubble;
      case 'follow':
        return Icons.person_add;
      case 'mention':
      case 'group_message_mention':
        return Icons.alternate_email;
      case 'group_invite':
        return Icons.group_add;
      default:
        return Icons.notifications;
    }
  }

  Color _badgeColor(String type) {
    switch (type) {
      case 'like':
        return const Color(0xFFEF4444);
      case 'comment':
        return AppColors.primary;
      case 'follow':
        return const Color(0xFF2563EB);
      case 'mention':
      case 'group_message_mention':
        return const Color(0xFF0891B2);
      case 'group_invite':
        return AppColors.primary;
      default:
        return Colors.grey;
    }
  }

  // 主文案里"用户名之后"那半句。系统类没有 fromUsername，走 _mainLine 里
  // 直接展示后端整句的分支，不会用到这里
  String _actionText(String type) {
    switch (type) {
      case 'like':
        return '赞了你的文章';
      case 'comment':
        return '评论了你的文章';
      case 'follow':
        return '关注了你';
      case 'mention':
        return '提及了你';
      case 'group_message_mention':
        return '在群聊中提及了你';
      case 'group_invite':
        return '邀请你加入群组';
      default:
        return '给你发来新通知';
    }
  }

  // 右侧内容缩略图取不到真实封面（通知模型没有 coverImage 字段），用一个
  // 带类型语义的图标盒兜底
  IconData _contentIcon(String type) {
    switch (type) {
      case 'group_invite':
        return Icons.groups_outlined;
      case 'mention':
      case 'group_message_mention':
        return Icons.alternate_email;
      case 'like':
      case 'comment':
        return Icons.article_outlined;
      default:
        return Icons.notifications_outlined;
    }
  }

  // createdAt 是毫秒（模型里已 *1000），这里不再乘 1000
  String _relativeTime(int ms) {
    final diff = DateTime.now().difference(
      DateTime.fromMillisecondsSinceEpoch(ms),
    );
    if (diff.inMinutes < 1) return '刚刚';
    if (diff.inMinutes < 60) return '${diff.inMinutes}分钟前';
    if (diff.inHours < 24) return '${diff.inHours}小时前';
    if (diff.inDays == 1) return '昨天';
    return '${diff.inDays}天前';
  }

  // 按自然日分组（不是简单 now-dt 的 24 小时差，跨零点更准）
  String _groupLabel(int ms) {
    final now = DateTime.now();
    final dt = DateTime.fromMillisecondsSinceEpoch(ms);
    final today = DateTime(now.year, now.month, now.day);
    final that = DateTime(dt.year, dt.month, dt.day);
    final diff = today.difference(that).inDays;
    if (diff <= 0) return '今天';
    if (diff == 1) return '昨天';
    return '更早';
  }

  // comment 通知的后端 content 形如 "用户名 评论了你的教程《标题》：评论正文"，
  // 用 "》：" 作分隔提取评论正文（标题包在《》里，正文接在后面）。提取不到
  // 就返回 null，退回展示文章标题
  String? _commentBody(AppNotification n) {
    if (n.type != 'comment') return null;
    final c = n.content ?? '';
    final idx = c.indexOf('》：');
    if (idx >= 0 && idx + 2 < c.length) {
      final body = c.substring(idx + 2).trim();
      if (body.isNotEmpty) return body;
    }
    return null;
  }

  bool _matchesFilter(AppNotification n) {
    switch (_activeFilter) {
      case 'like':
        return n.type == 'like';
      case 'comment':
        return n.type == 'comment';
      case 'follow':
        return n.type == 'follow';
      case 'mention':
        return n.type == 'mention' || n.type == 'group_message_mention';
      case 'system':
        // 系统/其它：除 点赞/评论/关注/提及 之外全归这里（含 system、
        // group_invite、answer_posted 等），保证「全部」= 各 chip 之并集
        return !const [
          'like',
          'comment',
          'follow',
          'mention',
          'group_message_mention',
        ].contains(n.type);
      default:
        return true; // all
    }
  }

  // tune 图标的排序/筛选面板：时间倒序/正序 + 只看未读
  void _showSortSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final ink = Theme.of(ctx).textTheme.bodyLarge?.color;
        return StatefulBuilder(
          builder: (ctx, setSheet) {
            Widget sortRow(String label, bool selected, VoidCallback onTap) {
              return ListTile(
                dense: true,
                onTap: () {
                  onTap();
                  setSheet(() {});
                },
                title: Text(
                  label,
                  style: TextStyle(
                    fontSize: 15,
                    color: ink,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                  ),
                ),
                trailing: selected
                    ? const Icon(Icons.check, size: 20, color: _primary)
                    : null,
              );
            }

            return Container(
              decoration: BoxDecoration(
                color: Theme.of(ctx).scaffoldBackgroundColor,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(20),
                ),
              ),
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(ctx).padding.bottom + 8,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 36,
                    height: 4,
                    margin: const EdgeInsets.symmetric(vertical: 12),
                    decoration: BoxDecoration(
                      color: Colors.grey[300],
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        '排序',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Colors.grey[500],
                        ),
                      ),
                    ),
                  ),
                  sortRow(
                    '最新在前',
                    _newestFirst,
                    () => setState(() => _newestFirst = true),
                  ),
                  sortRow(
                    '最早在前',
                    !_newestFirst,
                    () => setState(() => _newestFirst = false),
                  ),
                  Divider(height: 1, color: Theme.of(ctx).dividerColor),
                  SwitchListTile(
                    value: _unreadOnly,
                    onChanged: (v) {
                      setState(() => _unreadOnly = v);
                      setSheet(() {});
                    },
                    activeThumbColor: _primary,
                    // 去掉 M3 Switch 关闭态默认的一圈描边
                    trackOutlineColor: const WidgetStatePropertyAll(
                      Colors.transparent,
                    ),
                    title: Text(
                      '只看未读',
                      style: TextStyle(fontSize: 15, color: ink),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final notifications = ref.watch(notificationsProvider);

    // base feed：invite_answer / forum_reply 各有专属页，排除出本页；mention /
    // group_message_mention 保留（对应「提及」筛选）
    final base = notifications
        .where((n) => n.type != 'invite_answer' && n.type != 'forum_reply')
        .toList();
    var filtered = base.where(_matchesFilter).toList();
    // 「只看未读」+ 排序（tune 面板）——默认最新在前，可切最早在前。
    // 今天/更早分组的 _buildFeed 只做连续去重，正序倒序都能正确分组
    if (_unreadOnly) {
      filtered = filtered.where((n) => !n.isRead).toList();
    }
    filtered.sort(
      (a, b) => _newestFirst
          ? b.createdAt.compareTo(a.createdAt)
          : a.createdAt.compareTo(b.createdAt),
    );

    return Scaffold(
      // 浅色跟首页统一用米白 #FAFAF8（不是全局 scaffold 的 #F7F7FB），
      // 深色仍走主题的 darkBg
      backgroundColor: isDark
          ? Theme.of(context).scaffoldBackgroundColor
          : const Color(0xFFFAFAF8),
      body: SafeArea(
        child: Column(
          children: [
            _buildTopBar(l10n),
            Expanded(
              child: RefreshIndicator(
                onRefresh: () => Future.wait([
                  _loadInvites(),
                  ref.read(notificationsProvider.notifier).fetch(),
                ]),
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: EdgeInsets.zero,
                  children: [
                    // 「需要你处理」邀请汇总卡——保留在筛选 chips 上方
                    if (!_loadingInvites) ...[
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
                        child: _sectionLabel('需要你处理'),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: InviteSummaryCard(
                          count: _invites.length,
                          invites: _invites,
                          onTap: () => context.push('/invite-list'),
                        ),
                      ),
                      const SizedBox(height: 14),
                    ],
                    _buildChips(isDark),
                    const SizedBox(height: 4),
                    if (base.isEmpty)
                      _buildEmptyState(isDark)
                    else if (filtered.isEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 60),
                        child: Center(
                          child: Text(
                            '该分类下暂无通知',
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.grey[400],
                            ),
                          ),
                        ),
                      )
                    else
                      ..._buildFeed(filtered, isDark, l10n),
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionLabel(String text) => Text(
    text,
    style: TextStyle(
      fontSize: 12,
      fontWeight: FontWeight.w600,
      color: Colors.grey[500],
    ),
  );

  Widget _buildTopBar(AppLocalizations l10n) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 6, 8, 4),
    child: Row(
      children: [
        // 手机端是 push 进来的，保留返回箭头；HD 根标签内嵌时 showBackButton
        // 传 false，隐藏返回键（根标签没有可 pop 的路由）
        if (widget.showBackButton)
          IconButton(
            onPressed: () => context.pop(),
            icon: const Icon(Icons.arrow_back_ios, size: 18),
          ),
        const Text(
          '通知',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
        ),
        const Spacer(),
        IconButton(
          tooltip: '全部已读',
          onPressed: _markAllRead,
          icon: const Icon(Icons.done_all_outlined),
        ),
        // 筛选入口暂时留空位（未来接高级筛选）
        IconButton(
          onPressed: _showSortSheet,
          icon: Icon(
            Icons.tune_outlined,
            // 非默认（切了正序 / 开了只看未读）时高亮，提示当前有筛选生效
            color: (!_newestFirst || _unreadOnly) ? _primary : null,
          ),
        ),
      ],
    ),
  );

  Widget _buildChips(bool isDark) => SizedBox(
    height: 34,
    child: ListView.separated(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      itemCount: _filters.length,
      separatorBuilder: (_, __) => const SizedBox(width: 8),
      itemBuilder: (ctx, i) {
        final f = _filters[i];
        final isActive = _activeFilter == f['key'];
        return GestureDetector(
          onTap: () => setState(() => _activeFilter = f['key']!),
          child: Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              decoration: BoxDecoration(
                color: isActive
                    ? _primary
                    : isDark
                    ? const Color(0xFF1A1A35)
                    : const Color(0xFFF5F5F5),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: isActive
                      ? _primary
                      : isDark
                      ? const Color(0xFF2A2A4A)
                      : const Color(0xFFEBEBEB),
                  width: 0.5,
                ),
              ),
              child: Text(
                f['label']!,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: isActive
                      ? Colors.white
                      : isDark
                      ? const Color(0xFF7A80A0)
                      : const Color(0xFF888888),
                ),
              ),
            ),
          ),
        );
      },
    ),
  );

  // 通知按 今天/昨天/更早 分组（列表已按 createdAt 倒序），连续同组只出一个
  // 分组标题
  List<Widget> _buildFeed(
    List<AppNotification> items,
    bool isDark,
    AppLocalizations l10n,
  ) {
    final widgets = <Widget>[];
    String? lastGroup;
    for (final n in items) {
      final g = _groupLabel(n.createdAt);
      if (g != lastGroup) {
        widgets.add(_groupHeader(g));
        lastGroup = g;
      }
      widgets.add(_notificationCard(n, isDark, l10n));
    }
    return widgets;
  }

  Widget _groupHeader(String label) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
    child: Text(
      label,
      style: TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w500,
        color: Colors.grey[500],
        letterSpacing: 0.5,
      ),
    ),
  );

  // 懒解析某个"关注了你"通知里对方的 userId + 我是否已回关。结果缓存，
  // 同一个 username 在途/已完成都跳过，不会重复请求（build 里 fire-and-forget
  // 调用也安全）。profile 接口可能因对方"主页不公开"403，退回不受隐私影响的
  // 旧接口兜底；都解析不出 id 时静默放弃，按钮退回"跳对方主页"的老行为。
  Future<void> _ensureFollowState(String username) async {
    if (username.isEmpty ||
        _isFollowing.containsKey(username) ||
        _resolvingFollow.contains(username)) {
      return;
    }
    _resolvingFollow.add(username);
    final api = ref.read(apiClientProvider);
    String? userId;
    final res = await api.get('/auth/users/profile/$username');
    if (res.success && res.data is Map) {
      userId = (res.data as Map)['id']?.toString();
    }
    if (userId == null) {
      final alt = await api.get('/auth/users/$username');
      if (alt.success && alt.data is Map) {
        final d = alt.data as Map;
        userId = (d['id'] ?? (d['user'] is Map ? d['user']['id'] : null))
            ?.toString();
      }
    }
    if (userId == null) {
      _resolvingFollow.remove(username);
      return;
    }
    final statusRes = await api.get('/auth/users/$userId/follow-status');
    final following = statusRes.success && statusRes.data is Map
        ? (statusRes.data as Map)['isFollowing'] == true
        : false;
    if (!mounted) {
      _resolvingFollow.remove(username);
      return;
    }
    setState(() {
      _followUserId[username] = userId!;
      _isFollowing[username] = following;
      _resolvingFollow.remove(username);
    });
  }

  // 点「回关/已回关」：原地关注/取关切换。乐观更新 + 失败回滚；还没解析出
  // id（如对方主页不公开）时退回跳对方主页让用户在那边操作。
  Future<void> _toggleFollowBack(String username) async {
    if (username.isEmpty || _togglingFollow.contains(username)) return;
    if (_followUserId[username] == null) {
      await _ensureFollowState(username);
    }
    final userId = _followUserId[username];
    if (userId == null) {
      if (mounted) context.push('/users/$username');
      return;
    }
    final following = _isFollowing[username] ?? false;
    setState(() {
      _togglingFollow.add(username);
      _isFollowing[username] = !following;
    });
    final api = ref.read(apiClientProvider);
    final res = following
        ? await api.delete('/auth/users/$userId/follow')
        : await api.post('/auth/users/$userId/follow');
    if (!mounted) return;
    setState(() {
      _togglingFollow.remove(username);
      if (!res.success) _isFollowing[username] = following; // 回滚
    });
    if (!res.success) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('操作失败：${res.message ?? '请稍后重试'}')),
      );
    }
  }

  // 「关注了你」通知右侧的回关按钮：已回关=绿色胶囊，未回关=紫色胶囊，
  // 请求在途显示转圈。首次渲染顺手 fire-and-forget 解析一次真实关注状态。
  Widget _followBackButton(AppNotification n, bool isDark) {
    final username = n.fromUsername ?? '';
    if (username.isNotEmpty) unawaited(_ensureFollowState(username));
    final following = _isFollowing[username] ?? false;
    final toggling = _togglingFollow.contains(username);
    const green = AppColors.success;
    final fg = following ? green : _primary;
    final bg = following
        ? (isDark ? green.withValues(alpha: 0.18) : const Color(0xFFE8F8F0))
        : (isDark ? const Color(0xFF1A1A35) : const Color(0xFFF0F0FF));
    final borderColor = following
        ? green.withValues(alpha: isDark ? 0.5 : 0.35)
        : (isDark ? const Color(0xFF3A3A5C) : const Color(0xFFDDDDFF));
    return GestureDetector(
      onTap: (username.isEmpty || toggling)
          ? null
          : () => _toggleFollowBack(username),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: borderColor, width: 0.5),
        ),
        child: toggling
            ? SizedBox(
                width: 11,
                height: 11,
                child: CircularProgressIndicator(strokeWidth: 1.4, color: fg),
              )
            : Text(
                following ? '已回关' : '回关',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                  color: fg,
                ),
              ),
      ),
    );
  }

  Widget _notificationCard(
    AppNotification n,
    bool isDark,
    AppLocalizations l10n,
  ) {
    final isGroupInvite = n.type == 'group_invite';
    final ink = isDark ? const Color(0xFFF0F2F8) : const Color(0xFF1A1A1A);
    final muted = isDark ? const Color(0xFF7A80A0) : const Color(0xFF666666);
    final quoteBg = isDark ? const Color(0xFF1A1A35) : const Color(0xFFF8F8F8);
    final commentBody = _commentBody(n);

    return GestureDetector(
      onTap: isGroupInvite && n.tutorialId != null
          ? () => _handleGroupInvite(n)
          : () => _openNotification(n),
      behavior: HitTestBehavior.opaque,
      child: Container(
        color: n.isRead
            ? Colors.transparent
            : _primary.withValues(alpha: isDark ? 0.04 : 0.03),
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 头像 + 类型角标
            Stack(
              clipBehavior: Clip.none,
              children: [
                if (isGroupInvite)
                  Container(
                    width: 40,
                    height: 40,
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        colors: [AppColors.primary, Color(0xFF8B5CF6)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.groups,
                      color: Colors.white,
                      size: 18,
                    ),
                  )
                else
                  buildMessageAvatar(
                    n.fromAvatar,
                    n.fromUsername ?? l10n.systemNotificationInitial,
                    radius: 20,
                  ),
                Positioned(
                  right: -2,
                  bottom: -2,
                  child: Container(
                    width: 18,
                    height: 18,
                    decoration: BoxDecoration(
                      color: _badgeColor(n.type),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: Theme.of(context).scaffoldBackgroundColor,
                        width: 2,
                      ),
                    ),
                    child: Icon(
                      _badgeIcon(n.type),
                      size: 9,
                      color: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(width: 10),

            // 正文
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _mainLine(n, ink),
                  // comment 优先展示评论正文（紫色左线），其它类型展示文章
                  // 标题（灰色左线）
                  if (commentBody != null) ...[
                    const SizedBox(height: 5),
                    _quoteCard(
                      '「$commentBody」',
                      bg: quoteBg,
                      textColor: muted,
                      borderColor: _primary.withValues(alpha: 0.5),
                    ),
                  ] else if (n.tutorialTitle?.isNotEmpty ?? false) ...[
                    const SizedBox(height: 5),
                    _quoteCard(
                      n.tutorialTitle!,
                      bg: quoteBg,
                      textColor: muted,
                      borderColor: isDark
                          ? const Color(0xFF3A3A5C)
                          : const Color(0xFFE0E0E0),
                    ),
                  ],
                  const SizedBox(height: 4),
                  Text(
                    _relativeTime(n.createdAt),
                    style: TextStyle(fontSize: 11, color: Colors.grey[400]),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),

            // 右侧：未读点 + 回关按钮 / 内容图标盒
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (!n.isRead)
                  Container(
                    width: 8,
                    height: 8,
                    decoration: const BoxDecoration(
                      color: _primary,
                      shape: BoxShape.circle,
                    ),
                  ),
                if (!n.isRead) const SizedBox(height: 6),
                if (n.type == 'follow')
                  _followBackButton(n, isDark)
                else
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: isDark
                          ? const Color(0xFF1A1A35)
                          : AppColors.primaryLight,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Icon(
                      _contentIcon(n.type),
                      size: 16,
                      color: _primary,
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // 主文案：有 fromUsername 就加粗用户名 + 类型动作短句；系统类没有用户名，
  // 直接展示后端整句（title 优先，content 兜底）
  Widget _mainLine(AppNotification n, Color ink) {
    final base = TextStyle(fontSize: 13, color: ink, height: 1.5);
    final name = n.fromUsername;
    if (name == null || name.isEmpty) {
      return Text(
        n.title ?? n.content ?? '有新通知',
        style: base,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      );
    }
    return RichText(
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      text: TextSpan(
        style: base,
        children: [
          TextSpan(
            text: name,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          TextSpan(text: ' ${_actionText(n.type)}'),
        ],
      ),
    );
  }

  Widget _quoteCard(
    String text, {
    required Color bg,
    required Color textColor,
    required Color borderColor,
  }) => Container(
    width: double.infinity,
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
    decoration: BoxDecoration(
      color: bg,
      borderRadius: BorderRadius.circular(6),
      border: Border(left: BorderSide(color: borderColor, width: 2)),
    ),
    child: Text(
      text,
      style: TextStyle(fontSize: 11, color: textColor, height: 1.5),
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
    ),
  );

  Widget _buildEmptyState(bool isDark) => Padding(
    padding: const EdgeInsets.only(top: 64, bottom: 40),
    child: Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: isDark
                  ? _primary.withValues(alpha: 0.15)
                  : const Color(0xFFF0F0FF),
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Icon(
              Icons.notifications_outlined,
              size: 28,
              color: _primary,
            ),
          ),
          const SizedBox(height: 14),
          Text(
            '还没有通知',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w500,
              color: isDark ? const Color(0xFFF0F2F8) : const Color(0xFF1A1A1A),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '当有人点赞、评论或关注你时\n会在这里出现',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              color: Colors.grey[400],
              height: 1.6,
            ),
          ),
          const SizedBox(height: 20),
          GestureDetector(
            onTap: () => context.push('/publish'),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              decoration: BoxDecoration(
                color: _primary,
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Text(
                '去发布第一篇文章',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: Colors.white,
                ),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}
