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
import '../../messages/utils/message_avatar.dart' show messageTimeAgo;
import '../../notebook/services/notebook_service.dart';
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

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen>
    with WidgetsBindingObserver {
  final _scrollCtrl = ScrollController();
  // "继续创作"用的是本地最近 Notebook 列表（NotebookService.getRecentList，
  // 跟个人主页 Notebook tab 同一份数据源），不是编个假的完成度百分比——
  // 这些 Notebook 本来就没有"完成度"这个概念，只有真实的 cell 数/更新时间
  List<Map<String, dynamic>> _recentNotebooks = [];

  // 顶部推荐轮播用的状态
  final _heroCtrl = PageController(viewportFraction: 0.88);
  int _heroPage = 0;

  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _scrollCtrl.addListener(_onScroll);
    _loadRecentNotebooks();
    _refreshTimer = Timer.periodic(
      const Duration(minutes: 30),
      (_) => _refreshAll(),
    );
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
    _heroCtrl.dispose();
    _refreshTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _loadRecentNotebooks() async {
    final userId = ref.read(currentUserProvider)?.id ?? 'guest';
    final list = await NotebookService(userId).getRecentList();
    if (mounted) setState(() => _recentNotebooks = list);
  }

  void _onScroll() {
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
        child: Column(
          children: [
            _buildHeader(context, l10n, isDarkMode),
            const SizedBox(height: 10),
            _buildCategoryTabs(l10n, state, isDarkMode),
            const SizedBox(height: 8),
            Expanded(
              child: RefreshIndicator(
                color: _primary,
                onRefresh: () => ref.read(homeFeedProvider.notifier).refresh(),
                child: _buildBody(context, l10n, state, isDarkMode),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(
    BuildContext context,
    AppLocalizations l10n,
    bool isDarkMode,
  ) {
    final user = ref.watch(currentUserProvider);
    final textColor = isDarkMode
        ? Theme.of(context).textTheme.bodyLarge?.color ?? Colors.white
        : _ink;
    final subColor = isDarkMode
        ? Theme.of(context).textTheme.bodySmall?.color ?? Colors.grey
        : _muted;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      l10n.appName,
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        color: textColor,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Container(
                      width: 6,
                      height: 6,
                      decoration: const BoxDecoration(
                        color: _primary,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  l10n.homeAppSubtitle,
                  style: TextStyle(fontSize: 12, color: subColor),
                ),
              ],
            ),
          ),
          GestureDetector(
            onTap: () => context.push('/search'),
            child: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: Theme.of(context).cardColor,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: Theme.of(context).dividerColor,
                  width: 0.5,
                ),
              ),
              child: Icon(Icons.search, size: 18, color: textColor),
            ),
          ),
          GestureDetector(
            onTap: () => context.go('/profile'),
            child: Padding(
              padding: const EdgeInsets.only(left: 8),
              child: _Avatar(avatar: user?.avatar, username: user?.username),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCategoryTabs(
    AppLocalizations l10n,
    HomeFeedState state,
    bool isDarkMode,
  ) {
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

  Widget _buildBody(
    BuildContext context,
    AppLocalizations l10n,
    HomeFeedState state,
    bool isDarkMode,
  ) {
    if (state.isLoading && state.tutorials.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: const [
          SizedBox(height: 120),
          Center(child: CircularProgressIndicator(color: _primary)),
        ],
      );
    }
    if (state.error != null && state.tutorials.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          const SizedBox(height: 80),
          Center(
            child: Text(
              l10n.loadFailedWithReason('${state.error}'),
              style: const TextStyle(color: AppColors.danger, fontSize: 13),
            ),
          ),
        ],
      );
    }

    // "推荐文章"顶部沿用大卡轮播的滚动式样式（原来发现页搬过来的那套
    // PageView+圆点），取当前已加载列表的前5条；剩下的才是宫格瀑布流。
    // 继续创作挪到 Feed 末尾当"逛完还有更多"的附加区块，只在 Feed 翻到
    // 底（!hasMore）时才接上
    final all = state.filtered;
    final carouselItems = all.take(5).toList();
    // 宫格不排除轮播里已经出现过的前5条——账号内容不多时（比如只有5篇）
    // 排除掉会让宫格直接空掉，而且宫格区域完全没内容可滚，会连带卡住
    // _onScroll 的触底翻页判断（没有可滚动的高度，永远碰不到"接近底部"
    // 那个阈值，state.hasMore 是 true 也永远翻不了下一页）。轮播只是把
    // 同一份列表的前几条挑出来做个"重点展示"的滚动式样式，跟下面完整
    // 的宫格瀑布流本来就允许重复，不是两份互斥的数据
    final gridItems = all;
    final showEmpty = all.isEmpty;

    final bottomSuffix = <Widget>[
      if (_recentNotebooks.isNotEmpty) ...[
        _buildContinueCreating(context, l10n, isDarkMode),
        const SizedBox(height: 20),
      ],
    ];
    final showSuffix =
        !showEmpty &&
        !state.hasMore &&
        !state.isLoadingMore &&
        bottomSuffix.isNotEmpty;

    return CustomScrollView(
      controller: _scrollCtrl,
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
          sliver: SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildRecommendedHeader(context, l10n, state),
                const SizedBox(height: 10),
                if (carouselItems.isNotEmpty) ...[
                  _recommendedCarousel(carouselItems),
                  const SizedBox(height: 18),
                ],
              ],
            ),
          ),
        ),
        if (showEmpty)
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
          )
        else
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
            sliver: SliverGrid(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                crossAxisSpacing: 10,
                mainAxisSpacing: 10,
                // 顶部tab到底部导航栏之间的可视区域大致能完整露出两行
                // （四张卡）不用先滚——图片区+标题两行+作者行加起来的
                // 高宽比调出来的经验值，不是精确按屏幕高度反算的（轮播
                // 区块高度本身就因设备而异，没法保证所有机型都恰好4张）
                childAspectRatio: 0.66,
              ),
              delegate: SliverChildBuilderDelegate(
                (context, i) =>
                    _GridCard(tutorial: gridItems[i], isDarkMode: isDarkMode),
                childCount: gridItems.length,
              ),
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
        if (showSuffix)
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
            sliver: SliverToBoxAdapter(child: Column(children: bottomSuffix)),
          )
        else
          const SliverToBoxAdapter(child: SizedBox(height: 16)),
      ],
    );
  }

  Widget _recommendedCarousel(List<TutorialModel> heroList) {
    return Column(
      children: [
        SizedBox(
          height: 208,
          child: PageView.builder(
            controller: _heroCtrl,
            // PageController(viewportFraction < 1) 默认 padEnds:true，会给
            // 第一张/最后一张卡自动叠加一圈居中留白——这才是首卡左边距一直
            // 顶不到边的真正原因，之前每次都只调 itemBuilder 自己的 Padding，
            // 治标不治本，这个 flag 才是不留白的根本开关
            padEnds: false,
            itemCount: heroList.length,
            onPageChanged: (i) => setState(() => _heroPage = i),
            // 外层 ListView 本身已经统一带 16px 左右边距——这里只补卡片
            // 之间的间隙，不能再对称地左右各留 6px，不然首卡左边会变成
            // 16+6=22px，比右边露出来的下一张卡片间隙明显宽一截
            itemBuilder: (context, index) => Padding(
              padding: EdgeInsets.only(
                right: index == heroList.length - 1 ? 0 : 10,
              ),
              child: _recommendedCard(context, heroList[index]),
            ),
          ),
        ),
        if (heroList.length > 1) ...[
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(
              heroList.length,
              (i) => AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                margin: const EdgeInsets.symmetric(horizontal: 3),
                width: _heroPage == i ? 16 : 6,
                height: 6,
                decoration: BoxDecoration(
                  color: _heroPage == i
                      ? _primary
                      : Theme.of(context).dividerColor,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _recommendedCard(BuildContext context, TutorialModel t) {
    final rule = matchedTopicRuleFor(t.tags);
    return GestureDetector(
      onTap: () => _openTutorial(context, t),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (t.coverImage?.isNotEmpty == true)
              CachedNetworkImage(
                imageUrl: t.coverImage!,
                fit: BoxFit.cover,
                errorWidget: (context, url, error) =>
                    _recommendedGradientBg(rule),
              )
            else
              _recommendedGradientBg(rule),
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  stops: const [0.35, 1],
                  colors: [
                    Colors.transparent,
                    Colors.black.withValues(alpha: 0.68),
                  ],
                ),
              ),
            ),
            Positioned(
              left: 16,
              right: 16,
              bottom: 14,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (rule != null)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 9,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.22),
                        borderRadius: BorderRadius.circular(99),
                      ),
                      child: Text(
                        rule.label,
                        style: const TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  const SizedBox(height: 8),
                  Text(
                    t.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                      height: 1.28,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      _AuthorAvatar(
                        avatar: t.avatar,
                        username: t.username,
                        isFoundingCreator: t.isFoundingCreator,
                        radius: 9,
                      ),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          t.username,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.white70,
                          ),
                        ),
                      ),
                      const Spacer(),
                      const Icon(
                        Icons.favorite,
                        size: 13,
                        color: Colors.white70,
                      ),
                      const SizedBox(width: 3),
                      Text(
                        '${t.likes}',
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.white70,
                        ),
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

  Widget _recommendedGradientBg(TopicBadgeRule? rule) {
    final base = rule?.fg ?? _primary;
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [base.withValues(alpha: 0.9), base.withValues(alpha: 0.55)],
        ),
      ),
    );
  }

  // 继续创作——真实的本地最近 Notebook 列表，不编完成度百分比（这些
  // Notebook 本来就没有这个概念），只展示真实的 cell 数和更新时间
  Widget _buildContinueCreating(
    BuildContext context,
    AppLocalizations l10n,
    bool isDarkMode,
  ) {
    final items = _recentNotebooks.take(4).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionHeader(title: l10n.continueCreatingTitle),
        const SizedBox(height: 10),
        SizedBox(
          height: 96,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: items.length,
            separatorBuilder: (_, _) => const SizedBox(width: 10),
            itemBuilder: (context, index) {
              final nb = items[index];
              final name = nb['name'] as String? ?? '';
              final cellCount = nb['cellCount'] as int? ?? 0;
              final updatedAt = (nb['updatedAt'] as num?)?.toInt() ?? 0;
              return GestureDetector(
                onTap: () => context.push('/notebook/${nb['id']}'),
                child: Container(
                  width: 168,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Theme.of(context).cardColor,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: Theme.of(context).dividerColor,
                      width: 0.5,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 28,
                        height: 28,
                        decoration: BoxDecoration(
                          color: _primary.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(
                          Icons.description_outlined,
                          size: 15,
                          color: _primary,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: Theme.of(context).textTheme.bodyLarge?.color,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${l10n.notebookCellsCount(cellCount)} · ${messageTimeAgo(l10n, updatedAt * 1000)}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11,
                          color: Theme.of(context).textTheme.bodySmall?.color,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildRecommendedHeader(
    BuildContext context,
    AppLocalizations l10n,
    HomeFeedState state,
  ) {
    return _SectionHeader(title: l10n.recommendedArticlesTitle);
  }
}

void _openTutorial(BuildContext context, TutorialModel t) {
  context.push('/tutorial/${t.id}');
}

// 各段小标题统一样式——继续创作/热门话题/推荐文章 三段都用这个，右侧
// action 是可选的一个文字按钮（推荐文章的"换一换"），大多数段不需要
class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          title,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: Theme.of(context).textTheme.bodyLarge?.color,
          ),
        ),
      ],
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
      radius: 18,
      backgroundColor: AppColors.primary,
      backgroundImage: provider,
      child: provider == null
          ? Text(
              (username?.isNotEmpty ?? false)
                  ? username![0].toUpperCase()
                  : '?',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
            )
          : null,
    );
  }
}

// 小红书风格宫格卡——图片铺满卡片上半部（没有封面图就用话题色渐变占位，
// 不留白），下半部标题最多两行 + 作者行，圆角卡片，跟 SliverGrid 的
// crossAxisCount:2 配合铺成瀑布流网格
class _GridCard extends StatelessWidget {
  final TutorialModel tutorial;
  final bool isDarkMode;
  const _GridCard({required this.tutorial, required this.isDarkMode});

  @override
  Widget build(BuildContext context) {
    final topicRule = matchedTopicRuleFor(tutorial.tags);
    final topicLabel =
        topicRule?.label ??
        (tutorial.tags.isNotEmpty ? tutorial.tags.first : null);

    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () => _openTutorial(context, tutorial),
      child: Container(
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Theme.of(context).dividerColor, width: 0.5),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AspectRatio(
              aspectRatio: 1,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  (tutorial.coverImage?.isNotEmpty ?? false)
                      ? CachedNetworkImage(
                          imageUrl: tutorial.coverImage!,
                          fit: BoxFit.cover,
                          placeholder: (context, url) =>
                              Container(color: Theme.of(context).dividerColor),
                          errorWidget: (context, url, error) =>
                              _CoverPlaceholder(title: tutorial.title),
                        )
                      : _CoverPlaceholder(title: tutorial.title),
                  if (topicLabel != null)
                    Positioned(
                      top: 8,
                      left: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.55),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          topicLabel,
                          style: const TextStyle(
                            fontSize: 9.5,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      tutorial.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        height: 1.3,
                        color: Theme.of(context).textTheme.bodyLarge?.color,
                      ),
                    ),
                    Row(
                      children: [
                        _AuthorAvatar(
                          avatar: tutorial.avatar,
                          username: tutorial.username,
                          radius: 8,
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            tutorial.username,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 11,
                              color: Theme.of(context).textTheme.bodySmall?.color,
                            ),
                          ),
                        ),
                        Icon(
                          Icons.favorite_border,
                          size: 11,
                          color: Theme.of(context).textTheme.bodySmall?.color,
                        ),
                        const SizedBox(width: 2),
                        Text(
                          '${tutorial.likes}',
                          style: TextStyle(
                            fontSize: 10.5,
                            color: Theme.of(context).textTheme.bodySmall?.color,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

const _coverPalette = [
  (bg: Color(0xFFEEF2FF), icon: Icons.terminal, fg: Color(0xFF6366F1)),
  (bg: Color(0xFFECFDF5), icon: Icons.functions, fg: Color(0xFF16A34A)),
  (
    bg: Color(0xFFFFF7ED),
    icon: Icons.smart_toy_outlined,
    fg: Color(0xFFD97706),
  ),
  (bg: Color(0xFFFDF2F8), icon: Icons.auto_awesome, fg: Color(0xFFDB2777)),
  (bg: Color(0xFFEFF6FF), icon: Icons.grid_on, fg: Color(0xFF2563EB)),
];

class _CoverPlaceholder extends StatelessWidget {
  final String title;
  const _CoverPlaceholder({required this.title});

  @override
  Widget build(BuildContext context) {
    final entry =
        _coverPalette[title.isNotEmpty
            ? title.codeUnitAt(0) % _coverPalette.length
            : 0];
    return Container(
      color: entry.bg,
      alignment: Alignment.center,
      child: Icon(entry.icon, color: entry.fg, size: 28),
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
