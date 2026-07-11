import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_client.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../../shared/widgets/rounded_list_card.dart';
import '../../auth/auth_service.dart';
import '../../profile/models/user_profile_model.dart';
import '../models/conversation_model.dart';
import '../utils/message_avatar.dart';

enum _FriendTab { friends, following, followers, recommended }

// 好友：互相关注的用户（GET /auth/friends，跟 chat_screen.dart 判断陌生人
// 限制用的是同一份口径）。关注/粉丝两个 tab 复用 profile 那边已经在用的
// /auth/users/:id/followers|following。"推荐"这个 tab 后端完全没有实现
// （没有推荐算法/接口），保留在参考图里的视觉位置，选中直接给"即将上线"。
//
// 参考图里的"新的好友请求 3（接受/忽略）"改造成了"关注了你、你还没回关"——
// 这个项目的好友关系是互相关注自动成立的，没有"发送/接受好友请求"这套
// 流程，真正能做的等价物是筛出"关注了我但我还没回关"的人，配一个真实的
// 回关按钮（POST /auth/users/:id/follow）
class FriendListScreen extends ConsumerStatefulWidget {
  const FriendListScreen({super.key});
  @override
  ConsumerState<FriendListScreen> createState() => _FriendListScreenState();
}

class _FriendListScreenState extends ConsumerState<FriendListScreen> {
  _FriendTab _tab = _FriendTab.friends;
  bool _loading = true;
  List<Map<String, dynamic>> _friends = [];
  List<UserProfile> _following = [];
  List<UserProfile> _followers = [];
  final Set<String> _dismissedUnrequited = {};
  final Set<String> _openingChatWith = {};
  final Set<String> _busyUserIds = {};
  final _searchCtrl = TextEditingController();
  String _query = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final me = ref.read(currentUserProvider);
    final myId = me?.id ?? '';
    final api = ref.read(apiClientProvider);
    final results = await Future.wait([
      api.get('/auth/friends'),
      if (myId.isNotEmpty) api.get('/auth/users/$myId/following'),
      if (myId.isNotEmpty) api.get('/auth/users/$myId/followers'),
    ]);
    if (!mounted) return;
    final friendsRes = results[0];
    setState(() {
      _friends = friendsRes.success && friendsRes.data != null
          ? List<Map<String, dynamic>>.from(
              (friendsRes.data['friends'] as List?) ?? [],
            )
          : [];
      if (myId.isNotEmpty && results.length > 2) {
        final followingRes = results[1];
        final followersRes = results[2];
        _following = followingRes.success && followingRes.data != null
            ? ((followingRes.data['following'] as List?) ?? [])
                  .map((j) => UserProfile.fromJson(j as Map<String, dynamic>))
                  .toList()
            : [];
        _followers = followersRes.success && followersRes.data != null
            ? ((followersRes.data['followers'] as List?) ?? [])
                  .map((j) => UserProfile.fromJson(j as Map<String, dynamic>))
                  .toList()
            : [];
      }
      _loading = false;
    });
  }

  List<UserProfile> get _unrequited {
    final followingIds = _following.map((u) => u.id).toSet();
    return _followers
        .where(
          (f) =>
              !followingIds.contains(f.id) &&
              !_dismissedUnrequited.contains(f.id),
        )
        .toList();
  }

  Future<void> _followBack(UserProfile user) async {
    if (_busyUserIds.contains(user.id)) return;
    setState(() => _busyUserIds.add(user.id));
    final res = await ref
        .read(apiClientProvider)
        .post('/auth/users/${user.id}/follow');
    if (!mounted) return;
    setState(() {
      _busyUserIds.remove(user.id);
      if (res.success) _following = [..._following, user];
    });
  }

  Future<void> _unfollow(UserProfile user) async {
    final l10n = AppLocalizations.of(context)!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        content: Text(l10n.unfollowConfirmMessage(user.username)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l10n.searchCancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              l10n.unfollowAction,
              style: const TextStyle(color: Colors.red),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true || _busyUserIds.contains(user.id)) return;
    setState(() => _busyUserIds.add(user.id));
    final res = await ref
        .read(apiClientProvider)
        .delete('/auth/users/${user.id}/follow');
    if (!mounted) return;
    setState(() {
      _busyUserIds.remove(user.id);
      if (res.success) {
        _following = _following.where((u) => u.id != user.id).toList();
        _friends = _friends
            .where((f) => f['id']?.toString() != user.id)
            .toList();
      }
    });
  }

  Future<void> _openChat(Map<String, dynamic> f) async {
    final friendId = f['id']?.toString() ?? '';
    if (friendId.isEmpty || _openingChatWith.contains(friendId)) return;
    setState(() => _openingChatWith.add(friendId));

    try {
      final api = ref.read(apiClientProvider);
      final res = await api.get('/auth/conversations');
      if (res.success && res.data != null) {
        final convs = (res.data['conversations'] as List?) ?? [];
        final existing = convs.cast<Map<String, dynamic>?>().firstWhere(
          (c) => c?['other_user_id']?.toString() == friendId,
          orElse: () => null,
        );
        if (existing != null) {
          if (!mounted) return;
          context.push(
            '/messages/chat/${existing['id']}',
            extra: Conversation.fromJson(existing),
          );
          return;
        }
      }

      if (!mounted) return;
      final msgRes = await api.post(
        '/auth/messages',
        data: {'toUserId': friendId, 'content': '你好！', 'type': 'text'},
      );
      if (!msgRes.success || msgRes.data == null) {
        if (!mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('打开聊天失败：${msgRes.message}')));
        return;
      }
      if (!mounted) return;
      context.push(
        '/messages/chat/${msgRes.data['conversationId']}',
        extra: Conversation(
          id: msgRes.data['conversationId'].toString(),
          otherUserId: friendId,
          otherUsername: f['username']?.toString() ?? '',
          otherAvatar: f['avatar']?.toString(),
          unreadCount: 0,
        ),
      );
    } finally {
      if (mounted) setState(() => _openingChatWith.remove(friendId));
    }
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
                const SizedBox(height: 16),
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
                                    ? Text('@${u.handle}')
                                    : null,
                                trailing: ElevatedButton(
                                  onPressed: () {
                                    Navigator.pop(ctx);
                                    context.push(
                                      '/users/${u.handle ?? u.username}',
                                    );
                                  },
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: kMessagesPrimary,
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

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final isDark = Theme.of(context).brightness == Brightness.dark;
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
                  Expanded(
                    child: Text(
                      l10n.friendsQuickLabel,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  GestureDetector(
                    onTap: _showAddFriendSearch,
                    child: const Icon(Icons.person_add_alt_outlined, size: 22),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
              // filled:true 没配 fillColor，之前一直是吃全局主题的
              // fillColor（浅色 #F5F5F5），跟这个页面 Scaffold 自己的
              // scaffoldBackgroundColor（浅色 #F7F7FB）几乎是同一个灰度，
              // 浅色模式下框和背景快融在一起，看不清——换成跟
              // search_screen.dart/group_chat_screen.dart 搜索框同一套
              // 视觉语言：外层 Container 给一个明显更深的灰色胶囊底，
              // TextField 自己 filled:false 不再吃主题灰
              child: Container(
                height: 40,
                decoration: BoxDecoration(
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.08)
                      : const Color(0xFFE8E8ED),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: TextField(
                  controller: _searchCtrl,
                  onChanged: (v) => setState(() => _query = v),
                  decoration: InputDecoration(
                    hintText: l10n.searchUserPlaceholder,
                    hintStyle: TextStyle(
                      color: isDark
                          ? Colors.white.withValues(alpha: 0.35)
                          : Colors.grey[600],
                    ),
                    prefixIcon: Icon(
                      Icons.search,
                      size: 20,
                      color: isDark
                          ? Colors.white.withValues(alpha: 0.5)
                          : Colors.grey[600],
                    ),
                    filled: false,
                    isDense: true,
                    border: InputBorder.none,
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  _tabChip(l10n.friendsQuickLabel, _FriendTab.friends),
                  const SizedBox(width: 8),
                  _tabChip(l10n.followingCountLabel, _FriendTab.following),
                  const SizedBox(width: 8),
                  _tabChip(l10n.followersCountLabel, _FriendTab.followers),
                  const SizedBox(width: 8),
                  _tabChip(l10n.tabRecommended, _FriendTab.recommended),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _buildTabBody(l10n),
            ),
          ],
        ),
      ),
    );
  }

  Widget _tabChip(String label, _FriendTab value) {
    final selected = _tab == value;
    return GestureDetector(
      onTap: () => setState(() => _tab = value),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: selected
              ? kMessagesPrimary.withValues(alpha: 0.1)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: selected
                ? kMessagesPrimary
                : Theme.of(context).textTheme.bodyMedium?.color,
          ),
        ),
      ),
    );
  }

  Widget _buildTabBody(AppLocalizations l10n) {
    switch (_tab) {
      case _FriendTab.friends:
        return _buildFriendsTab(l10n);
      case _FriendTab.following:
        return _buildUserList(
          _filterUsers(_following),
          emptyTitle: l10n.noFollowingYet,
          trailingBuilder: (u) => _busyUserIds.contains(u.id)
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : OutlinedButton(
                  onPressed: () => _unfollow(u),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                  ),
                  child: Text(
                    l10n.unfollowAction,
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
        );
      case _FriendTab.followers:
        final followingIds = _following.map((u) => u.id).toSet();
        return _buildUserList(
          _filterUsers(_followers),
          emptyTitle: l10n.noFollowersYet,
          trailingBuilder: (u) => followingIds.contains(u.id)
              ? null
              : _busyUserIds.contains(u.id)
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : ElevatedButton(
                  onPressed: () => _followBack(u),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: kMessagesPrimary,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                  ),
                  child: Text(
                    l10n.followBackAction,
                    style: const TextStyle(fontSize: 12, color: Colors.white),
                  ),
                ),
        );
      case _FriendTab.recommended:
        return _ComingSoon(message: l10n.recommendedUsersComingSoon);
    }
  }

  List<UserProfile> _filterUsers(List<UserProfile> list) {
    if (_query.isEmpty) return list;
    return list
        .where((u) => u.username.toLowerCase().contains(_query.toLowerCase()))
        .toList();
  }

  Widget _buildUserList(
    List<UserProfile> users, {
    required String emptyTitle,
    Widget? Function(UserProfile)? trailingBuilder,
  }) {
    if (users.isEmpty) {
      return Center(
        child: Text(emptyTitle, style: const TextStyle(color: Colors.grey)),
      );
    }
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 8),
      children: [
        RoundedListCard(
          children: users
              .map(
                (u) => ListTile(
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 6,
                  ),
                  leading: buildMessageAvatar(u.avatar, u.username),
                  title: Text(
                    u.username,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  subtitle: u.handle != null
                      ? Text(
                          '@${u.handle}',
                          style: const TextStyle(fontSize: 12),
                        )
                      : null,
                  trailing: trailingBuilder?.call(u),
                  onTap: () => context.push('/users/${u.handle ?? u.username}'),
                ),
              )
              .toList(),
        ),
      ],
    );
  }

  Widget _buildFriendsTab(AppLocalizations l10n) {
    final friends = _query.isEmpty
        ? _friends
        : _friends
              .where(
                (f) => (f['username']?.toString() ?? '').toLowerCase().contains(
                  _query.toLowerCase(),
                ),
              )
              .toList();
    final unrequited = _unrequited;

    return ListView(
      children: [
        if (unrequited.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: Text(
              l10n.notYetFollowedBackTitle,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
            ),
          ),
          SizedBox(
            height: 118,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: unrequited.length,
              itemBuilder: (ctx, i) {
                final u = unrequited[i];
                final busy = _busyUserIds.contains(u.id);
                return Container(
                  width: 84,
                  margin: const EdgeInsets.only(right: 12),
                  child: Column(
                    children: [
                      buildMessageAvatar(u.avatar, u.username, radius: 26),
                      const SizedBox(height: 6),
                      Text(
                        u.username,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Expanded(
                            child: SizedBox(
                              height: 26,
                              child: busy
                                  ? const Center(
                                      child: SizedBox(
                                        width: 12,
                                        height: 12,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 1.5,
                                        ),
                                      ),
                                    )
                                  : ElevatedButton(
                                      onPressed: () => _followBack(u),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: kMessagesPrimary,
                                        padding: EdgeInsets.zero,
                                        minimumSize: Size.zero,
                                        tapTargetSize:
                                            MaterialTapTargetSize.shrinkWrap,
                                      ),
                                      child: Text(
                                        l10n.followBackAction,
                                        style: const TextStyle(
                                          fontSize: 11,
                                          color: Colors.white,
                                        ),
                                      ),
                                    ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      GestureDetector(
                        onTap: () =>
                            setState(() => _dismissedUnrequited.add(u.id)),
                        child: Text(
                          l10n.searchCancel,
                          style: const TextStyle(
                            fontSize: 11,
                            color: Colors.grey,
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
          const Divider(height: 24),
        ],
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Text(
            l10n.allFriendsCountLabel(friends.length),
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
          ),
        ),
        if (friends.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 40),
            child: Center(
              child: Column(
                children: [
                  const Icon(
                    Icons.people_outline,
                    size: 48,
                    color: Color(0xFFE5E5EA),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    l10n.noFriendsYetTitle,
                    style: const TextStyle(color: Colors.grey),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    l10n.noFriendsYetSubtitle,
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ],
              ),
            ),
          )
        else
          RoundedListCard(
            children: friends.map((f) {
              final username = f['username']?.toString() ?? '';
              final unread = (f['unread_count'] as num?)?.toInt() ?? 0;
              final userId = f['id']?.toString() ?? '';
              return ListTile(
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 6,
                ),
                leading: buildMessageAvatar(f['avatar']?.toString(), username),
                title: Text(
                  username,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                subtitle: f['last_message'] != null
                    ? Text(
                        f['last_message'].toString(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 12),
                      )
                    : const Text(
                        '发消息打招呼',
                        style: TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (unread > 0)
                      Container(
                        margin: const EdgeInsets.only(right: 8),
                        padding: const EdgeInsets.all(4),
                        decoration: const BoxDecoration(
                          color: kMessagesPrimary,
                          shape: BoxShape.circle,
                        ),
                        child: Text(
                          '$unread',
                          style: const TextStyle(
                            fontSize: 10,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    GestureDetector(
                      onTap: () => _openChat(f),
                      child: const Icon(
                        Icons.chat_bubble_outline,
                        size: 18,
                        color: Colors.grey,
                      ),
                    ),
                    const SizedBox(width: 8),
                    GestureDetector(
                      onTap: () => _showFriendMenu(f, username, userId),
                      child: const Icon(
                        Icons.more_horiz,
                        size: 18,
                        color: Colors.grey,
                      ),
                    ),
                  ],
                ),
                onTap: () => _openChat(f),
              );
            }).toList(),
          ),
      ],
    );
  }

  void _showFriendMenu(Map<String, dynamic> f, String username, String userId) {
    final l10n = AppLocalizations.of(context)!;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: BoxDecoration(
          color: Theme.of(ctx).cardColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(
                  Icons.person_off_outlined,
                  color: Colors.red,
                ),
                title: Text(
                  l10n.unfollowAction,
                  style: const TextStyle(color: Colors.red),
                ),
                onTap: () {
                  Navigator.pop(ctx);
                  if (userId.isEmpty) return;
                  _unfollow(
                    UserProfile(
                      id: userId,
                      username: username,
                      followerCount: 0,
                      followingCount: 0,
                      tutorialCount: 0,
                      createdAt: 0,
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ComingSoon extends StatelessWidget {
  final String message;
  const _ComingSoon({required this.message});

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
              Icons.auto_awesome_outlined,
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
