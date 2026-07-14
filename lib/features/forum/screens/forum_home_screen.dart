import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart' show Share;

import '../../../core/network/api_client.dart';
import '../../../shared/utils/forum_gradient.dart';
import 'forum_list_screen.dart';

const _primary = Color(0xFF6366F1);

// 论坛主页——GET /auth/forums/:forumId 已经真实返回 forum + pinnedPosts
// （member_count/follower_count/reply_count/is_following 都是后端算好的，
// is_following 是 SELECT COUNT(*) 出来的 0/1）。精华/最新/最热三个 tab
// 复用同一个 ForumListScreen，只是传不同的 sort
class ForumHomeScreen extends ConsumerStatefulWidget {
  final String forumId;
  const ForumHomeScreen({super.key, required this.forumId});

  @override
  ConsumerState<ForumHomeScreen> createState() => _ForumHomeScreenState();
}

class _ForumHomeScreenState extends ConsumerState<ForumHomeScreen>
    with SingleTickerProviderStateMixin {
  Map<String, dynamic>? _forum;
  List<Map<String, dynamic>> _pinnedPosts = [];
  bool _loading = true;
  bool _following = false;
  late TabController _tabCtrl;
  // 发帖成功后不能只刷新论坛主页自己的元信息（_loadForum 只拉
  // post_count/pinnedPosts 这些汇总数据）——精华/最新/最热三个 tab 各是
  // 独立的 ForumListScreen 实例，各自拿着自己上次拉到的 _posts，不会因为
  // 主页刷新一次就跟着重新拉。用这个信号广播给三个 tab，让它们各自重新
  // 拉一次自己的帖子列表
  final _refreshSignal = ValueNotifier<int>(0);

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 3, vsync: this);
    _loadForum();
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    _refreshSignal.dispose();
    super.dispose();
  }

  Future<void> _loadForum() async {
    final res = await ref
        .read(apiClientProvider)
        .get('/auth/forums/${widget.forumId}');
    if (!mounted) return;
    if (!res.success || res.data is! Map) {
      setState(() => _loading = false);
      return;
    }
    final data = res.data as Map;
    final forum = Map<String, dynamic>.from(data['forum'] as Map? ?? {});
    setState(() {
      _forum = forum;
      _pinnedPosts = ((data['pinnedPosts'] as List?) ?? const [])
          .map((p) => Map<String, dynamic>.from(p as Map))
          .toList();
      _following = forum['is_following'] == 1 || forum['is_following'] == true;
      _loading = false;
    });
  }

  Future<void> _toggleFollow() async {
    final was = _following;
    setState(() => _following = !_following);
    final res = await ref
        .read(apiClientProvider)
        .post('/auth/forums/${widget.forumId}/follow');
    if (!mounted) return;
    if (!res.success) {
      setState(() => _following = was);
    }
  }

  // 分享论坛——调起系统通用分享面板，带论坛名/简介 + 站内链接，跟教程分享
  // 用的同一套 dreamingpolar.com 链接格式
  void _shareForum() {
    final name = _forum?['name']?.toString() ?? '极梦论坛';
    final desc = _forum?['description']?.toString() ?? '';
    final url = 'https://dreamingpolar.com/forum/${widget.forumId}';
    final text = desc.isNotEmpty
        ? '来极梦「$name」逛逛——$desc\n$url'
        : '来极梦「$name」逛逛\n$url';
    Share.share(text, subject: name);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    // 之前顶栏/Tab条用的是建群/发帖页那套写死的 #0A0A1A/白色"产品感"
    // 背景，但这个页面的 Scaffold 自己没设背景色，走的是主题默认的
    // scaffoldBackgroundColor（暗色 #1C1C1E / 浅色 #F7F7FB）——两个颜色
    // 对不上，顶栏跟下面 TabBarView 内容区之间会有一条明显的接缝，暗色下
    // 尤其明显。论坛主页是浏览类页面，不是建群/发帖那种独立表单页，跟着
    // 主题背景走更统一，不用另起一套颜色
    // 浅色统一成首页米白 #FAFAF8（不再是偏冷的默认 #F7F7FB）；深色不变。
    // 顶栏/Tab条/内容区都用这个 bg，保持一整块不出接缝
    final bg = isDark
        ? Theme.of(context).scaffoldBackgroundColor
        : const Color(0xFFFAFAF8);

    return Scaffold(
      backgroundColor: bg,
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : NestedScrollView(
              headerSliverBuilder: (ctx, inner) => [
                SliverAppBar(
                  backgroundColor: bg,
                  elevation: 0,
                  pinned: true,
                  leading: IconButton(
                    icon: const Icon(Icons.arrow_back_ios, size: 18),
                    onPressed: () => context.pop(),
                  ),
                  title: Text(
                    _forum?['name']?.toString() ?? '',
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                SliverToBoxAdapter(child: _buildBanner(isDark)),
                if (_pinnedPosts.isNotEmpty)
                  SliverToBoxAdapter(child: _buildNotice(isDark)),
                SliverPersistentHeader(
                  pinned: true,
                  delegate: _TabBarDelegate(
                    TabBar(
                      controller: _tabCtrl,
                      tabs: const [
                        Tab(text: '精华'),
                        Tab(text: '最新'),
                        Tab(text: '最热'),
                      ],
                      labelColor: _primary,
                      unselectedLabelColor: isDark
                          ? Colors.white.withValues(alpha: 0.4)
                          : Colors.grey[400],
                      indicatorColor: _primary,
                      indicatorWeight: 2,
                      labelStyle: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                      dividerColor: isDark
                          ? Colors.white.withValues(alpha: 0.06)
                          : const Color(0xFFEBEBEB),
                    ),
                    backgroundColor: bg,
                  ),
                ),
              ],
              body: TabBarView(
                controller: _tabCtrl,
                children: [
                  ForumListScreen(
                    forumId: widget.forumId,
                    sort: 'featured',
                    refreshSignal: _refreshSignal,
                  ),
                  ForumListScreen(
                    forumId: widget.forumId,
                    sort: 'latest',
                    refreshSignal: _refreshSignal,
                  ),
                  ForumListScreen(
                    forumId: widget.forumId,
                    sort: 'hot',
                    refreshSignal: _refreshSignal,
                  ),
                ],
              ),
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          await context.push(
            '/forum/create',
            extra: {
              'forumId': widget.forumId,
              'forumTags': List<String>.from(_forum?['tags'] ?? const []),
            },
          );
          _refreshSignal.value++;
          _loadForum();
        },
        backgroundColor: _primary,
        child: const Icon(Icons.edit, color: Colors.white),
      ),
    );
  }

  Widget _buildBanner(bool isDark) {
    final name = _forum?['name']?.toString() ?? '';
    final desc = _forum?['description']?.toString() ?? '';
    final members = (_forum?['member_count'] as num?)?.toInt() ?? 0;
    final posts = (_forum?['post_count'] as num?)?.toInt() ?? 0;
    final replies = (_forum?['reply_count'] as num?)?.toInt() ?? 0;
    final tags = List<String>.from((_forum?['tags'] as List?) ?? const []);
    final colorIdx = (_forum?['color_index'] as num?)?.toInt() ?? 0;
    final avatar = _forum?['avatar']?.toString();

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: isDark
                ? Colors.white.withValues(alpha: 0.06)
                : const Color(0xFFEBEBEB),
            width: 0.5,
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 58,
                height: 58,
                decoration: BoxDecoration(
                  gradient: (avatar?.isNotEmpty ?? false)
                      ? null
                      : LinearGradient(
                          colors: forumGradientFor(colorIdx),
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                  image: (avatar?.isNotEmpty ?? false)
                      ? DecorationImage(
                          image: NetworkImage(avatar!),
                          fit: BoxFit.cover,
                        )
                      : null,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: (avatar?.isNotEmpty ?? false)
                    ? null
                    : Center(
                        child: Text(
                          name.isNotEmpty ? name.substring(0, 1) : 'F',
                          style: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                          ),
                        ),
                      ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                        color: isDark
                            ? Colors.white.withValues(alpha: 0.9)
                            : const Color(0xFF1A1A1A),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      desc,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        height: 1.5,
                        color: isDark
                            ? Colors.white.withValues(alpha: 0.4)
                            : Colors.grey[500],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _StatItem('$members', '成员'),
              const SizedBox(width: 20),
              _StatItem('$posts', '帖子'),
              const SizedBox(width: 20),
              _StatItem('$replies', '回复'),
              if (tags.isNotEmpty) ...[
                const SizedBox(width: 20),
                Expanded(
                  child: Wrap(
                    spacing: 5,
                    runSpacing: 4,
                    children: tags
                        .take(2)
                        .map(
                          (t) => Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 7,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: isDark
                                  ? _primary.withValues(alpha: 0.15)
                                  : const Color(0xFFEEF0FF),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              t,
                              style: const TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w500,
                                color: _primary,
                              ),
                            ),
                          ),
                        )
                        .toList(),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: GestureDetector(
                  onTap: _toggleFollow,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    height: 34,
                    decoration: BoxDecoration(
                      color: _following
                          ? (isDark
                                ? Colors.white.withValues(alpha: 0.08)
                                : const Color(0xFFF0F0F0))
                          : _primary,
                      borderRadius: BorderRadius.circular(99),
                    ),
                    child: Center(
                      child: Text(
                        _following ? '✓ 已关注' : '关注',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: _following
                              ? (isDark
                                    ? Colors.white.withValues(alpha: 0.6)
                                    : const Color(0xFF555555))
                              : Colors.white,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: _shareForum,
                child: Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: isDark
                        ? Colors.white.withValues(alpha: 0.08)
                        : const Color(0xFFF0F0F0),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.share,
                    size: 16,
                    color: isDark
                        ? Colors.white.withValues(alpha: 0.5)
                        : const Color(0xFF555555),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildNotice(bool isDark) {
    final post = _pinnedPosts.first;
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: const Color(0xFFFEF3C7),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: const Color(0xFFD97706).withValues(alpha: 0.2),
          width: 0.5,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.push_pin, size: 14, color: Color(0xFFD97706)),
          const SizedBox(width: 7),
          Expanded(
            child: Text(
              post['title']?.toString() ?? '',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 12,
                height: 1.5,
                color: Color(0xFF92400E),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatItem extends StatelessWidget {
  final String value;
  final String label;
  const _StatItem(this.value, this.label);

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        value,
        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
      ),
      Text(label, style: TextStyle(fontSize: 10, color: Colors.grey[400])),
    ],
  );
}

class _TabBarDelegate extends SliverPersistentHeaderDelegate {
  final TabBar tabBar;
  final Color backgroundColor;
  const _TabBarDelegate(this.tabBar, {required this.backgroundColor});

  @override
  double get minExtent => tabBar.preferredSize.height;
  @override
  double get maxExtent => tabBar.preferredSize.height;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    return Container(color: backgroundColor, child: tabBar);
  }

  @override
  bool shouldRebuild(_TabBarDelegate old) =>
      old.tabBar != tabBar || old.backgroundColor != backgroundColor;
}
