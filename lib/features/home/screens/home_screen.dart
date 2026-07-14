import 'dart:async';
import 'dart:convert';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_client.dart';
import '../../../core/profile_refresh_signal.dart';
import '../../../core/theme/app_theme.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../../shared/models/tutorial_model.dart';
import '../../../shared/widgets/article_flow_item.dart';
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
// 「关注」后端没有"只看关注的人"的聚合接口，客户端自己拼真实数据：
// 拉关注列表→逐个拉作者已发布作品→合并去重排序（见 _loadFollowingFeed）。
// 「热榜」没有真实排行数据源，这版不加，避免又一个假 Tab
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

  // 「关注」tab 的信息流——后端没有"只看关注的人"的聚合接口，客户端自己拼：
  // 先拉我关注的作者列表（GET /auth/users/:id/following），再逐个拉他们的
  // 已发布作品（GET /auth/tutorials?author=id），合并去重按时间新到旧排。
  // 懒加载：第一次切到「关注」才拉
  List<TutorialModel> _followingFeed = [];
  bool _followingLoading = false;
  bool _followingLoaded = false;
  String? _followingError;

  Timer? _refreshTimer;

  Future<void> _loadFollowingFeed() async {
    final myId = ref.read(currentUserProvider)?.id;
    if (myId == null || myId.isEmpty) {
      if (!mounted) return;
      setState(() {
        _followingFeed = [];
        _followingLoading = false;
        _followingLoaded = true;
      });
      return;
    }
    setState(() {
      _followingLoading = true;
      _followingError = null;
    });
    final api = ref.read(apiClientProvider);
    try {
      final followRes = await api.get('/auth/users/$myId/following');
      final following = (followRes.success && followRes.data != null)
          ? ((followRes.data['following'] as List?) ?? const [])
          : const [];
      final authorIds = following
          .map((u) => (u as Map)['id']?.toString() ?? '')
          .where((id) => id.isNotEmpty)
          // 关注很多人时限制并发请求数，取前 40 个作者（够填满信息流了）
          .take(40)
          .toList();
      if (authorIds.isEmpty) {
        if (!mounted) return;
        setState(() {
          _followingFeed = [];
          _followingLoading = false;
          _followingLoaded = true;
        });
        return;
      }
      final results = await Future.wait(
        authorIds.map(
          (id) => api.get(
            '/auth/tutorials',
            queryParameters: {
              'author': id,
              'status': 'published',
              'limit': '10',
            },
          ),
        ),
      );
      final seen = <String>{};
      final all = <TutorialModel>[];
      for (final res in results) {
        if (!res.success || res.data == null) continue;
        final list = ((res.data as Map)['tutorials'] as List?) ?? const [];
        for (final j in list) {
          final t = TutorialModel.fromJson(Map<String, dynamic>.from(j as Map));
          if (seen.add(t.id)) all.add(t);
        }
      }
      all.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      if (!mounted) return;
      setState(() {
        _followingFeed = all;
        _followingLoading = false;
        _followingLoaded = true;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _followingError = '$e';
        _followingLoading = false;
        _followingLoaded = true;
      });
    }
  }

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
    setState(() => _mainTab = tab);
    // 第一次切到「关注」才拉数据，不一进首页就发一堆请求
    if (tab == _MainTab.follow && !_followingLoaded && !_followingLoading) {
      _loadFollowingFeed();
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final state = ref.watch(homeFeedProvider);
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    // 首页是 IndexedStack 常驻实例，发布/编辑教程后不会自动重新拉取——
    // 跟"我的"页同一个信号：谁改了内容就 bump 一次，这里监听到变化就
    // 重新拉一次首页 feed，不然编辑保存后首页卡片还是旧的摘要/预览
    ref.listen<int>(profileRefreshSignalProvider, (prev, next) {
      if (prev != next) ref.read(homeFeedProvider.notifier).refresh();
    });

    final feed = SafeArea(
      child: RefreshIndicator(
        color: _primary,
        onRefresh: () => _mainTab == _MainTab.follow
            ? _loadFollowingFeed()
            : ref.read(homeFeedProvider.notifier).refresh(),
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
    );

    return Scaffold(
      backgroundColor: isDarkMode ? AppColors.darkBg : const Color(0xFFFAFAF8),
      // 深色下顶部叠两片低透明度光晕，制造"背景有氛围、不是纯死黑"的
      // 极光感；浅色沿用原本的纯背景，不需要这层
      body: isDarkMode
          ? Stack(
              children: [
                Positioned(
                  top: -100,
                  left: -60,
                  child: Container(
                    width: 280,
                    height: 280,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: _primary.withValues(alpha: 0.08),
                    ),
                  ),
                ),
                Positioned(
                  top: -80,
                  right: -40,
                  child: Container(
                    width: 200,
                    height: 200,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: const Color(0xFF50B4FF).withValues(alpha: 0.06),
                    ),
                  ),
                ),
                feed,
              ],
            )
          : feed,
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
                          ? const Color(0xFF5B61FF)
                          : const Color(0xFF1A1A1A))
                    : (isDarkMode ? AppColors.darkSurface : Colors.white),
                borderRadius: BorderRadius.circular(99),
                border: selected
                    ? null
                    : Border.all(
                        color: isDarkMode
                            ? AppColors.darkBorder
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
                      ? Colors.white
                      : (isDarkMode
                            ? AppColors.darkTextSecondary
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
      final mutedColor = isDarkMode
          ? Theme.of(context).textTheme.bodySmall?.color
          : const Color(0xFF999999);
      if (_followingLoading && _followingFeed.isEmpty) {
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
      if (_followingError != null && _followingFeed.isEmpty) {
        return [
          SliverFillRemaining(
            hasScrollBody: false,
            child: Padding(
              padding: const EdgeInsets.only(top: 80),
              child: Center(
                child: Text(
                  l10n.loadFailedWithReason('$_followingError'),
                  style: const TextStyle(color: AppColors.danger, fontSize: 13),
                ),
              ),
            ),
          ),
        ];
      }
      final followItems = _followingFeed
          .where((t) => !_hiddenIds.contains(t.id))
          .toList();
      if (followItems.isEmpty) {
        return [
          SliverFillRemaining(
            hasScrollBody: false,
            child: Padding(
              padding: const EdgeInsets.only(top: 100, left: 40, right: 40),
              child: Center(
                child: Text(
                  '关注的作者还没有新作品\n关注更多创作者，这里就会有他们的动态',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: mutedColor, height: 1.6),
                ),
              ),
            ),
          ),
        ];
      }
      return [
        SliverList(
          delegate: SliverChildBuilderDelegate((context, i) {
            return ArticleFlowItem(
              tutorial: followItems[i],
              onTap: () => _openTutorial(context, followItems[i]),
              onHide: () => setState(() => _hiddenIds.add(followItems[i].id)),
            );
          }, childCount: followItems.length),
        ),
        const SliverToBoxAdapter(child: SizedBox(height: 16)),
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
    var items = state.filtered
        .where((t) => !_hiddenIds.contains(t.id))
        .toList();
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
          return ArticleFlowItem(
            tutorial: items[i],
            onTap: () => _openTutorial(context, items[i]),
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
                color: isDark
                    ? Colors.white.withValues(alpha: 0.85)
                    : const Color(0xFF1A1A1A),
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
                            ? AppColors.darkBg
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
