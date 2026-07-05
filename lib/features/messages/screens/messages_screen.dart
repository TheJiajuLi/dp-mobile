import 'dart:async';
import 'dart:convert';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_client.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../profile/models/user_profile_model.dart';
import '../models/conversation_model.dart';
import '../models/notification_model.dart';
import '../providers/messages_provider.dart';

const _primary = Color(0xFF6366F1);

String _initial(String? name) {
  if (name == null || name.isEmpty) return '?';
  return name.substring(0, 1).toUpperCase();
}

// 跟全项目其它头像渲染的地方保持一致：data:image 是旧的 base64 头像，
// 否则是 COS 图片 URL
Widget _buildAvatar(String? avatar, String username, {double radius = 24}) {
  if (avatar != null && avatar.isNotEmpty) {
    if (avatar.startsWith('data:image')) {
      try {
        return CircleAvatar(
          radius: radius,
          backgroundImage: MemoryImage(base64Decode(avatar.split(',').last)),
        );
      } catch (_) {
        // 解码失败落到下面的首字母占位
      }
    } else {
      return CircleAvatar(
        radius: radius,
        backgroundImage: CachedNetworkImageProvider(avatar),
      );
    }
  }
  return CircleAvatar(
    radius: radius,
    backgroundColor: _primary,
    child: Text(
      _initial(username),
      style: TextStyle(
        color: Colors.white,
        fontWeight: FontWeight.w700,
        fontSize: radius * 0.67,
      ),
    ),
  );
}

// 相对时间格式化——通知/私信tab共用
String timeAgo(AppLocalizations l10n, int tsMs) {
  final diff = DateTime.now().difference(DateTime.fromMillisecondsSinceEpoch(tsMs));
  if (diff.inMinutes < 1) return l10n.timeJustNow;
  if (diff.inMinutes < 60) return l10n.timeMinutesAgo(diff.inMinutes);
  if (diff.inHours < 24) return l10n.timeHoursAgo(diff.inHours);
  if (diff.inDays < 30) return l10n.timeDaysAgo(diff.inDays);
  return l10n.timeMonthsAgo(diff.inDays ~/ 30);
}

class MessagesScreen extends ConsumerStatefulWidget {
  const MessagesScreen({super.key});
  @override
  ConsumerState<MessagesScreen> createState() => _MessagesScreenState();
}

class _MessagesScreenState extends ConsumerState<MessagesScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabCtrl;
  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 3, vsync: this);
    // 微信式已读：切到通知 tab（index=0）就立即标记已读，不等轮询
    _tabCtrl.addListener(() {
      if (_tabCtrl.index == 0 && !_tabCtrl.indexIsChanging) {
        _markAllRead();
      }
    });
    // TabController 默认 initialIndex 就是 0，进这个页面本来就停在通知
    // tab 是最常见的场景，也要在这里标记已读——但必须等 _loadData() 里的
    // notificationsProvider.fetch() 先把通知列表拉回来，_markAllRead()
    // 才能正确判断"有没有未读"从而决定要不要调标记已读接口。如果不等，
    // 这里读到的还是空列表，既不会调 API（服务端那边其实还是未读），
    // 又会把 unreadCountProvider 先清零、马上又被 _loadData() 拉到的
    // 真实未读数覆盖回去，变成"红点一闪又出现"
    _loadData().then((_) {
      if (mounted && _tabCtrl.index == 0) _markAllRead();
    });
    // 每 30 秒轮询一次
    _pollTimer = Timer.periodic(const Duration(seconds: 30), (_) => _loadData());
  }

  Future<void> _loadData() async {
    await ref.read(notificationsProvider.notifier).fetch();
    await ref.read(conversationsProvider.notifier).fetch();
    final res = await ref.read(apiClientProvider).get('/auth/notifications/unread-count');
    if (res.success && res.data != null && mounted) {
      ref.read(unreadCountProvider.notifier).state =
          (res.data['unread'] as num?)?.toInt() ?? 0;
    }
  }

  // 本地立即清零，不等 API/下一次轮询——有未读才真的调一次标记已读接口
  Future<void> _markAllRead() async {
    ref.read(unreadCountProvider.notifier).state = 0;
    final notifs = ref.read(notificationsProvider);
    if (notifs.any((n) => !n.isRead)) {
      await ref.read(notificationsProvider.notifier).markAllRead();
    }
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    _pollTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final notifications = ref.watch(notificationsProvider);
    final conversations = ref.watch(conversationsProvider);
    final unread = ref.watch(unreadCountProvider);

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(
        child: Column(
          children: [
            // 顶部栏
            Container(
              color: Theme.of(context).cardColor,
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
              child: Column(
                children: [
                  Row(
                    children: [
                      Text(l10n.messagesTitle,
                          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
                      const Spacer(),
                      if (unread > 0)
                        GestureDetector(
                          onTap: _markAllRead,
                          child: Text(l10n.markAllRead,
                              style: const TextStyle(fontSize: 14, color: _primary)),
                        ),
                      const SizedBox(width: 12),
                      const Icon(Icons.search, size: 22),
                      const SizedBox(width: 12),
                      GestureDetector(
                        onTap: _showAddMenu,
                        child: Container(
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                              color: const Color(0xFFEEF0FF), borderRadius: BorderRadius.circular(8)),
                          child: const Icon(Icons.add, color: _primary, size: 20),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TabBar(
                    controller: _tabCtrl,
                    labelColor: _primary,
                    unselectedLabelColor: Colors.grey,
                    labelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
                    unselectedLabelStyle:
                        const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                    indicatorColor: _primary,
                    indicatorWeight: 2,
                    tabs: [
                      Tab(child: _tabLabel(l10n.tabNotifications, unread)),
                      Tab(
                          child: _tabLabel(l10n.tabDirectMessages,
                              conversations.fold<int>(0, (s, c) => s + c.unreadCount))),
                      Tab(text: l10n.tabGroups),
                    ],
                  ),
                ],
              ),
            ),

            // 内容
            Expanded(
              child: TabBarView(
                controller: _tabCtrl,
                children: [
                  _NotifTab(notifications: notifications),
                  _DmTab(conversations: conversations),
                  const _GroupTab(),
                ],
              ),
            ),
          ],
        ),
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
              decoration:
                  BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(2)),
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
                ScaffoldMessenger.of(context)
                    .showSnackBar(SnackBar(content: Text(l10n.createGroupComingSoon)));
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
                ScaffoldMessenger.of(context)
                    .showSnackBar(SnackBar(content: Text(l10n.createForumComingSoon)));
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
              decoration: BoxDecoration(color: bgColor, borderRadius: BorderRadius.circular(12)),
              child: Icon(icon, color: color, size: 22),
            ),
            const SizedBox(width: 14),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                Text(subtitle, style: const TextStyle(fontSize: 12, color: Colors.grey)),
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
          // 用户习惯性会把 @ 也打进去（毕竟提示文案和别处显示都带 @），
          // 但后端 handle 字段本身不含 @，原样传过去只会一直查不到人
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
                    .map((j) => UserProfile.fromJson(j as Map<String, dynamic>))
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
              borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            ),
            padding: EdgeInsets.fromLTRB(20, 20, 20, MediaQuery.of(ctx).viewInsets.bottom + 20),
            child: Column(
              children: [
                Container(
                  width: 36,
                  height: 4,
                  decoration:
                      BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(2)),
                ),
                const SizedBox(height: 16),
                Text(l10n.addFriend, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
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
                        borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                    suffixIcon: TextButton(
                      onPressed: () => doSearch(ctrl.text),
                      child: Text(l10n.search),
                    ),
                  ),
                  // 边输边搜——不用等用户点搜索按钮或按回车。少于2个字符先不发
                  // 请求，避免每敲一个字母就打一次接口
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
                            child: Text(l10n.searchUserPlaceholder, style: const TextStyle(color: Colors.grey)))
                        : ListView.builder(
                            itemCount: results.length,
                            itemBuilder: (ctx, i) {
                              final u = results[i];
                              return ListTile(
                                leading: _buildAvatar(u.avatar, u.username),
                                title:
                                    Text(u.username, style: const TextStyle(fontWeight: FontWeight.w600)),
                                subtitle: u.handle != null
                                    ? Text('@${u.handle}', style: const TextStyle(color: Colors.grey))
                                    : null,
                                trailing: ElevatedButton(
                                  onPressed: () {
                                    Navigator.pop(ctx);
                                    // handle 更精准（唯一且不会变），username 只是兜底——
                                    // 两者路由都认，但优先用 handle 避免同名撞车
                                    context.push('/users/${u.handle ?? u.username}');
                                  },
                                  style: ElevatedButton.styleFrom(
                                      backgroundColor: _primary,
                                      shape:
                                          RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                      padding: const EdgeInsets.symmetric(horizontal: 12)),
                                  child: Text(l10n.view,
                                      style: const TextStyle(color: Colors.white, fontSize: 13)),
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

  Widget _tabLabel(String text, int count) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // 英文文案（"Direct Messages"之类）比中文长很多，不换成 Flexible+
        // ellipsis 的话，非可滚动 TabBar 三等分宽度下会直接溢出
        Flexible(
          child: Text(text, overflow: TextOverflow.ellipsis, maxLines: 1),
        ),
        if (count > 0) ...[
          const SizedBox(width: 4),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
            decoration: BoxDecoration(color: Colors.red, borderRadius: BorderRadius.circular(99)),
            child: Text('$count',
                style: const TextStyle(
                    fontSize: 10, color: Colors.white, fontWeight: FontWeight.w700)),
          ),
        ],
      ],
    );
  }
}

// 通知 tab
class _NotifTab extends StatelessWidget {
  final List<AppNotification> notifications;
  const _NotifTab({required this.notifications});

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
    if (notifications.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.notifications_none, size: 56, color: Colors.grey),
            const SizedBox(height: 12),
            Text(l10n.noNotificationsYet, style: const TextStyle(color: Colors.grey, fontSize: 15)),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: notifications.length,
      itemBuilder: (ctx, i) {
        final n = notifications[i];
        return Container(
          color: n.isRead ? Colors.transparent : _primary.withValues(alpha: 0.04),
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            leading: GestureDetector(
              onTap: (n.fromUsername?.isNotEmpty ?? false)
                  ? () => context.push('/users/${n.fromUsername}')
                  : null,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  _buildAvatar(n.fromAvatar, n.fromUsername ?? l10n.systemNotificationInitial, radius: 22),
                  Positioned(
                    bottom: -2,
                    right: -2,
                    child: Container(
                      width: 18,
                      height: 18,
                      decoration: BoxDecoration(
                          color: _typeColor(n.type),
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 1.5)),
                      child: Icon(_typeIcon(n.type), size: 10, color: Colors.white),
                    ),
                  ),
                ],
              ),
            ),
            title: Text(
              n.content ?? n.title ?? '',
              style: TextStyle(
                  fontSize: 14, fontWeight: n.isRead ? FontWeight.w400 : FontWeight.w500),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle:
                Text(timeAgo(l10n, n.createdAt), style: const TextStyle(fontSize: 12, color: Colors.grey)),
            trailing: n.tutorialId != null
                ? Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                        color: _primary.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8)),
                    child: const Icon(Icons.article_outlined, color: _primary, size: 20),
                  )
                : n.isRead
                    ? null
                    : Container(
                        width: 8,
                        height: 8,
                        decoration: const BoxDecoration(color: _primary, shape: BoxShape.circle)),
          ),
        );
      },
    );
  }
}

// 私信 tab
class _DmTab extends ConsumerWidget {
  final List<Conversation> conversations;
  const _DmTab({required this.conversations});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    if (conversations.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.chat_bubble_outline, size: 56, color: Colors.grey),
            const SizedBox(height: 12),
            Text(l10n.noDirectMessagesYet, style: const TextStyle(color: Colors.grey, fontSize: 15)),
            const SizedBox(height: 8),
            GestureDetector(
              onTap: () => context.go('/community'),
              child: Text(l10n.goMeetNewFriends, style: const TextStyle(color: _primary, fontSize: 14)),
            ),
          ],
        ),
      );
    }

    return ListView.separated(
      itemCount: conversations.length,
      separatorBuilder: (_, __) => const Divider(height: 0.5, indent: 76),
      itemBuilder: (ctx, i) {
        final conv = conversations[i];
        return ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          onTap: () => context.push('/messages/chat/${conv.id}', extra: conv),
          leading: _buildAvatar(conv.otherAvatar, conv.otherUsername),
          title: Row(
            children: [
              Text(conv.otherUsername,
                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
              const Spacer(),
              Text(
                  conv.lastMessageAt == null
                      ? ''
                      : timeAgo(l10n, conv.lastMessageAt!),
                  style: const TextStyle(fontSize: 12, color: Colors.grey)),
            ],
          ),
          subtitle: Row(
            children: [
              Expanded(
                child: Text(conv.lastMessage ?? '',
                    style: const TextStyle(fontSize: 13, color: Colors.grey),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
              ),
              if (conv.unreadCount > 0)
                Container(
                  margin: const EdgeInsets.only(left: 8),
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration:
                      BoxDecoration(color: Colors.red, borderRadius: BorderRadius.circular(99)),
                  child: Text('${conv.unreadCount}',
                      style: const TextStyle(
                          fontSize: 11, color: Colors.white, fontWeight: FontWeight.w700)),
                ),
            ],
          ),
        );
      },
    );
  }
}

// 群组 tab（占位——讨论群/技术交流论坛下个版本上线）
class _GroupTab extends StatelessWidget {
  const _GroupTab();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 80,
            height: 80,
            decoration:
                BoxDecoration(color: const Color(0xFFEEF0FF), borderRadius: BorderRadius.circular(20)),
            child: const Icon(Icons.group, size: 40, color: _primary),
          ),
          const SizedBox(height: 16),
          Text(l10n.groupFeature, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Text(l10n.comingSoonStayTuned, style: const TextStyle(color: Colors.grey, fontSize: 14)),
        ],
      ),
    );
  }
}
