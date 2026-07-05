import 'dart:convert';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../../shared/models/tutorial_model.dart';
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

  @override
  void initState() {
    super.initState();
    _scrollCtrl.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollCtrl.removeListener(_onScroll);
    _scrollCtrl.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollCtrl.position.pixels >=
        _scrollCtrl.position.maxScrollExtent - 200) {
      ref.read(communityProvider.notifier).loadMore();
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final state = ref.watch(communityProvider);
    final list = state.filtered;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
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
            ),
            SizedBox(
              height: 36,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: _tags.length,
                separatorBuilder: (context, index) => const SizedBox(width: 8),
                itemBuilder: (context, index) {
                  final tag = _tags[index];
                  final selected = state.selectedTag == tag;
                  return GestureDetector(
                    onTap: () =>
                        ref.read(communityProvider.notifier).setTag(tag),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: selected
                            ? AppColors.primary
                            : Theme.of(context).inputDecorationTheme.fillColor,
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: Text(
                        _tagLabel(l10n, tag),
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: selected
                              ? Colors.white
                              : Theme.of(context).textTheme.bodySmall?.color,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: RefreshIndicator(
                color: AppColors.primary,
                onRefresh: () => ref.read(communityProvider.notifier).refresh(),
                child: _buildBody(context, state, list),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(
    BuildContext context,
    CommunityState state,
    List<TutorialModel> list,
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
              AppLocalizations.of(
                context,
              )!.loadFailedWithReason('${state.error}'),
              style: const TextStyle(color: AppColors.danger, fontSize: 13),
            ),
          ),
        ],
      );
    }
    if (list.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          const SizedBox(height: 80),
          Center(
            child: Text(
              AppLocalizations.of(context)!.noTutorialsYet,
              style: TextStyle(
                color: Theme.of(context).textTheme.bodySmall?.color,
              ),
            ),
          ),
        ],
      );
    }
    return GridView.builder(
      controller: _scrollCtrl,
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      physics: const AlwaysScrollableScrollPhysics(),
      itemCount: list.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        childAspectRatio: 0.78,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
      ),
      itemBuilder: (context, index) {
        final tutorial = list[index];
        return _TutorialCard(
          tutorial: tutorial,
          onTap: () => context.push('/tutorial/${tutorial.id}'),
        );
      },
    );
  }
}

class _TutorialCard extends StatelessWidget {
  final TutorialModel tutorial;
  final VoidCallback onTap;

  const _TutorialCard({required this.tutorial, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Theme.of(context).dividerColor, width: 0.5),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              height: 110,
              width: double.infinity,
              child: _CoverImage(
                coverImage: tutorial.coverImage,
                title: tutorial.title,
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    tutorial.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Theme.of(context).textTheme.bodyLarge?.color,
                      height: 1.3,
                    ),
                  ),
                  const SizedBox(height: 8),
                  GestureDetector(
                    onTap: tutorial.username.isEmpty
                        ? null
                        : () => context.push('/users/${tutorial.username}'),
                    child: Row(
                      children: [
                        _AuthorAvatar(
                          avatar: tutorial.avatar,
                          username: tutorial.username,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            tutorial.username,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 11,
                              color: Theme.of(
                                context,
                              ).textTheme.bodySmall?.color,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      const Icon(
                        Icons.favorite,
                        size: 12,
                        color: Color(0xFFEF4444),
                      ),
                      const SizedBox(width: 3),
                      Text(
                        '${tutorial.likes}',
                        style: TextStyle(
                          fontSize: 11,
                          color: Theme.of(context).textTheme.bodySmall?.color,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Icon(
                        Icons.visibility_outlined,
                        size: 12,
                        color: Theme.of(context).textTheme.bodySmall?.color,
                      ),
                      const SizedBox(width: 3),
                      Text(
                        '${tutorial.views}',
                        style: TextStyle(
                          fontSize: 11,
                          color: Theme.of(context).textTheme.bodySmall?.color,
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

  const _AuthorAvatar({required this.avatar, required this.username});

  Widget _letter() => CircleAvatar(
    radius: 8,
    backgroundColor: AppColors.primary.withValues(alpha: 0.15),
    child: Text(
      username.isNotEmpty ? username.substring(0, 1) : '?',
      style: const TextStyle(
        fontSize: 9,
        fontWeight: FontWeight.w700,
        color: AppColors.primary,
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    if (avatar == null || avatar!.isEmpty) return _letter();

    if (avatar!.startsWith('data:image')) {
      try {
        final raw = avatar!.split(',').last;
        return CircleAvatar(
          radius: 8,
          backgroundImage: MemoryImage(base64Decode(raw)),
        );
      } catch (_) {
        return _letter();
      }
    }

    return ClipOval(
      child: SizedBox(
        width: 16,
        height: 16,
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
