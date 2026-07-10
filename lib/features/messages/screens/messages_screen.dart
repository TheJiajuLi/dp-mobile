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
import '../widgets/invite_summary_card.dart';

const _primary = kMessagesPrimary;

// 通知过滤跟 notifications_screen.dart 用的是同一套口径（评论/点赞/关注
// 真实存在，AI 后端没有对应类型）——只用来决定"最近通知"预览区显示哪几
// 条，不是一个独立页面，选中态不需要跨页面保留。@提及以前也在这个筛选
// 器里、点了显示"即将上线"，现在已经有独立的"提及"入口+专属页面了，
// 这里的筛选项就撤掉，不然点进去还会显示过时的"即将上线"提示
enum _PreviewFilter { all, comment, like, follow, ai }

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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadData();
    _loadFriendsCount();
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

  Future<void> _loadFriendsCount() async {
    final res = await ref.read(apiClientProvider).get('/auth/friends');
    if (!mounted) return;
    if (res.success && res.data != null) {
      setState(
        () => _friendsCount = ((res.data['friends'] as List?) ?? []).length,
      );
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
      case _PreviewFilter.follow:
        return all.where((n) => n.type == 'follow').toList();
      case _PreviewFilter.ai:
        return const [];
    }
  }

  bool get _isComingSoonFilter => _filter == _PreviewFilter.ai;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final notifications = ref.watch(notificationsProvider);
    final conversations = ref.watch(conversationsProvider);
    final unread = ref.watch(unreadCountProvider);
    final mentionUnread = ref.watch(mentionUnreadCountProvider);
    final dmUnread = conversations.fold<int>(0, (s, c) => s + c.unreadCount);
    final previewNotifs = _isComingSoonFilter
        ? const <AppNotification>[]
        // 评论/点赞/关注三个筛选chip各自严格按 type 精确匹配，互不重叠——
        // 只有"全部"才是真的"全部"，不该再额外排除 invite_answer/mention/
        // answer_posted 这几个类型（之前排除是想避免跟邀请回答汇总卡/
        // 提及入口重复展示，但"全部"筛选项的字面意思不该被打折扣，两者
        // 冲突时以"全部"的语义为准——2026-07-10 改回不过滤）
        : _filteredPreview(notifications).take(4).toList();
    final previewConvs = conversations.take(3).toList();
    // 私信只属于"全部"，在评论/点赞/关注/AI 这些通知筛选下不该出现
    final showDms = _filter == _PreviewFilter.all && previewConvs.isNotEmpty;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
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
                    onTap: () => context.push('/messages/conversations'),
                    child: const Icon(Icons.search, size: 22),
                  ),
                  const SizedBox(width: 12),
                  GestureDetector(
                    onTap: _showAddMenu,
                    child: Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: const Color(0xFFEEF0FF),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(Icons.add, color: _primary, size: 20),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),

            // 通知类型过滤——只决定下面"最近通知"预览显示哪几条，
            // @提及/AI 后端没有对应类型，选中后走"即将上线"提示
            SizedBox(
              height: 32,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                children: [
                  _filterChip(l10n.notifFilterAll, _PreviewFilter.all),
                  _filterChip(l10n.notifFilterComments, _PreviewFilter.comment),
                  _filterChip(l10n.notifFilterLikes, _PreviewFilter.like),
                  _filterChip(l10n.notifFilterFollows, _PreviewFilter.follow),
                  _filterChip(l10n.notifFilterAi, _PreviewFilter.ai),
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
                      onTap: () => context.push('/messages/notifications'),
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
                      onTap: () => context.push('/messages/conversations'),
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
                      onTap: () => context.push('/messages/mentions'),
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
                      subtitle: '查看已加入的群组',
                      onTap: () => context.push('/messages/groups'),
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
                      subtitle: '发现感兴趣的论坛',
                      onTap: () => context.push('/messages/forums'),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            // 邀请回答的汇总卡放在消息首页最显眼的位置，不再只藏在"最近
            // 通知"整页里靠 count>0 才出现——这是找不到入口反馈最多的
            // 地方，常驻在这里保证一进消息 Tab 就能看到
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: InviteSummaryCard(
                count: _invites.length,
                invites: _invites,
                onTap: () => context.push('/invite-list'),
              ),
            ),
            const SizedBox(height: 16),

            if (_isComingSoonFilter)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: _ComingSoonInline(
                  message: l10n.notifFilterComingSoonMessage,
                ),
              )
            else if (previewNotifs.isNotEmpty) ...[
              _SectionHeader(
                title: l10n.recentNotificationsTitle,
                actionLabel: l10n.viewAllAction,
                onAction: () => context.push('/messages/notifications'),
              ),
              _PreviewCard(
                children: previewNotifs
                    .map(
                      (n) => _NotifPreviewTile(
                        notification: n,
                        onTap: (n.fromUsername?.isNotEmpty ?? false)
                            ? () => context.push('/users/${n.fromUsername}')
                            : null,
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
                onAction: () => context.push('/messages/conversations'),
              ),
              _PreviewCard(
                children: previewConvs
                    .map(
                      (c) => _ConvPreviewTile(
                        conversation: c,
                        onTap: () =>
                            context.push('/messages/chat/${c.id}', extra: c),
                      ),
                    )
                    .toList(),
              ),
            ],

            if (previewNotifs.isEmpty && !showDms && !_isComingSoonFilter)
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
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 2),
          Text(
            subtitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 10, color: Colors.grey),
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
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(l10n.createForumComingSoon)),
                );
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

class _ComingSoonInline extends StatelessWidget {
  final String message;
  const _ComingSoonInline({required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _primary.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          const Icon(Icons.hourglass_top_outlined, color: _primary, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(fontSize: 13, color: _primary),
            ),
          ),
        ],
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
