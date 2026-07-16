import 'dart:convert';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_client.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/founding_badge.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../../shared/models/tutorial_model.dart';
import '../../../shared/utils/topic_badge.dart';
import '../../../shared/widgets/tutorial_block_renderer.dart'
    show inlineLatexText;
import '../../messages/utils/message_avatar.dart' show messageTimeAgo;
import '../community_provider.dart';

// 这些还是后端实际的 tag 值（用来跟 tutorial.tags 比对/筛选），只是
// 显示的时候用 _tagLabel 换成本地化文案，不能直接把这个列表本身翻译掉
const _tags = ['全部', 'Python', '数据分析', '机器学习', '可视化', 'LaTeX', '统计学', '数学建模'];

String _tagLabel(AppLocalizations l10n, String tag) => switch (tag) {
  '全部' => l10n.tagAll,
  '数据分析' => l10n.tagDataAnalysis,
  '机器学习' => l10n.tagMachineLearning,
  '可视化' => l10n.tagVisualization,
  '统计学' => l10n.tagStatistics,
  '数学建模' => l10n.tagMathModeling,
  _ => tag,
};

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

class CommunityScreen extends ConsumerStatefulWidget {
  const CommunityScreen({super.key});

  @override
  ConsumerState<CommunityScreen> createState() => _CommunityScreenState();
}

class _CommunityScreenState extends ConsumerState<CommunityScreen> {
  final _scrollCtrl = ScrollController();
  final _heroCtrl = PageController(viewportFraction: 0.88);
  int _heroPage = 0;

  // 点赞/关注在列表接口里都拿不到当前用户的初始状态（后端 /auth/tutorials
  // 和作者去重出来的推荐列表都不带 is_liked/is_following），所以这里只能
  // 本地记录"这次会话里点过的"，点击时依然是真实的 POST/DELETE 请求，
  // 只是初始状态统一按"未点"处理——跟教程详情页评论区 _displayLikes 是
  // 同一个思路
  final Set<String> _likedIds = {};
  final Set<String> _followingIds = {};

  @override
  void initState() {
    super.initState();
    _scrollCtrl.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollCtrl.removeListener(_onScroll);
    _scrollCtrl.dispose();
    _heroCtrl.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollCtrl.position.pixels >=
        _scrollCtrl.position.maxScrollExtent - 200) {
      ref.read(communityProvider.notifier).loadMore();
    }
  }

  int _displayLikes(TutorialModel t) =>
      t.likes + (_likedIds.contains(t.id) ? 1 : 0);

  Future<void> _toggleLike(TutorialModel t) async {
    final api = ref.read(apiClientProvider);
    final liked = _likedIds.contains(t.id);
    final res = liked
        ? await api.delete('/auth/tutorials/${t.id}/like')
        : await api.post('/auth/tutorials/${t.id}/like');
    if (!mounted) return;
    if (res.success) {
      setState(() {
        liked ? _likedIds.remove(t.id) : _likedIds.add(t.id);
      });
    } else {
      final l10n = AppLocalizations.of(context)!;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.actionFailedWithReason('${res.message}'))),
      );
    }
  }

  Future<void> _toggleFollow(String? userId) async {
    if (userId == null || userId.isEmpty) return;
    final api = ref.read(apiClientProvider);
    final following = _followingIds.contains(userId);
    final res = following
        ? await api.delete('/auth/users/$userId/follow')
        : await api.post('/auth/users/$userId/follow');
    if (!mounted) return;
    if (res.success) {
      setState(() {
        following ? _followingIds.remove(userId) : _followingIds.add(userId);
      });
    } else {
      final l10n = AppLocalizations.of(context)!;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.actionFailedWithReason('${res.message}'))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final state = ref.watch(communityProvider);

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(
        child: RefreshIndicator(
          color: AppColors.primary,
          onRefresh: () => ref.read(communityProvider.notifier).refresh(),
          child: _buildBody(context, l10n, state),
        ),
      ),
    );
  }

  Widget _buildBody(
    BuildContext context,
    AppLocalizations l10n,
    CommunityState state,
  ) {
    if (state.isLoading && state.tutorials.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: const [
          SizedBox(height: 120),
          Center(child: CircularProgressIndicator(color: AppColors.primary)),
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

    final list = state.filtered;
    if (list.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          const SizedBox(height: 80),
          Center(
            child: Text(
              l10n.noTutorialsYet,
              style: TextStyle(
                color: Theme.of(context).textTheme.bodySmall?.color,
              ),
            ),
          ),
        ],
      );
    }

    final heroList = list.take(5).toList();
    final feedList = list.skip(heroList.length).toList();
    final splitAt = feedList.length < 4 ? feedList.length : 4;
    final firstFeed = feedList.take(splitAt).toList();
    final restFeed = feedList.skip(splitAt).toList();
    final rankList = ([
      ...list,
    ]..sort((a, b) => b.views.compareTo(a.views))).take(5).toList();

    final seenAuthors = <String>{};
    final suggestedAuthors = <TutorialModel>[];
    for (final t in state.tutorials) {
      if (t.username.isEmpty || !seenAuthors.add(t.username)) continue;
      suggestedAuthors.add(t);
      if (suggestedAuthors.length >= 8) break;
    }

    return CustomScrollView(
      controller: _scrollCtrl,
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: [
        SliverToBoxAdapter(child: _searchBar(context, l10n)),
        SliverToBoxAdapter(child: _tabRow(context, l10n, state)),
        const SliverToBoxAdapter(child: SizedBox(height: 14)),
        if (heroList.isNotEmpty)
          SliverToBoxAdapter(child: _heroCarousel(heroList)),
        SliverToBoxAdapter(child: _hotTopics(context, l10n)),
        if (suggestedAuthors.isNotEmpty)
          SliverToBoxAdapter(
            child: _suggestedFollow(context, suggestedAuthors),
          ),
        SliverToBoxAdapter(child: _sectionHeader(context, '为你推荐')),
        SliverList.builder(
          itemCount: firstFeed.length,
          itemBuilder: (context, index) =>
              _contentCard(context, l10n, firstFeed[index]),
        ),
        if (rankList.isNotEmpty)
          SliverToBoxAdapter(child: _newsRanking(context, rankList)),
        if (restFeed.isNotEmpty) ...[
          SliverToBoxAdapter(child: _sectionHeader(context, '更多推荐')),
          SliverList.builder(
            itemCount: restFeed.length,
            itemBuilder: (context, index) =>
                _contentCard(context, l10n, restFeed[index]),
          ),
        ],
        SliverToBoxAdapter(
          child: SizedBox(
            height: 32,
            child: state.isLoadingMore
                ? const Center(
                    child: SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppColors.primary,
                      ),
                    ),
                  )
                : null,
          ),
        ),
      ],
    );
  }

  Widget _searchBar(BuildContext context, AppLocalizations l10n) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      // 这里改成纯跳转入口，不再是 inline 实时过滤——真正的搜索
      // 交互（联想词/历史/热门话题/分类结果）统一放到 /search 页
      child: GestureDetector(
        onTap: () => context.push('/search'),
        child: Container(
          height: 44,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: Theme.of(context).inputDecorationTheme.fillColor,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Icon(
                Icons.search,
                color: Theme.of(context).textTheme.bodySmall?.color,
                size: 20,
              ),
              const SizedBox(width: 8),
              Text(
                l10n.searchTutorialsHint,
                style: TextStyle(
                  color: Theme.of(context).textTheme.bodySmall?.color,
                  fontSize: 14,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _tabRow(
    BuildContext context,
    AppLocalizations l10n,
    CommunityState state,
  ) {
    return SizedBox(
      height: 42,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        itemCount: _tags.length,
        itemBuilder: (context, index) {
          final tag = _tags[index];
          final selected = state.selectedTag == tag;
          return GestureDetector(
            onTap: () => ref.read(communityProvider.notifier).setTag(tag),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              alignment: Alignment.center,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    _tagLabel(l10n, tag),
                    style: TextStyle(
                      fontSize: selected ? 15 : 14,
                      fontWeight: selected ? FontWeight.w800 : FontWeight.w500,
                      color: selected
                          ? Theme.of(context).textTheme.bodyLarge?.color
                          : Theme.of(context).textTheme.bodySmall?.color,
                    ),
                  ),
                  const SizedBox(height: 6),
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    height: 3,
                    width: selected ? 16 : 0,
                    decoration: BoxDecoration(
                      color: AppColors.primary,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _heroCarousel(List<TutorialModel> heroList) {
    return Column(
      children: [
        SizedBox(
          height: 208,
          child: PageView.builder(
            controller: _heroCtrl,
            itemCount: heroList.length,
            onPageChanged: (i) => setState(() => _heroPage = i),
            itemBuilder: (context, index) => Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: _heroCard(context, heroList[index]),
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
                      ? AppColors.primary
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

  Widget _heroCard(BuildContext context, TutorialModel t) {
    final rule = matchedTopicRuleFor(t.tags);
    return GestureDetector(
      onTap: () => context.push('/tutorial/${t.id}'),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (t.coverImage?.isNotEmpty == true)
              CachedNetworkImage(
                imageUrl: t.coverImage!,
                fit: BoxFit.cover,
                errorWidget: (context, url, error) => _heroGradientBg(rule),
              )
            else
              _heroGradientBg(rule),
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
                        size: 18,
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

  Widget _heroGradientBg(TopicBadgeRule? rule) {
    final base = rule?.fg ?? AppColors.primary;
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

  Widget _hotTopics(BuildContext context, AppLocalizations l10n) {
    final topics = _tags.skip(1).toList();
    return SizedBox(
      height: 34,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: topics.length,
        separatorBuilder: (context, index) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final tag = topics[index];
          return GestureDetector(
            onTap: () => ref.read(communityProvider.notifier).setTag(tag),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 13),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: Theme.of(context).inputDecorationTheme.fillColor,
                borderRadius: BorderRadius.circular(17),
              ),
              child: Text(
                '# ${_tagLabel(l10n, tag)}',
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: Theme.of(context).textTheme.bodySmall?.color,
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _suggestedFollow(BuildContext context, List<TutorialModel> authors) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionHeader(context, '推荐关注'),
        SizedBox(
          height: 156,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: authors.length,
            separatorBuilder: (context, index) => const SizedBox(width: 10),
            itemBuilder: (context, index) {
              final t = authors[index];
              final following = _followingIds.contains(t.userId);
              final category = topicCategoryLabelFor(t.tags);
              return Container(
                width: 130,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Theme.of(context).cardColor,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: Theme.of(context).brightness == Brightness.dark
                      ? null
                      : [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.03),
                            blurRadius: 10,
                            offset: const Offset(0, 3),
                          ),
                        ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    GestureDetector(
                      onTap: t.username.isEmpty
                          ? null
                          : () => context.push('/users/${t.username}'),
                      child: _AuthorAvatar(
                        avatar: t.avatar,
                        username: t.username,
                        isFoundingCreator: t.isFoundingCreator,
                        size: 40,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      t.username,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (category != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        category,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 10.5,
                          color: Theme.of(context).textTheme.bodySmall?.color,
                        ),
                      ),
                    ],
                    const Spacer(),
                    SizedBox(
                      width: double.infinity,
                      height: 27,
                      child: OutlinedButton(
                        onPressed: () => _toggleFollow(t.userId),
                        style: OutlinedButton.styleFrom(
                          padding: EdgeInsets.zero,
                          backgroundColor: following ? null : AppColors.primary,
                          side: BorderSide(
                            color: following
                                ? Theme.of(context).dividerColor
                                : AppColors.primary,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(99),
                          ),
                        ),
                        child: Text(
                          following ? '已关注' : '关注',
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600,
                            color: following
                                ? Theme.of(context).textTheme.bodySmall?.color
                                : Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _sectionHeader(BuildContext context, String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 10),
      child: Text(
        title,
        style: const TextStyle(fontSize: 16.5, fontWeight: FontWeight.w800),
      ),
    );
  }

  Widget _contentCard(
    BuildContext context,
    AppLocalizations l10n,
    TutorialModel t,
  ) {
    final badgeStyle = topicBadgeStyleFor(
      t.tags.isNotEmpty ? t.tags.first : '',
    );
    final category = topicCategoryLabelFor(t.tags);
    final liked = _likedIds.contains(t.id);

    return GestureDetector(
      onTap: () => context.push('/tutorial/${t.id}'),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: SizedBox(
                width: 104,
                height: 88,
                child: _CoverImage(coverImage: t.coverImage, title: t.title),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (category != null)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: badgeStyle.$1,
                        borderRadius: BorderRadius.circular(99),
                      ),
                      child: Text(
                        category,
                        style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w700,
                          color: badgeStyle.$2,
                        ),
                      ),
                    ),
                  const SizedBox(height: 6),
                  Text(
                    t.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      height: 1.3,
                      color: Theme.of(context).textTheme.bodyLarge?.color,
                    ),
                  ),
                  if (t.summary?.isNotEmpty == true) ...[
                    const SizedBox(height: 4),
                    // 摘要跟信息流卡片一致走 inlineLatexText，$…$ 行内公式渲染
                    inlineLatexText(
                      t.summary!,
                      TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).textTheme.bodySmall?.color,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      _AuthorAvatar(
                        avatar: t.avatar,
                        username: t.username,
                        isFoundingCreator: t.isFoundingCreator,
                        size: 16,
                      ),
                      const SizedBox(width: 5),
                      Flexible(
                        child: Text(
                          t.username,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11,
                            color: Theme.of(context).textTheme.bodySmall?.color,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        messageTimeAgo(l10n, t.createdAt),
                        style: TextStyle(
                          fontSize: 11,
                          color: Theme.of(context).textTheme.bodySmall?.color,
                        ),
                      ),
                      const Spacer(),
                      GestureDetector(
                        onTap: () => _toggleLike(t),
                        behavior: HitTestBehavior.opaque,
                        child: Row(
                          children: [
                            Icon(
                              liked ? Icons.favorite : Icons.favorite_outline,
                              size: 14,
                              color: liked
                                  ? const Color(0xFFEF4444)
                                  : Theme.of(
                                      context,
                                    ).textTheme.bodySmall?.color,
                            ),
                            const SizedBox(width: 3),
                            Text(
                              '${_displayLikes(t)}',
                              style: TextStyle(
                                fontSize: 11,
                                color: Theme.of(
                                  context,
                                ).textTheme.bodySmall?.color,
                              ),
                            ),
                          ],
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

  Widget _newsRanking(BuildContext context, List<TutorialModel> rankList) {
    const rankColors = [
      Color(0xFFF43F5E),
      Color(0xFFF59E0B),
      Color(0xFF10B981),
    ];
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 4),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(
                Icons.local_fire_department,
                size: 17,
                color: Color(0xFFF59E0B),
              ),
              SizedBox(width: 6),
              Text(
                '今日热度榜',
                style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.w800),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ...List.generate(rankList.length, (index) {
            final t = rankList[index];
            return GestureDetector(
              onTap: () => context.push('/tutorial/${t.id}'),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 7),
                child: Row(
                  children: [
                    SizedBox(
                      width: 18,
                      child: Text(
                        '${index + 1}',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          color: index < 3
                              ? rankColors[index]
                              : Theme.of(context).textTheme.bodySmall?.color,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        t.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 13),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '${t.views}',
                      style: TextStyle(
                        fontSize: 11.5,
                        color: Theme.of(context).textTheme.bodySmall?.color,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }),
        ],
      ),
    );
  }
}

class _CoverImage extends StatelessWidget {
  final String? coverImage;
  final String title;

  const _CoverImage({required this.coverImage, required this.title});

  @override
  Widget build(BuildContext context) {
    if (coverImage == null || coverImage!.isEmpty) {
      return _CoverPlaceholder(title: title);
    }
    return CachedNetworkImage(
      imageUrl: coverImage!,
      fit: BoxFit.cover,
      width: double.infinity,
      height: double.infinity,
      placeholder: (context, url) =>
          Container(color: Theme.of(context).dividerColor),
      errorWidget: (context, url, error) => _CoverPlaceholder(title: title),
    );
  }
}

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
      child: Icon(entry.icon, color: entry.fg, size: 32),
    );
  }
}

class _AuthorAvatar extends StatelessWidget {
  final String? avatar;
  final String username;
  final bool isFoundingCreator;
  final double size;

  const _AuthorAvatar({
    required this.avatar,
    required this.username,
    this.isFoundingCreator = false,
    this.size = 16,
  });

  Widget _letter() => CircleAvatar(
    radius: size / 2,
    backgroundColor: AppColors.primary.withValues(alpha: 0.15),
    child: Text(
      username.isNotEmpty ? username.substring(0, 1) : '?',
      style: TextStyle(
        fontSize: size * 0.56,
        fontWeight: FontWeight.w700,
        color: AppColors.primary,
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    return FoundingAvatarRing(
      isFoundingCreator: isFoundingCreator,
      size: size,
      child: _content(context),
    );
  }

  Widget _content(BuildContext context) {
    if (avatar == null || avatar!.isEmpty) return _letter();

    if (avatar!.startsWith('data:image')) {
      try {
        final raw = avatar!.split(',').last;
        return CircleAvatar(
          radius: size / 2,
          backgroundImage: MemoryImage(base64Decode(raw)),
        );
      } catch (_) {
        return _letter();
      }
    }

    return ClipOval(
      child: SizedBox(
        width: size,
        height: size,
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
