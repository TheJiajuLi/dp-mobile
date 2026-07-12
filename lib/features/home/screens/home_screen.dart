import 'dart:async';
import 'dart:convert';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/founding_badge.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../../shared/models/tutorial_model.dart';
import '../../auth/auth_service.dart';
import '../../messages/providers/messages_provider.dart';
import '../providers/home_feed_provider.dart';

const _primary = Color(0xFF6366F1);

// 分类 pill 只是 homeFeedCategories 的一个展示子集——「全部」不再单独
// 出一个 pill（不选中任何 pill 就等价于全部，靠 HomeFeedState 默认的
// selectedCategory=='全部' 语义达成，不用改 home_feed_provider.dart），
// 顺带去掉「时事」腾地方给更常用的分类。筛选关键词表仍在 provider 里
// 保留「时事」这个 key，只是首页不再露出对应 pill 入口
const _categoryPills = ['科学', '经济', '生活', '数据', '编程'];

// 首页 Feed 顶部三个 Tab——「全部」「最新」都是真实数据，走同一个
// GET /auth/tutorials?status=published 接口：全部=后端默认排序（本来
// 就是 created_at DESC），最新=同一份列表在客户端按 createdAt 再排一遍
// （确认过后端目前没有 sort 参数，加了也会被忽略，所以不去改
// home_feed_provider.dart 的请求参数，只在展示层做一次保证正确的排序）。
// 「关注」没有真实数据源（后端 /auth/tutorials 做不到"只看关注的人"），
// 点了只提示"即将上线"，不展示任何列表，不编假数据。「热榜」同理
// 没有真实排行数据源，这版不加，避免又一个假 Tab
enum _MainTab { all, follow, latest }

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen>
    with WidgetsBindingObserver {
  final _scrollCtrl = ScrollController();
  _MainTab _mainTab = _MainTab.all;
  // "不感兴趣"——纯本地状态，隐藏当前会话里点过 × 的条目，不落库、
  // 不调接口，刷新/重进页面就会恢复显示
  final Set<String> _hiddenIds = {};

  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _scrollCtrl.addListener(_onScroll);
    _refreshTimer = Timer.periodic(
      const Duration(minutes: 30),
      (_) => _refreshAll(),
    );
    // 顶栏红点要用 notificationsProvider 里真实的未读数，不是
    // unreadCountProvider（那个是"通知+群组消息"合并总数，语义不对）。
    // notificationsProvider 只有真的调过 fetch() 才会有数据——消息页
    // 自己会轮询刷新，但用户完全可能先打开首页、还没点过"消息" Tab，
    // 这里主动拉一次，冷启动时红点也是准的
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ref.read(notificationsProvider.notifier).fetch();
    });
  }

  void _refreshAll() {
    ref.read(homeFeedProvider.notifier).refresh();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _refreshAll();
    }
  }

  @override
  void dispose() {
    _scrollCtrl.removeListener(_onScroll);
    _scrollCtrl.dispose();
    _refreshTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  void _onScroll() {
    if (_mainTab == _MainTab.follow) return;
    if (_scrollCtrl.position.pixels >=
        _scrollCtrl.position.maxScrollExtent - 200) {
      ref.read(homeFeedProvider.notifier).loadMore();
    }
  }

  String _categoryLabel(AppLocalizations l10n, String category) =>
      switch (category) {
        '科学' => l10n.categoryScience,
        '经济' => l10n.categoryEconomy,
        '时事' => l10n.categoryCurrentAffairs,
        '生活' => l10n.categoryLife,
        '数据' => l10n.categoryData,
        '编程' => l10n.categoryProgramming,
        _ => l10n.tagAll,
      };

  void _selectMainTab(_MainTab tab) {
    if (tab == _MainTab.follow) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('关注功能即将上线')));
    }
    setState(() => _mainTab = tab);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final state = ref.watch(homeFeedProvider);
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDarkMode ? const Color(0xFF000000) : const Color(0xFFFAFAF8),
      body: SafeArea(
        child: RefreshIndicator(
          color: _primary,
          onRefresh: () => ref.read(homeFeedProvider.notifier).refresh(),
          child: CustomScrollView(
            controller: _scrollCtrl,
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverToBoxAdapter(child: _buildHeader(context, isDarkMode)),
              SliverToBoxAdapter(child: _buildMainTabs(isDarkMode)),
              SliverToBoxAdapter(
                child: _buildCategoryTabs(l10n, state, isDarkMode),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: 4)),
              ..._buildFeedSlivers(context, l10n, state, isDarkMode),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context, bool isDark) {
    final user = ref.watch(currentUserProvider);
    final notifUnread = ref
        .watch(notificationsProvider)
        .where((n) => !n.isRead)
        .length;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Row(
        children: [
          const Text(
            '极梦',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: _primary,
            ),
          ),
          const Spacer(),
          _HeaderIconButton(
            icon: Icons.search_outlined,
            isDark: isDark,
            onTap: () => context.push('/search'),
          ),
          _HeaderIconButton(
            icon: Icons.notifications_outlined,
            isDark: isDark,
            showDot: notifUnread > 0,
            onTap: () => context.push('/messages/notifications'),
          ),
          GestureDetector(
            onTap: () => context.go('/profile'),
            child: Padding(
              padding: const EdgeInsets.only(left: 4),
              child: _Avatar(avatar: user?.avatar, username: user?.username),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMainTabs(bool isDark) {
    Widget tab(String label, _MainTab value, {required bool isFirst}) {
      final active = _mainTab == value;
      return GestureDetector(
        onTap: () => _selectMainTab(value),
        child: Padding(
          padding: EdgeInsets.fromLTRB(isFirst ? 16 : 12, 14, 12, 8),
          child: Column(
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: active ? FontWeight.w500 : FontWeight.normal,
                  color: active ? _primary : Colors.grey[400],
                ),
              ),
              const SizedBox(height: 4),
              Container(
                height: 2,
                width: 20,
                decoration: BoxDecoration(
                  color: active ? _primary : Colors.transparent,
                  borderRadius: BorderRadius.circular(1),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          tab('推荐', _MainTab.all, isFirst: true),
          tab('关注', _MainTab.follow, isFirst: false),
          tab('最新', _MainTab.latest, isFirst: false),
        ],
      ),
    );
  }

  Widget _buildCategoryTabs(
    AppLocalizations l10n,
    HomeFeedState state,
    bool isDarkMode,
  ) {
    if (_mainTab == _MainTab.follow) return const SizedBox.shrink();
    return SizedBox(
      height: 36,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: _categoryPills.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final category = _categoryPills[index];
          final selected = state.selectedCategory == category;
          return GestureDetector(
            onTap: () => ref
                .read(homeFeedProvider.notifier)
                .setCategory(selected ? '全部' : category),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: selected
                    ? (isDarkMode
                          ? Theme.of(context).textTheme.bodyLarge?.color ??
                                Colors.white
                          : const Color(0xFF1A1A1A))
                    : Theme.of(context).cardColor,
                borderRadius: BorderRadius.circular(99),
                border: selected
                    ? null
                    : Border.all(
                        color: isDarkMode
                            ? Theme.of(context).dividerColor
                            : const Color(0xFFE8E8E8),
                        width: 1.5,
                      ),
              ),
              child: Text(
                _categoryLabel(l10n, category),
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: selected
                      ? (isDarkMode
                            ? Theme.of(context).scaffoldBackgroundColor
                            : Colors.white)
                      : (isDarkMode
                            ? Theme.of(context).textTheme.bodySmall?.color
                            : const Color(0xFF555555)),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  List<Widget> _buildFeedSlivers(
    BuildContext context,
    AppLocalizations l10n,
    HomeFeedState state,
    bool isDarkMode,
  ) {
    if (_mainTab == _MainTab.follow) {
      return [
        SliverFillRemaining(
          hasScrollBody: false,
          child: Padding(
            padding: const EdgeInsets.only(top: 60),
            child: Center(
              child: Text(
                '关注功能即将上线',
                style: TextStyle(
                  color: isDarkMode
                      ? Theme.of(context).textTheme.bodySmall?.color
                      : const Color(0xFF999999),
                ),
              ),
            ),
          ),
        ),
      ];
    }

    if (state.isLoading && state.tutorials.isEmpty) {
      return [
        const SliverFillRemaining(
          hasScrollBody: false,
          child: Padding(
            padding: EdgeInsets.only(top: 120),
            child: Center(child: CircularProgressIndicator(color: _primary)),
          ),
        ),
      ];
    }
    if (state.error != null && state.tutorials.isEmpty) {
      return [
        SliverFillRemaining(
          hasScrollBody: false,
          child: Padding(
            padding: const EdgeInsets.only(top: 80),
            child: Center(
              child: Text(
                l10n.loadFailedWithReason('${state.error}'),
                style: const TextStyle(color: AppColors.danger, fontSize: 13),
              ),
            ),
          ),
        ),
      ];
    }

    // "最新" tab：同一份数据在展示层按 createdAt 重新排一遍——后端确认过
    // 目前没有 sort 参数，加了也会被忽略，这里保证不管后端支不支持这个
    // tab 看到的都是真的按时间新到旧
    var items = state.filtered.where((t) => !_hiddenIds.contains(t.id)).toList();
    if (_mainTab == _MainTab.latest) {
      items = [...items]..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    }

    if (items.isEmpty) {
      return [
        SliverFillRemaining(
          hasScrollBody: false,
          child: Padding(
            padding: const EdgeInsets.only(top: 60),
            child: Center(
              child: Text(
                l10n.noTutorialsYet,
                style: TextStyle(
                  color: isDarkMode
                      ? Theme.of(context).textTheme.bodySmall?.color
                      : const Color(0xFF999999),
                ),
              ),
            ),
          ),
        ),
      ];
    }

    return [
      SliverList(
        delegate: SliverChildBuilderDelegate((context, i) {
          return _FeedItem(
            tutorial: items[i],
            isDark: isDarkMode,
            onHide: () => setState(() => _hiddenIds.add(items[i].id)),
          );
        }, childCount: items.length),
      ),
      if (state.isLoadingMore)
        const SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Center(
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  color: _primary,
                  strokeWidth: 2,
                ),
              ),
            ),
          ),
        ),
      const SliverToBoxAdapter(child: SizedBox(height: 16)),
    ];
  }
}

void _openTutorial(BuildContext context, TutorialModel t) {
  context.push('/tutorial/${t.id}');
}

class _HeaderIconButton extends StatelessWidget {
  final IconData icon;
  final bool isDark;
  final bool showDot;
  final VoidCallback onTap;

  const _HeaderIconButton({
    required this.icon,
    required this.isDark,
    this.showDot = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6),
        child: SizedBox(
          width: 26,
          height: 26,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Icon(
                icon,
                size: 22,
                color: isDark ? Colors.white.withValues(alpha: 0.85) : const Color(0xFF1A1A1A),
              ),
              if (showDot)
                Positioned(
                  top: 0,
                  right: 0,
                  child: Container(
                    width: 7,
                    height: 7,
                    decoration: BoxDecoration(
                      color: const Color(0xFFEF4444),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: isDark
                            ? const Color(0xFF000000)
                            : const Color(0xFFFAFAF8),
                        width: 1.5,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  final String? avatar;
  final String? username;
  const _Avatar({this.avatar, this.username});

  @override
  Widget build(BuildContext context) {
    ImageProvider? provider;
    if (avatar != null && avatar!.isNotEmpty) {
      if (avatar!.startsWith('data:image')) {
        try {
          provider = MemoryImage(base64Decode(avatar!.split(',').last));
        } catch (_) {
          provider = null;
        }
      } else {
        provider = CachedNetworkImageProvider(avatar!);
      }
    }
    return CircleAvatar(
      radius: 16,
      backgroundColor: AppColors.primary,
      backgroundImage: provider,
      child: provider == null
          ? Text(
              (username?.isNotEmpty ?? false)
                  ? username![0].toUpperCase()
                  : '?',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            )
          : null,
    );
  }
}

// 无边框沉浸式 Feed 条目——知乎/Twitter 风格：没有卡片背景色、没有
// border，条目之间只靠底部一条 0.5px 分割线分隔，内容直接浮在页面
// 背景上
class _FeedItem extends StatelessWidget {
  final TutorialModel tutorial;
  final bool isDark;
  final VoidCallback onHide;
  const _FeedItem({
    required this.tutorial,
    required this.isDark,
    required this.onHide,
  });

  @override
  Widget build(BuildContext context) {
    final textPrimary = isDark ? Colors.white : const Color(0xFF1A1A1A);
    final textSecondary = isDark ? const Color(0xFF666666) : const Color(0xFF888888);
    final divider = isDark ? const Color(0xFF1A1A1A) : const Color(0xFFF0F0F0);
    final actionDivider = isDark ? const Color(0xFF111111) : const Color(0xFFF5F5F5);
    // "来源行"只在真的能确认内容来自小梦（账号 username=='小梦'）时才
    // 显示——没有别的字段能判断一篇教程是不是小梦发的，不编造这个状态
    final showSource = tutorial.username == '小梦';

    return GestureDetector(
      onTap: () => _openTutorial(context, tutorial),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 14, 12, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (showSource) ...[
                  Row(
                    children: [
                      const CircleAvatar(
                        radius: 8,
                        backgroundColor: _primary,
                        child: Text(
                          '梦',
                          style: TextStyle(
                            fontSize: 8,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                      ),
                      const SizedBox(width: 5),
                      Text(
                        '小梦 · 发表了文章',
                        style: TextStyle(
                          fontSize: 11,
                          color: isDark
                              ? const Color(0xFF555555)
                              : const Color(0xFFAAAAAA),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                ],
                Text(
                  tutorial.title,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: textPrimary,
                    height: 1.45,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    _AuthorAvatar(
                      avatar: tutorial.avatar,
                      username: tutorial.username,
                      isFoundingCreator: tutorial.isFoundingCreator,
                      radius: 11,
                    ),
                    const SizedBox(width: 7),
                    Text(
                      tutorial.username,
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFF888888),
                      ),
                    ),
                  ],
                ),
                if (tutorial.summary?.isNotEmpty ?? false) ...[
                  const SizedBox(height: 8),
                  Text(
                    tutorial.summary!,
                    style: TextStyle(
                      fontSize: 13,
                      color: textSecondary,
                      height: 1.7,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
                if (tutorial.coverImage?.isNotEmpty == true) ...[
                  const SizedBox(height: 10),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: AspectRatio(
                      aspectRatio: 16 / 9,
                      child: CachedNetworkImage(
                        imageUrl: tutorial.coverImage!,
                        fit: BoxFit.cover,
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  decoration: BoxDecoration(
                    border: Border(
                      top: BorderSide(color: actionDivider, width: 0.5),
                    ),
                  ),
                  child: Row(
                    children: [
                      _ActionBtn(
                        icon: Icons.thumb_up_outlined,
                        label: '${tutorial.likes}',
                        isDark: isDark,
                        onTap: () => _openTutorial(context, tutorial),
                      ),
                      _ActionBtn(
                        icon: Icons.bookmark_outline,
                        label: '收藏',
                        isDark: isDark,
                        onTap: () => _openTutorial(context, tutorial),
                      ),
                      _ActionBtn(
                        icon: Icons.chat_bubble_outline,
                        label: '评论',
                        isDark: isDark,
                        onTap: () => _openTutorial(context, tutorial),
                      ),
                      const Spacer(),
                      GestureDetector(
                        onTap: onHide,
                        child: Icon(
                          Icons.close,
                          size: 16,
                          color: isDark
                              ? const Color(0xFF444444)
                              : const Color(0xFFCCCCCC),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Container(height: 0.5, color: divider),
        ],
      ),
    );
  }
}

class _ActionBtn extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isDark;
  final VoidCallback onTap;
  const _ActionBtn({
    required this.icon,
    required this.label,
    required this.isDark,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = isDark ? const Color(0xFF666666) : const Color(0xFF888888);
    return GestureDetector(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.only(right: 20),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(width: 4),
            Text(label, style: TextStyle(fontSize: 12, color: color)),
          ],
        ),
      ),
    );
  }
}

class _AuthorAvatar extends StatelessWidget {
  final String? avatar;
  final String username;
  final double radius;
  final bool isFoundingCreator;
  const _AuthorAvatar({
    required this.avatar,
    required this.username,
    this.radius = 9,
    this.isFoundingCreator = false,
  });

  Widget _letter() => CircleAvatar(
    radius: radius,
    backgroundColor: _primary.withValues(alpha: 0.15),
    child: Text(
      username.isNotEmpty ? username.substring(0, 1) : '?',
      style: TextStyle(
        fontSize: radius,
        fontWeight: FontWeight.w700,
        color: _primary,
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    return FoundingAvatarRing(
      isFoundingCreator: isFoundingCreator,
      size: radius * 2,
      child: _content(context),
    );
  }

  Widget _content(BuildContext context) {
    if (avatar == null || avatar!.isEmpty) return _letter();

    if (avatar!.startsWith('data:image')) {
      try {
        final raw = avatar!.split(',').last;
        return CircleAvatar(
          radius: radius,
          backgroundImage: MemoryImage(base64Decode(raw)),
        );
      } catch (_) {
        return _letter();
      }
    }

    return ClipOval(
      child: SizedBox(
        width: radius * 2,
        height: radius * 2,
        child: CachedNetworkImage(
          imageUrl: avatar!,
          fit: BoxFit.cover,
          placeholder: (context, url) =>
              Container(color: Theme.of(context).dividerColor),
          errorWidget: (context, url, error) => _letter(),
        ),
      ),
    );
  }
}
