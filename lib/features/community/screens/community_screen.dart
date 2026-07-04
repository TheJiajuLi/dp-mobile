import 'dart:convert';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../../shared/models/tutorial_model.dart';
import '../community_provider.dart';

const _tags = ['全部', 'Python', '数据分析', '机器学习', '可视化', 'LaTeX', '统计学', '数学建模'];

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
  final _searchCtrl = TextEditingController();
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
    _searchCtrl.dispose();
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
    final state = ref.watch(communityProvider);
    final list = state.filtered;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: TextField(
                controller: _searchCtrl,
                onChanged: (v) =>
                    ref.read(communityProvider.notifier).setSearchQuery(v),
                decoration: InputDecoration(
                  hintText: '搜索教程、作者...',
                  hintStyle: const TextStyle(
                    color: AppColors.textMuted,
                    fontSize: 14,
                  ),
                  prefixIcon: const Icon(
                    Icons.search,
                    color: AppColors.textMuted,
                    size: 20,
                  ),
                  filled: true,
                  fillColor: const Color(0xFFF2F2F5),
                  contentPadding: const EdgeInsets.symmetric(vertical: 0),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
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
                            : const Color(0xFFF2F2F5),
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: Text(
                        tag,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: selected ? Colors.white : AppColors.textMuted,
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
              '加载失败：${state.error}',
              style: const TextStyle(color: AppColors.danger, fontSize: 13),
            ),
          ),
        ],
      );
    }
    if (list.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: const [
          SizedBox(height: 80),
          Center(
            child: Text('暂无教程', style: TextStyle(color: AppColors.textMuted)),
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
          border: Border.all(color: const Color(0xFFF0F0F0), width: 0.5),
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
                            style: const TextStyle(
                              fontSize: 11,
                              color: AppColors.textMuted,
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
                        style: const TextStyle(
                          fontSize: 11,
                          color: AppColors.textMuted,
                        ),
                      ),
                      const SizedBox(width: 10),
                      const Icon(
                        Icons.visibility_outlined,
                        size: 12,
                        color: AppColors.textMuted,
                      ),
                      const SizedBox(width: 3),
                      Text(
                        '${tutorial.views}',
                        style: const TextStyle(
                          fontSize: 11,
                          color: AppColors.textMuted,
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
      placeholder: (context, url) => Container(color: AppColors.border),
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
          placeholder: (context, url) => Container(color: AppColors.border),
          errorWidget: (context, url, error) => _letter(),
        ),
      ),
    );
  }
}
