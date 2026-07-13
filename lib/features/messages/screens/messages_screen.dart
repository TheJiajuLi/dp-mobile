import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_client.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../profile/models/user_profile_model.dart';
import '../models/conversation_model.dart';
import '../models/notification_model.dart';
import '../providers/messages_provider.dart';
import '../utils/message_avatar.dart';
import '../utils/notification_nav.dart';
import '../widgets/invite_summary_card.dart';

const _primary = kMessagesPrimary;

// 通知过滤——只用来决定"最近通知"预览区显示哪几条，不是一个独立页面，
// 选中态不需要跨页面保留。@提及以前也在这个筛选器里、点了显示"即将上线"，
// 现在已经有独立的"提及"入口+专属页面了，这里的筛选项就撤掉，不然点进去
// 还会显示过时的"即将上线"提示。原来的 AI 筛选项后端没有对应类型，一直是
// 点了就显示"即将上线"的占位——2026-07-11 换成"回答"，映射真实存在的
// answer_posted 类型（question.controller.ts createNotification 调用里
// 确认过），不再是假占位
enum _PreviewFilter { all, comment, like, save, follow, answer }

class MessagesScreen extends ConsumerStatefulWidget {
  const MessagesScreen({super.key});
  @override
  ConsumerState<MessagesScreen> createState() => _MessagesScreenState();
}

class _MessagesScreenState extends ConsumerState<MessagesScreen>
    with WidgetsBindingObserver {
  Timer? _pollTimer;
  _PreviewFilter _filter = _PreviewFilter.all;
  int? _friendsCount;
  List<Map<String, dynamic>> _invites = [];
  // 论坛这边后端目前没有"我关注的论坛有没有新帖"这种信号，暂时只能退而
  // 求其次：关注了至少一个论坛就提示"有内容"，跟真正的"有没有新帖"不是
  // 一回事，是当前这版的已知局限——只在 initState 拉一次，不用跟着
  // 30秒轮询，关注关系变化不频繁
  bool _hasFollowedForum = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadData();
    _loadFriendsCount();
    _loadForumSignal();
    _pollTimer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => _loadData(),
    );
  }

  // 30秒轮询期间App被切到后台等再回来，正好卡在两次轮询中间的话未读数
  // 会有最多30秒的延迟——回答者发布回答之类的场景不想让提问者等这么久
  // 才看到消息Tab红点更新，App从后台恢复时主动补一次
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _loadData();
  }

  Future<void> _loadData() async {
    await ref.read(notificationsProvider.notifier).fetch();
    await ref.read(conversationsProvider.notifier).fetch();
    final res = await ref
        .read(apiClientProvider)
        .get('/auth/notifications/unread-count');
    if (res.success && res.data != null && mounted) {
      // 后端这个接口更新过了：'unread' 现在只算通知，'total' 才是
      // 通知+群组消息未读之和——消息Tab红点该用 total，不然群里来了新
      // 消息，底部导航栏完全看不出来
      ref.read(unreadCountProvider.notifier).state =
          (res.data['total'] as num?)?.toInt() ?? 0;
      ref.read(mentionUnreadCountProvider.notifier).state =
          (res.data['mention'] as num?)?.toInt() ?? 0;
    }
    final invitesRes = await ref
        .read(apiClientProvider)
        .get('/auth/questions/invites');
    if (invitesRes.success && invitesRes.data != null && mounted) {
      setState(() {
        _invites = ((invitesRes.data['invites'] as List?) ?? [])
            .map((i) => Map<String, dynamic>.from(i as Map))
            .toList();
      });
    }
  }

  // 从消息页 push 出去查看消息（通知/私信/提及/群聊/邀请），返回后主动刷新
  // 未读红点——不用等 30 秒轮询，也不用手动下拉。查看时子页面已在服务端
  // 标记已读，回来重新拉一次 unread-count 就是最新的
  Future<void> _openThenRefresh(String path, {Object? extra}) async {
    await context.push(path, extra: extra);
    if (mounted) _loadData();
  }

  Future<void> _loadFriendsCount() async {
    final res = await ref.read(apiClientProvider).get('/auth/friends');
    if (!mounted) return;
    if (res.success && res.data != null) {
      setState(
        () => _friendsCount = ((res.data['friends'] as List?) ?? []).length,
      );
    }
  }

  Future<void> _loadForumSignal() async {
    final res = await ref.read(apiClientProvider).get('/auth/forums');
    if (!mounted) return;
    if (res.success && res.data != null) {
      final forums = (res.data['forums'] as List?) ?? [];
      setState(() {
        _hasFollowedForum = forums.any((f) {
          final m = f as Map;
          return m['is_following'] == 1 || m['is_following'] == true;
        });
      });
    }
  }

  Future<void> _markAllRead() async {
    ref.read(unreadCountProvider.notifier).state = 0;
    final notifs = ref.read(notificationsProvider);
    if (notifs.any((n) => !n.isRead)) {
      await ref.read(notificationsProvider.notifier).markAllRead();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pollTimer?.cancel();
    super.dispose();
  }

  List<AppNotification> _filteredPreview(List<AppNotification> all) {
    switch (_filter) {
      case _PreviewFilter.all:
        return all;
      case _PreviewFilter.comment:
        return all.where((n) => n.type == 'comment').toList();
      case _PreviewFilter.like:
        return all.where((n) => n.type == 'like').toList();
      case _PreviewFilter.save:
        return all.where((n) => n.type == 'tutorial_save').toList();
      case _PreviewFilter.follow:
        return all.where((n) => n.type == 'follow').toList();
      case _PreviewFilter.answer:
        return all.where((n) => n.type == 'answer_posted').toList();
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final notifications = ref.watch(notificationsProvider);
    final conversations = ref.watch(conversationsProvider);
    final unread = ref.watch(unreadCountProvider);
    final mentionUnread = ref.watch(mentionUnreadCountProvider);
    final dmUnread = conversations.fold<int>(0, (s, c) => s + c.unreadCount);
    // unreadCountProvider 的 total 是"通知+群组消息"未读之和（后端算好
    // 的），减掉通知自己的未读数就是群组消息那一部分——不用再单独拉一次
    // /auth/groups 自己求和，跟之前"消息页群组Tab未读红点"那次的结论
    // 一致：信服务端的 total，不在客户端重新算一遍容易跟服务端对不上
    final notifUnread = notifications.where((n) => !n.isRead).length;
    final groupUnread = (unread - notifUnread).clamp(0, unread);
    // 评论/点赞/关注/回答四个筛选chip各自严格按 type 精确匹配，互不重叠——
    // 只有"全部"才是真的"全部"，不该再额外排除 invite_answer/mention/
    // answer_posted 这几个类型（之前排除是想避免跟邀请回答汇总卡/
    // 提及入口重复展示，但"全部"筛选项的字面意思不该被打折扣，两者
    // 冲突时以"全部"的语义为准——2026-07-10 改回不过滤）
    final previewNotifs = _filteredPreview(notifications).take(4).toList();
    final previewConvs = conversations.take(3).toList();
    // 私信只属于"全部"，在评论/点赞/关注/回答这些通知筛选下不该出现
    final showDms = _filter == _PreviewFilter.all && previewConvs.isNotEmpty;

    return Scaffold(
      // 浅色统一成首页那种偏米白的 #FAFAF8（比全局 scaffold 的冷灰白
      // #F7F7FB 更舒服），深色维持主题背景
      backgroundColor: Theme.of(context).brightness == Brightness.dark
          ? Theme.of(context).scaffoldBackgroundColor
          : const Color(0xFFFAFAF8),
      body: SafeArea(
        child: ListView(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
              child: Row(
                children: [
                  Text(
                    l10n.messagesTitle,
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (unread > 0) ...[
                    const SizedBox(width: 6),
                    Container(
                      width: 6,
                      height: 6,
                      decoration: const BoxDecoration(
                        color: Colors.red,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ],
                  const Spacer(),
                  if (unread > 0)
                    GestureDetector(
                      onTap: _markAllRead,
                      child: Text(
                        l10n.markAllRead,
                        style: const TextStyle(fontSize: 14, color: _primary),
                      ),
                    ),
                  const SizedBox(width: 12),
                  GestureDetector(
                    onTap: () => _openThenRefresh('/messages/conversations'),
                    child: const Icon(Icons.search, size: 22),
                  ),
                  const SizedBox(width: 12),
                  GestureDetector(
                    onTap: _showAddMenu,
                    child: Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        // 深色下改成紫色实心 + 白色＋号（跟"全部"选中态一套
                        // 视觉），浅色维持淡紫底 + 紫号
                        color:
                            Theme.of(context).brightness == Brightness.dark
                            ? _primary
                            : const Color(0xFFEEF0FF),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(
                        Icons.add,
                        color: Theme.of(context).brightness == Brightness.dark
                            ? Colors.white
                            : _primary,
                        size: 20,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),

            // 通知类型过滤——只决定下面"最近通知"预览显示哪几条
            SizedBox(
              height: 32,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                children: [
                  _filterChip(l10n.notifFilterAll, _PreviewFilter.all),
                  _filterChip(l10n.notifFilterComments, _PreviewFilter.comment),
                  _filterChip(l10n.notifFilterLikes, _PreviewFilter.like),
                  _filterChip(l10n.notifFilterSaves, _PreviewFilter.save),
                  _filterChip(l10n.notifFilterFollows, _PreviewFilter.follow),
                  _filterChip(l10n.notifFilterAnswer, _PreviewFilter.answer),
                ],
              ),
            ),
            const SizedBox(height: 14),

            // 快捷入口——通知/私信数字都是真实未读数；好友是真实好友总数
            // （没有"在线"这个概念）；群组列表有真实的 unread_count，但这个
            // 快捷方块的副标题先不接聚合未读数，只是个静态入口提示。
            // 加了"论坛"之后是6个方块，固定宽度的 Row 会挤得每块都装不下
            // 文字，改成横向可滚动，每块保持原来 Expanded 时差不多的宽度
            SizedBox(
              // 图标48 + 间距6 + 标题(~18) + 间距2 + 副标题(~14) ≈ 88，
              // 原来的 76 装不下副标题会 BOTTOM OVERFLOW，留足高度
              height: 94,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                children: [
                  SizedBox(
                    width: 72,
                    child: _quickTile(
                      icon: Icons.notifications,
                      iconColor: Colors.red,
                      iconBg: const Color(0xFFFEE2E2),
                      label: l10n.tabNotifications,
                      subtitle: unread > 0
                          ? l10n.newNotificationsCountLabel(unread)
                          : l10n.noNotificationsYet,
                      onTap: () => _openThenRefresh('/messages/notifications'),
                    ),
                  ),
                  const SizedBox(width: 14),
                  SizedBox(
                    width: 72,
                    child: _quickTile(
                      icon: Icons.chat_bubble,
                      iconColor: _primary,
                      iconBg: const Color(0xFFEEF0FF),
                      label: l10n.tabDirectMessages,
                      subtitle: dmUnread > 0
                          ? l10n.unreadCountLabel(dmUnread)
                          : l10n.noDirectMessagesYet,
                      onTap: () => _openThenRefresh('/messages/conversations'),
                    ),
                  ),
                  const SizedBox(width: 14),
                  SizedBox(
                    width: 72,
                    child: _quickTile(
                      icon: Icons.alternate_email,
                      iconColor: const Color(0xFF8B5CF6),
                      iconBg: const Color(0xFFF3E8FF),
                      label: l10n.mentionsQuickLabel,
                      subtitle: mentionUnread > 0
                          ? l10n.unreadCountLabel(mentionUnread)
                          : l10n.noMentionsYet,
                      onTap: () => _openThenRefresh('/messages/mentions'),
                    ),
                  ),
                  const SizedBox(width: 14),
                  SizedBox(
                    width: 72,
                    child: _quickTile(
                      icon: Icons.people,
                      iconColor: const Color(0xFF16A34A),
                      iconBg: const Color(0xFFE8F8F0),
                      label: l10n.friendsQuickLabel,
                      subtitle: _friendsCount == null
                          ? '···'
                          : l10n.friendsCountLabel(_friendsCount!),
                      onTap: () => context.push('/friends'),
                    ),
                  ),
                  const SizedBox(width: 14),
                  SizedBox(
                    width: 72,
                    child: _quickTile(
                      icon: Icons.groups,
                      iconColor: const Color(0xFFD97706),
                      iconBg: const Color(0xFFFFF7E6),
                      label: l10n.tabGroups,
                      subtitle: groupUnread > 0
                          ? '你有 $groupUnread 条未读消息'
                          : '去搜索发现更多群组 →',
                      subtitleColor: groupUnread > 0 ? _primary : null,
                      onTap: () => _openThenRefresh('/messages/groups'),
                    ),
                  ),
                  const SizedBox(width: 14),
                  SizedBox(
                    width: 72,
                    child: _quickTile(
                      icon: Icons.forum,
                      iconColor: const Color(0xFF0891B2),
                      iconBg: const Color(0xFFE0F2FE),
                      label: '论坛',
                      subtitle: _hasFollowedForum
                          ? '点击进入论坛查看最新内容'
                          : '去搜索发现更多论坛 →',
                      subtitleColor: _hasFollowedForum ? _primary : null,
                      onTap: () => context.push('/messages/forums'),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            // 邀请回答的汇总卡放在消息首页最显眼的位置，不再只藏在"最近
            // 通知"整页里靠 count>0 才出现——这是找不到入口反馈最多的
            // 地方，常驻在这里保证一进消息 Tab 就能看到。但"邀请回答"跟
            // 评论/点赞/关注这几个筛选没有语义关系（它既不是评论也不是
            // 点赞），只在"全部"和"回答"下显示，切到评论/点赞/关注时收起
            if (_filter == _PreviewFilter.all ||
                _filter == _PreviewFilter.answer) ...[
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: InviteSummaryCard(
                  count: _invites.length,
                  invites: _invites,
                  onTap: () => _openThenRefresh('/invite-list'),
                ),
              ),
              const SizedBox(height: 16),
            ],

            if (previewNotifs.isNotEmpty) ...[
              _SectionHeader(
                title: l10n.recentNotificationsTitle,
                actionLabel: l10n.viewAllAction,
                onAction: () => _openThenRefresh('/messages/notifications'),
              ),
              _PreviewCard(
                children: previewNotifs
                    .map(
                      (n) => _NotifPreviewTile(
                        notification: n,
                        onTap: () {
                          // 跟 notifications_screen.dart 的 _openNotification
                          // 同一个思路——之前这里只跳转，没有顺手标已读，退回来
                          // 红点/未读数一直卡着不消。本地先乐观标记，红点立刻
                          // 消失，真正的已读请求在后台异步发
                          if (!n.isRead) {
                            setState(() => n.isRead = true);
                            final current = ref.read(unreadCountProvider);
                            if (current > 0) {
                              ref.read(unreadCountProvider.notifier).state =
                                  current - 1;
                            }
                            unawaited(
                              ref
                                  .read(notificationsProvider.notifier)
                                  .markRead([n.id]),
                            );
                          }
                          // 评论/点赞/收藏/提及跳文章（评论/提及再定位到评论），
                          // 回答跳问题，关注才跳主页；其它类型兜底跳发信人主页
                          if (openNotificationTarget(context, n)) return;
                          if (n.fromUsername?.isNotEmpty ?? false) {
                            context.push('/users/${n.fromUsername}');
                          }
                        },
                      ),
                    )
                    .toList(),
              ),
              const SizedBox(height: 12),
            ],

            if (showDms) ...[
              _SectionHeader(
                title: l10n.tabDirectMessages,
                actionLabel: l10n.viewMoreAction,
                onAction: () => _openThenRefresh('/messages/conversations'),
              ),
              _PreviewCard(
                children: previewConvs
                    .map(
                      (c) => _ConvPreviewTile(
                        conversation: c,
                        onTap: () =>
                            _openThenRefresh('/messages/chat/${c.id}', extra: c),
                      ),
                    )
                    .toList(),
              ),
            ],

            if (previewNotifs.isEmpty && !showDms)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 60),
                child: Column(
                  children: [
                    const Icon(
                      Icons.mark_email_read_outlined,
                      size: 56,
                      color: Colors.grey,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      l10n.noNotificationsYet,
                      style: const TextStyle(color: Colors.grey, fontSize: 15),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _filterChip(String label, _PreviewFilter value) {
    final selected = _filter == value;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: GestureDetector(
        onTap: () => setState(() => _filter = value),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? _primary : Theme.of(context).cardColor,
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

  Widget _quickTile({
    required IconData icon,
    required Color iconColor,
    required Color iconBg,
    required String label,
    required String subtitle,
    required VoidCallback onTap,
    Color? subtitleColor,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(color: iconBg, shape: BoxShape.circle),
            child: Icon(icon, color: iconColor, size: 22),
          ),
          const SizedBox(height: 6),
          Text(
            label,
            // 之前没设 maxLines/overflow——英文长单词（"Notifications"）
            // 在72px窄格里会自动换成两行，把下面的副标题挤出固定高度的
            // SizedBox，就是截图里"BOTTOM OVERFLOWED"的根因。跟下面
            // subtitle同一套处理，单行截断不换行
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 2),
          Text(
            subtitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 10, color: subtitleColor ?? Colors.grey),
          ),
        ],
      ),
    );
  }

  void _showAddMenu() {
    final l10n = AppLocalizations.of(context)!;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: BoxDecoration(
          color: Theme.of(ctx).cardColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 20),
            _menuItem(
              Icons.person_add_outlined,
              l10n.addFriend,
              l10n.addFriendSubtitle,
              _primary,
              const Color(0xFFEEF0FF),
              () {
                Navigator.pop(ctx);
                _showAddFriendSearch();
              },
            ),
            const SizedBox(height: 12),
            _menuItem(
              Icons.group_add_outlined,
              l10n.createGroup,
              l10n.createGroupSubtitle,
              const Color(0xFF16A34A),
              const Color(0xFFE8F8F0),
              () {
                Navigator.pop(ctx);
                context.push('/groups/create');
              },
            ),
            const SizedBox(height: 12),
            _menuItem(
              Icons.forum_outlined,
              l10n.createForum,
              l10n.createForumSubtitle,
              const Color(0xFFD97706),
              const Color(0xFFFFF7E6),
              () {
                Navigator.pop(ctx);
                context.push('/forum/create-forum');
              },
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _menuItem(
    IconData icon,
    String title,
    String subtitle,
    Color color,
    Color bgColor,
    VoidCallback onTap,
  ) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Theme.of(context).inputDecorationTheme.fillColor,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: bgColor,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: color, size: 22),
            ),
            const SizedBox(width: 14),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  subtitle,
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ],
            ),
            const Spacer(),
            const Icon(Icons.chevron_right, color: Colors.grey, size: 20),
          ],
        ),
      ),
    );
  }

  void _showAddFriendSearch() {
    final l10n = AppLocalizations.of(context)!;
    final ctrl = TextEditingController();
    List<UserProfile> results = [];
    bool searching = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) {
          Future<void> doSearch(String query) async {
            final q = query.trim().replaceAll('@', '');
            if (q.isEmpty) {
              setSheet(() => results = []);
              return;
            }
            setSheet(() => searching = true);
            final res = await ref
                .read(apiClientProvider)
                .get('/auth/users/search', queryParameters: {'handle': q});
            final list = res.success && res.data != null
                ? ((res.data['users'] as List?) ?? [])
                      .map(
                        (j) => UserProfile.fromJson(j as Map<String, dynamic>),
                      )
                      .toList()
                : <UserProfile>[];
            setSheet(() {
              results = list;
              searching = false;
            });
          }

          return Container(
            height: MediaQuery.of(ctx).size.height * 0.85,
            decoration: BoxDecoration(
              color: Theme.of(ctx).cardColor,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(24),
              ),
            ),
            padding: EdgeInsets.fromLTRB(
              20,
              20,
              20,
              MediaQuery.of(ctx).viewInsets.bottom + 20,
            ),
            child: Column(
              children: [
                Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  l10n.addFriend,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: ctrl,
                  autofocus: true,
                  decoration: InputDecoration(
                    hintText: l10n.searchUserHandleHint,
                    prefixIcon: const Icon(Icons.search),
                    filled: true,
                    fillColor: Colors.grey[100],
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                    suffixIcon: TextButton(
                      onPressed: () => doSearch(ctrl.text),
                      child: Text(l10n.search),
                    ),
                  ),
                  onChanged: (v) {
                    if (v.trim().replaceAll('@', '').length < 2) {
                      setSheet(() => results = []);
                      return;
                    }
                    doSearch(v);
                  },
                  onSubmitted: doSearch,
                ),
                const SizedBox(height: 12),
                Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEEF0FF),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.info_outline, color: _primary, size: 16),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          l10n.mutualFollowBecomeFriendsHint,
                          style: const TextStyle(
                            fontSize: 12,
                            color: Color(0xFF4F46E5),
                            height: 1.4,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                if (searching)
                  const CircularProgressIndicator()
                else
                  Expanded(
                    child: results.isEmpty
                        ? Center(
                            child: Text(
                              l10n.searchUserPlaceholder,
                              style: const TextStyle(color: Colors.grey),
                            ),
                          )
                        : ListView.builder(
                            itemCount: results.length,
                            itemBuilder: (ctx, i) {
                              final u = results[i];
                              return ListTile(
                                leading: buildMessageAvatar(
                                  u.avatar,
                                  u.username,
                                ),
                                title: Text(
                                  u.username,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                subtitle: u.handle != null
                                    ? Text(
                                        '@${u.handle}',
                                        style: const TextStyle(
                                          color: Colors.grey,
                                        ),
                                      )
                                    : null,
                                trailing: ElevatedButton(
                                  onPressed: () {
                                    Navigator.pop(ctx);
                                    context.push(
                                      '/users/${u.handle ?? u.username}',
                                    );
                                  },
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: _primary,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                    ),
                                  ),
                                  child: Text(
                                    l10n.view,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 13,
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final String actionLabel;
  final VoidCallback onAction;
  const _SectionHeader({
    required this.title,
    required this.actionLabel,
    required this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Row(
        children: [
          Text(
            title,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
          ),
          const Spacer(),
          GestureDetector(
            onTap: onAction,
            child: Text(
              '$actionLabel >',
              style: const TextStyle(fontSize: 12, color: _primary),
            ),
          ),
        ],
      ),
    );
  }
}

// "最近通知"/"私信"预览区之前是贴边到底的表格式列表（跟设置页改之前
// 那个"白色块贴灰色背景"是同一类问题）——现在改成跟设置页 _SettingsGroup
// 一样的浮动圆角卡片：左右留白+细阴影，组内用分割线区分，不再贴边
class _PreviewCard extends StatelessWidget {
  final List<Widget> children;
  const _PreviewCard({required this.children});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final rows = <Widget>[];
    for (var i = 0; i < children.length; i++) {
      if (i > 0) {
        rows.add(
          Divider(
            height: 0.5,
            indent: 68,
            color: Theme.of(context).dividerColor,
          ),
        );
      }
      rows.add(children[i]);
    }
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(20),
        boxShadow: isDark
            ? null
            : [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.03),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Material(
        color: Colors.transparent,
        child: Column(children: rows),
      ),
    );
  }
}

class _NotifPreviewTile extends StatelessWidget {
  final AppNotification notification;
  final VoidCallback? onTap;
  const _NotifPreviewTile({required this.notification, this.onTap});

  Color _typeColor(String type) {
    switch (type) {
      case 'like':
        return Colors.red;
      case 'comment':
        return _primary;
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
    final n = notification;
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      onTap: onTap,
      leading: Stack(
        clipBehavior: Clip.none,
        children: [
          buildMessageAvatar(
            n.fromAvatar,
            n.fromUsername ?? l10n.systemNotificationInitial,
            radius: 20,
          ),
          Positioned(
            top: -2,
            right: -2,
            child: Container(
              width: 16,
              height: 16,
              decoration: BoxDecoration(
                color: _typeColor(n.type),
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 1.5),
              ),
              child: Icon(_typeIcon(n.type), size: 9, color: Colors.white),
            ),
          ),
        ],
      ),
      title: Text(
        n.content ?? n.title ?? '',
        style: const TextStyle(fontSize: 13),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        messageTimeAgo(l10n, n.createdAt),
        style: const TextStyle(fontSize: 11, color: Colors.grey),
      ),
      trailing: n.isRead
          ? null
          : Container(
              width: 7,
              height: 7,
              decoration: const BoxDecoration(
                color: _primary,
                shape: BoxShape.circle,
              ),
            ),
    );
  }
}

class _ConvPreviewTile extends StatelessWidget {
  final Conversation conversation;
  final VoidCallback onTap;
  const _ConvPreviewTile({required this.conversation, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final conv = conversation;
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      onTap: onTap,
      leading: buildMessageAvatar(conv.otherAvatar, conv.otherUsername),
      title: Text(
        conv.otherUsername,
        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
      ),
      subtitle: Text(
        conv.lastMessage ?? '',
        style: const TextStyle(fontSize: 12, color: Colors.grey),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            conv.lastMessageAt == null
                ? ''
                : messageTimeAgo(l10n, conv.lastMessageAt!),
            style: const TextStyle(fontSize: 11, color: Colors.grey),
          ),
          if (conv.unreadCount > 0) ...[
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: BoxDecoration(
                color: Colors.red,
                borderRadius: BorderRadius.circular(99),
              ),
              child: Text(
                '${conv.unreadCount}',
                style: const TextStyle(
                  fontSize: 10,
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
