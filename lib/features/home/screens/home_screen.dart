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
import '../../../shared/utils/topic_badge.dart';
import '../../auth/auth_service.dart';
import '../../messages/providers/messages_provider.dart';
import '../providers/home_feed_provider.dart';

const _primary = Color(0xFF6366F1);
const _ink = Color(0xFF1A1A1A);
const _muted = Color(0xFF999999);
// 2026-07-06 起统一成 AppColors.bg（跟主题默认 scaffoldBackgroundColor
// 同一个值）——之前这里自己配了个 #FAFAF8，跟发现页/消息页走
// Theme.of(context).scaffoldBackgroundColor 拿到的 #F7F7FB 是两个肉眼
// 很难分辨但确实不同的浅灰白，底部导航栏跟内容区拼接处会露出一条若隐
// 若现的接缝，深色主题下反而因为直接复用同一个主题色没有这个问题
const _bg = AppColors.bg;

// 首页 Feed 顶部三个 Tab——「全部」「最新」都是真实数据，走同一个
// GET /auth/tutorials?status=published 接口：全部=后端默认排序（本来
// 就是 created_at DESC），最新=同一份列表在客户端按 createdAt 再排一遍
// （确认过后端目前没有 sort 参数，加了也会被忽略，所以不去改
// home_feed_provider.dart 的请求参数，只在展示层做一次保证正确的排序）。
// 「关注」没有真实数据源（后端 /auth/tutorials 做不到"只看关注的人"），
// 点了只提示"即将上线"，不展示任何列表，不编假数据
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
      backgroundColor: isDarkMode
          ? Theme.of(context).scaffoldBackgroundColor
          : _bg,
      body: SafeArea(
        child: RefreshIndicator(
          color: _primary,
          onRefresh: () => ref.read(homeFeedProvider.notifier).refresh(),
          child: CustomScrollView(
            controller: _scrollCtrl,
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverToBoxAdapter(child: _buildHeader(context, isDarkMode)),
              SliverToBoxAdapter(child: _buildXiaomengCard(isDarkMode)),
              SliverToBoxAdapter(child: _buildAppGrid(isDarkMode)),
              SliverToBoxAdapter(child: _buildMainTabs(isDarkMode)),
              SliverToBoxAdapter(
                child: _buildCategoryTabs(l10n, state, isDarkMode),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: 8)),
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

  Widget _buildXiaomengCard(bool isDark) {
    return GestureDetector(
      onTap: () => context.push('/xiaomeng'),
      child: Container(
        margin: const EdgeInsets.fromLTRB(12, 14, 12, 14),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: _primary,
          borderRadius: BorderRadius.circular(14),
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          children: [
            Positioned(
              top: -12,
              right: -12,
              child: Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.08),
                  shape: BoxShape.circle,
                ),
              ),
            ),
            Positioned(
              bottom: -16,
              left: 60,
              child: Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.05),
                  shape: BoxShape.circle,
                ),
              ),
            ),
            Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    shape: BoxShape.circle,
                  ),
                  child: const Text(
                    '梦',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        '问问小梦',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '搜索整个知识宇宙',
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.white.withValues(alpha: 0.7),
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.chevron_right,
                  color: Colors.white.withValues(alpha: 0.6),
                  size: 18,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  static const List<_AppEntry> _apps = [
    _AppEntry(
      icon: Icons.travel_explore_outlined,
      label: '极索',
      route: '/jisuo',
      color: Color(0xFF6366F1),
      bgLight: Color(0xFFEEF0FF),
      bgDark: Color(0xFF20284A),
    ),
    _AppEntry(
      icon: Icons.code_outlined,
      label: 'Notebook',
      route: '/notebook',
      color: Color(0xFF16A34A),
      bgLight: Color(0xFFDCFCE7),
      bgDark: Color(0xFF0F2A1A),
    ),
    _AppEntry(
      icon: Icons.groups_outlined,
      label: '群组',
      route: '/messages/groups',
      color: Color(0xFFD97706),
      bgLight: Color(0xFFFEF3C7),
      bgDark: Color(0xFF2A1F00),
    ),
    _AppEntry(
      icon: Icons.forum_outlined,
      label: '论坛',
      route: '/messages/forums',
      color: Color(0xFFEF4444),
      bgLight: Color(0xFFFEE2E2),
      bgDark: Color(0xFF2A0A0A),
    ),
  ];

  Widget _buildAppGrid(bool isDark) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: _apps
            .map(
              (app) => Expanded(
                child: GestureDetector(
                  onTap: () => context.push(app.route),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 48,
                        height: 48,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: isDark ? app.bgDark : app.bgLight,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Icon(app.icon, size: 22, color: app.color),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        app.label,
                        style: TextStyle(
                          fontSize: 10,
                          color: isDark
                              ? const Color(0xFF7A80A0)
                              : const Color(0xFF555555),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            )
            .toList(),
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

    return Row(
      children: [
        tab('全部', _MainTab.all, isFirst: true),
        tab('关注', _MainTab.follow, isFirst: false),
        tab('最新', _MainTab.latest, isFirst: false),
      ],
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
        itemCount: homeFeedCategories.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final category = homeFeedCategories[index];
          final selected = state.selectedCategory == category;
          return GestureDetector(
            onTap: () =>
                ref.read(homeFeedProvider.notifier).setCategory(category),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: selected
                    ? (isDarkMode
                          ? Theme.of(context).textTheme.bodyLarge?.color ??
                                Colors.white
                          : _ink)
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
                      : _muted,
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
    var items = state.filtered;
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
                      : _muted,
                ),
              ),
            ),
          ),
        ),
      ];
    }

    return [
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(0, 0, 0, 4),
        sliver: SliverList(
          delegate: SliverChildBuilderDelegate((context, i) {
            if (i == 0) {
              return _HeroCard(tutorial: items[i], isDark: isDarkMode);
            }
            return _CompactCard(tutorial: items[i], isDark: isDarkMode);
          }, childCount: items.length),
        ),
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

String _formatCount(int n) {
  if (n >= 10000) return '${(n / 10000).toStringAsFixed(1)}w';
  if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}k';
  return '$n';
}

// 根据文章标签推断小卡片的图标——跟话题色板（topic_badge.dart）分开的
// 一套更粗粒度的启发式，纯粹为了给没有封面图的小卡片一个还算贴切的
// 图标，不追求跟六色话题分类精确对应
IconData _iconForTags(List<String> tags) {
  final t = tags.join(' ').toLowerCase();
  if (t.contains('数学') || t.contains('统计') || t.contains('公式')) {
    return Icons.functions;
  }
  if (t.contains('代码') || t.contains('python') || t.contains('sql')) {
    return Icons.code;
  }
  if (t.contains('数据') || t.contains('分析')) return Icons.bar_chart;
  if (t.contains('ai') || t.contains('机器学习')) return Icons.psychology;
  return Icons.auto_stories;
}

class _AppEntry {
  final IconData icon;
  final String label;
  final String route;
  final Color color;
  final Color bgLight;
  final Color bgDark;
  const _AppEntry({
    required this.icon,
    required this.label,
    required this.route,
    required this.color,
    required this.bgLight,
    required this.bgDark,
  });
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
                color: isDark ? Colors.white.withValues(alpha: 0.85) : _ink,
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
                            ? const Color(0xFF0A0A1A)
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

// Feed 第一条——16:9 封面 + 标签 + 标题 + 作者行的大卡片，"文章感"，
// 不是小红书瀑布流那种图片主导的"帖子感"
class _HeroCard extends StatelessWidget {
  final TutorialModel tutorial;
  final bool isDark;
  const _HeroCard({required this.tutorial, required this.isDark});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => _openTutorial(context, tutorial),
      child: Container(
        margin: const EdgeInsets.fromLTRB(12, 0, 12, 10),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF111128) : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isDark ? const Color(0xFF1E1E3A) : const Color(0xFFEBEBEB),
            width: 0.5,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AspectRatio(
              aspectRatio: 16 / 9,
              child: tutorial.coverImage?.isNotEmpty == true
                  ? CachedNetworkImage(
                      imageUrl: tutorial.coverImage!,
                      fit: BoxFit.cover,
                      errorWidget: (context, url, error) => _heroPlaceholder(),
                    )
                  : _heroPlaceholder(),
            ),
            Padding(
              padding: const EdgeInsets.all(10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (tutorial.tags.isNotEmpty)
                    Wrap(
                      spacing: 4,
                      children: tutorial.tags
                          .take(2)
                          .map(
                            (t) => Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 7,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: isDark
                                    ? const Color(0xFF1A1A35)
                                    : const Color(0xFFEEF0FF),
                                borderRadius: BorderRadius.circular(99),
                              ),
                              child: Text(
                                t,
                                style: const TextStyle(
                                  fontSize: 10,
                                  color: _primary,
                                ),
                              ),
                            ),
                          )
                          .toList(),
                    ),
                  const SizedBox(height: 6),
                  Text(
                    tutorial.title,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: isDark
                          ? const Color(0xFFF0F2F8)
                          : const Color(0xFF1A1A1A),
                      height: 1.5,
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
                        radius: 9,
                      ),
                      const SizedBox(width: 5),
                      Expanded(
                        child: Text(
                          tutorial.username,
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.grey[400],
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      _StatChip(Icons.favorite_border, '${tutorial.likes}'),
                      const SizedBox(width: 8),
                      _StatChip(
                        Icons.visibility_outlined,
                        _formatCount(tutorial.views),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _heroPlaceholder() {
    return Container(
      color: isDark ? const Color(0xFF1A1A35) : const Color(0xFFEEF0FF),
      child: const Center(
        child: Icon(Icons.auto_stories, size: 40, color: _primary),
      ),
    );
  }
}

// Feed 第一条之后——图标区 + 标题 + 元信息一行的紧凑卡片
class _CompactCard extends StatelessWidget {
  final TutorialModel tutorial;
  final bool isDark;
  const _CompactCard({required this.tutorial, required this.isDark});

  @override
  Widget build(BuildContext context) {
    final rule = matchedTopicRuleFor(tutorial.tags);
    final iconColor = rule?.fg ?? _primary;
    final iconBg = isDark
        ? iconColor.withValues(alpha: 0.15)
        : (rule?.bg ?? const Color(0xFFEEF0FF));

    return GestureDetector(
      onTap: () => _openTutorial(context, tutorial),
      child: Container(
        margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF111128) : Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isDark ? const Color(0xFF1E1E3A) : const Color(0xFFEBEBEB),
            width: 0.5,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: iconBg,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                _iconForTags(tutorial.tags),
                size: 20,
                color: iconColor,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    tutorial.title,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: isDark
                          ? const Color(0xFFF0F2F8)
                          : const Color(0xFF1A1A1A),
                      height: 1.4,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '${tutorial.username} · ${tutorial.likes}赞 · '
                    '${_formatCount(tutorial.views)}阅读',
                    style: TextStyle(fontSize: 11, color: Colors.grey[400]),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  final IconData icon;
  final String value;
  const _StatChip(this.icon, this.value);

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 12, color: Colors.grey[400]),
        const SizedBox(width: 2),
        Text(value, style: TextStyle(fontSize: 11, color: Colors.grey[400])),
      ],
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
