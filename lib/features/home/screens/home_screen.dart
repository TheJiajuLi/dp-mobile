import 'dart:convert';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../../shared/models/tutorial_model.dart';
import '../../../shared/utils/topic_badge.dart';
import '../../auth/auth_service.dart';
import '../../messages/screens/messages_screen.dart' show timeAgo;
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

enum _EntryStatus { live, comingSoon, stayTuned }

String _statusLabel(AppLocalizations l10n, _EntryStatus status) =>
    switch (status) {
      _EntryStatus.live => l10n.statusLive,
      _EntryStatus.comingSoon => l10n.statusComingSoon,
      _EntryStatus.stayTuned => l10n.statusStayTuned,
    };

enum _AppId { notebook, aria, grid, visualization, mathModeling, more }

String _appName(AppLocalizations l10n, _AppId id) => switch (id) {
  _AppId.notebook => 'Power Notebook',
  _AppId.aria => l10n.appAriaAssistant,
  _AppId.grid => l10n.appDataGrid,
  _AppId.visualization => l10n.appVisualizationFactory,
  _AppId.mathModeling => l10n.appMathModeling,
  _AppId.more => l10n.appMoreComingSoon,
};

class _AppEntry {
  final _AppId id;
  final IconData icon;
  final Color color;
  final _EntryStatus status;
  final String? route;
  final bool usePush;

  const _AppEntry({
    required this.id,
    required this.icon,
    required this.color,
    required this.status,
    this.route,
    this.usePush = false,
  });
}

// 这套 app 入口宫格是首页原有的功能入口（Notebook/ARIA 等），这次重设计
// 首页视觉语言时保留在首页——ARIA 目前只有这一个入口，直接拿掉的话这个
// 功能在全App里就再也点不进去了。后续计划挪到"社区"页，这次先不动
const _appEntries = <_AppEntry>[
  _AppEntry(
    id: _AppId.notebook,
    icon: Icons.code,
    color: Color(0xFF6366F1),
    status: _EntryStatus.live,
    route: '/notebook',
    usePush: true,
  ),
  _AppEntry(
    id: _AppId.aria,
    icon: Icons.auto_awesome,
    color: Color(0xFF16A34A),
    status: _EntryStatus.live,
    route: '/aria',
    usePush: true,
  ),
  _AppEntry(
    id: _AppId.grid,
    icon: Icons.grid_on,
    color: Color(0xFF2563EB),
    status: _EntryStatus.comingSoon,
  ),
  _AppEntry(
    id: _AppId.visualization,
    icon: Icons.bar_chart,
    color: Color(0xFFD97706),
    status: _EntryStatus.comingSoon,
  ),
  _AppEntry(
    id: _AppId.mathModeling,
    icon: Icons.functions,
    color: Color(0xFFC026D3),
    status: _EntryStatus.comingSoon,
  ),
  _AppEntry(
    id: _AppId.more,
    icon: Icons.more_horiz,
    color: Color(0xFF8E8E93),
    status: _EntryStatus.stayTuned,
  ),
];

// Feed 里三种卡片怎么混排，不需要用户自己选、也不需要后端打标记，纯前端
// 按下标规则自动分配：
//   - 固定在渲染出的第 3 张卡（rows.length==2 时）插入本周专题卡，不消耗
//     tutorial
//   - 原始下标 i%5==0 且带封面图 → 大图头条
//   - 原始下标 i%8==0 且后面还有一条 → 双列小卡（连续消耗两条）
//   - 其余 → 文字+缩略图
sealed class _FeedRow {
  const _FeedRow();
}

class _FeatureRow extends _FeedRow {
  const _FeatureRow();
}

class _HeroRow extends _FeedRow {
  final TutorialModel tutorial;
  const _HeroRow(this.tutorial);
}

class _MiniRow extends _FeedRow {
  final TutorialModel a;
  final TutorialModel b;
  const _MiniRow(this.a, this.b);
}

class _TextRow extends _FeedRow {
  final TutorialModel tutorial;
  const _TextRow(this.tutorial);
}

List<_FeedRow> _buildRows(List<TutorialModel> tutorials) {
  final rows = <_FeedRow>[];
  var i = 0;
  var insertedFeature = false;
  while (i < tutorials.length) {
    if (!insertedFeature && rows.length == 2) {
      rows.add(const _FeatureRow());
      insertedFeature = true;
      continue;
    }
    final t = tutorials[i];
    if (i % 5 == 0 && (t.coverImage?.isNotEmpty ?? false)) {
      rows.add(_HeroRow(t));
      i += 1;
    } else if (i % 8 == 0 && i + 1 < tutorials.length) {
      rows.add(_MiniRow(tutorials[i], tutorials[i + 1]));
      i += 2;
    } else {
      rows.add(_TextRow(t));
      i += 1;
    }
  }
  return rows;
}

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  final _scrollCtrl = ScrollController();
  // "继续创作"用的是本地最近 Notebook 列表（NotebookService.getRecentList，
  // 跟个人主页 Notebook tab 同一份数据源），不是编个假的完成度百分比——
  // 这些 Notebook 本来就没有"完成度"这个概念，只有真实的 cell 数/更新时间
  List<Map<String, dynamic>> _recentNotebooks = [];
  // "换一换"——本地重新洗一次牌，不是重新拉接口；换分类之后旧的洗牌顺序
  // 就不对了，靠 _shuffleCategory 记住是对着哪个分类洗的，分类一变就失效
  List<TutorialModel>? _shuffleSeed;
  String? _shuffleCategory;

  @override
  void initState() {
    super.initState();
    _scrollCtrl.addListener(_onScroll);
    _loadRecentNotebooks();
  }

  @override
  void dispose() {
    _scrollCtrl.removeListener(_onScroll);
    _scrollCtrl.dispose();
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

  void _onEntryTap(BuildContext context, _AppEntry entry) {
    if (entry.route != null) {
      if (entry.usePush) {
        context.push(entry.route!);
      } else {
        context.go(entry.route!);
      }
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context)!.comingSoonStayTuned),
        ),
      );
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

  // 本地重新洗一次牌，不重新拉接口；换了分类之后旧洗牌顺序对不上新分类
  // 的结果，直接失效退回接口原始顺序
  List<TutorialModel> _displayTutorials(HomeFeedState state) {
    if (_shuffleCategory != state.selectedCategory) return state.filtered;
    return _shuffleSeed ?? state.filtered;
  }

  void _onShuffleTap(HomeFeedState state) {
    setState(() {
      _shuffleCategory = state.selectedCategory;
      _shuffleSeed = List.of(state.filtered)..shuffle();
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final state = ref.watch(homeFeedProvider);
    final rows = _buildRows(_displayTutorials(state));
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
                child: _buildBody(context, l10n, state, rows, isDarkMode),
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
    List<_FeedRow> rows,
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

    // 前面几段固定区块（入口宫格/继续创作/热门话题/推荐文章标题）先拼成
    // 一个 widget 列表，后面 Feed 卡片行接着往下排——比手动算好几段偏移量
    // 简单可靠，加/减一段不用重新核对下标
    final prefixWidgets = <Widget>[
      _buildAppGrid(context, l10n),
      if (_recentNotebooks.isNotEmpty) ...[
        _buildContinueCreating(context, l10n, isDarkMode),
        const SizedBox(height: 20),
      ],
      if (_buildTrendingTopics(context, l10n, state, isDarkMode)
          case final topics?) ...[
        topics,
        const SizedBox(height: 20),
      ],
      _buildRecommendedHeader(context, l10n, state),
      const SizedBox(height: 10),
    ];

    final showEmpty = rows.isEmpty;
    final itemCount =
        prefixWidgets.length +
        (showEmpty ? 1 : rows.length) +
        (state.isLoadingMore ? 1 : 0);

    return ListView.builder(
      controller: _scrollCtrl,
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      physics: const AlwaysScrollableScrollPhysics(),
      itemCount: itemCount,
      itemBuilder: (context, index) {
        if (index < prefixWidgets.length) return prefixWidgets[index];
        final rowIndex = index - prefixWidgets.length;
        if (showEmpty) {
          return Padding(
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
          );
        }
        if (rowIndex < rows.length) {
          return _buildRow(context, l10n, rows[rowIndex], isDarkMode);
        }
        return const Padding(
          padding: EdgeInsets.symmetric(vertical: 16),
          child: Center(
            child: SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(color: _primary, strokeWidth: 2),
            ),
          ),
        );
      },
    );
  }

  Widget _buildAppGrid(BuildContext context, AppLocalizations l10n) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: _appEntries.length,
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          mainAxisSpacing: 14,
          crossAxisSpacing: 8,
          childAspectRatio: 0.95,
        ),
        itemBuilder: (context, index) {
          final entry = _appEntries[index];
          return _AppEntryCard(
            entry: entry,
            onTap: () => _onEntryTap(context, entry),
          );
        },
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
                        '${l10n.notebookCellsCount(cellCount)} · ${timeAgo(l10n, updatedAt * 1000)}',
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

  // 热门话题——真实统计当前已加载教程里的标签出现次数（不是后端聚合
  // 总数，后端目前没有这个接口），取频次最高的几个；数量级会比"全站
  // 总量"小很多，但至少是真的，不编个好看的假数字
  Widget? _buildTrendingTopics(
    BuildContext context,
    AppLocalizations l10n,
    HomeFeedState state,
    bool isDarkMode,
  ) {
    final tagCounts = <String, int>{};
    for (final t in state.tutorials) {
      for (final tag in t.tags) {
        if (tag.isEmpty) continue;
        tagCounts[tag] = (tagCounts[tag] ?? 0) + 1;
      }
    }
    if (tagCounts.isEmpty) return null;
    final sorted = tagCounts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final top = sorted.take(8).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionHeader(title: l10n.trendingTopicsTitle),
        const SizedBox(height: 10),
        SizedBox(
          height: 64,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: top.length,
            separatorBuilder: (_, _) => const SizedBox(width: 10),
            itemBuilder: (context, index) {
              final tag = top[index].key;
              final count = top[index].value;
              final style = topicBadgeStyleFor(tag);
              return GestureDetector(
                onTap: () =>
                    context.push('/search?q=${Uri.encodeComponent(tag)}'),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: Theme.of(context).cardColor,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: Theme.of(context).dividerColor,
                      width: 0.5,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 30,
                        height: 30,
                        decoration: BoxDecoration(
                          color: style.$1,
                          borderRadius: BorderRadius.circular(9),
                        ),
                        child: Icon(
                          Icons.tag_rounded,
                          size: 15,
                          color: style.$2,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            tag,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: Theme.of(
                                context,
                              ).textTheme.bodyLarge?.color,
                            ),
                          ),
                          Text(
                            l10n.articlesCountWithValue(count),
                            style: TextStyle(
                              fontSize: 10,
                              color: Theme.of(
                                context,
                              ).textTheme.bodySmall?.color,
                            ),
                          ),
                        ],
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
    return _SectionHeader(
      title: l10n.recommendedArticlesTitle,
      action: state.filtered.length > 1
          ? (label: l10n.shuffleAction, onTap: () => _onShuffleTap(state))
          : null,
    );
  }

  Widget _buildRow(
    BuildContext context,
    AppLocalizations l10n,
    _FeedRow row,
    bool isDarkMode,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: switch (row) {
        _FeatureRow() => _FeatureCard(l10n: l10n),
        _HeroRow(:final tutorial) => _HeroCard(
          tutorial: tutorial,
          isDarkMode: isDarkMode,
        ),
        _MiniRow(:final a, :final b) => _MiniRowCards(
          a: a,
          b: b,
          isDarkMode: isDarkMode,
        ),
        _TextRow(:final tutorial) => _TextCard(
          tutorial: tutorial,
          isDarkMode: isDarkMode,
        ),
      },
    );
  }
}

void _openTutorial(BuildContext context, TutorialModel t) {
  context.push('/tutorial/${t.id}');
}

// 各段小标题统一样式——继续创作/热门话题/推荐文章 三段都用这个，右侧
// action 是可选的一个文字按钮（推荐文章的"换一换"），大多数段不需要
class _SectionHeader extends StatelessWidget {
  final String title;
  final ({String label, VoidCallback onTap})? action;
  const _SectionHeader({required this.title, this.action});

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
        const Spacer(),
        if (action != null)
          GestureDetector(
            onTap: action!.onTap,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  action!.label,
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).textTheme.bodySmall?.color,
                  ),
                ),
                Icon(
                  Icons.refresh_rounded,
                  size: 14,
                  color: Theme.of(context).textTheme.bodySmall?.color,
                ),
              ],
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

// 工具入口宫格——一线产品那种更宽松、更"确信"的视觉语言：大一号的浅色
// 圆角图标块 + 图标本身也更大，不再靠一个圆点去标"上没上线"（一排排
// 圆点反而显得没自信/像半成品），未上线的入口整体调低透明度就够直观，
// 具体状态文案还是靠长按 Tooltip
class _AppEntryCard extends StatelessWidget {
  final _AppEntry entry;
  final VoidCallback onTap;

  const _AppEntryCard({required this.entry, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final live = entry.status == _EntryStatus.live;
    return InkWell(
      borderRadius: BorderRadius.circular(AppRadius.md),
      onTap: onTap,
      child: Tooltip(
        message:
            '${_appName(l10n, entry.id)} · ${_statusLabel(l10n, entry.status)}',
        child: Opacity(
          opacity: live ? 1 : 0.55,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: entry.color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(entry.icon, color: entry.color, size: 24),
              ),
              const SizedBox(height: 8),
              Text(
                _appName(l10n, entry.id),
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Theme.of(context).textTheme.bodyLarge?.color,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// 本周专题——目前是纯前端 hardcode 的展示卡，后端还没有专题相关的接口，
// 「进入专题」先给一个"即将上线"占位，不接不存在的路由
class _FeatureCard extends StatelessWidget {
  final AppLocalizations l10n;
  const _FeatureCard({required this.l10n});

  int get _weekNumber {
    final now = DateTime.now();
    final startOfYear = DateTime(now.year, 1, 1);
    return (now.difference(startOfYear).inDays / 7).ceil().clamp(1, 53);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              l10n.weeklyTopicBadge(_weekNumber),
              style: const TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: Colors.white70,
                letterSpacing: 0.5,
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            l10n.weeklyTopicTitle,
            style: const TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w700,
              color: Colors.white,
              height: 1.3,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            l10n.weeklyTopicSummary,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 13,
              color: Colors.white60,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Text(
                l10n.articlesCountWithValue(12),
                style: const TextStyle(fontSize: 12, color: Colors.white54),
              ),
              const SizedBox(width: 12),
              Text(
                l10n.readCountWithValue('8.4k'),
                style: const TextStyle(fontSize: 12, color: Colors.white54),
              ),
              const Spacer(),
              GestureDetector(
                onTap: () => ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(l10n.comingSoonStayTuned)),
                ),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: _primary,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    l10n.enterTopicAction,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// 大图头条——只有带封面图的教程才会被分配到这种卡（见 _buildRows），
// 没封面图的教程走 _TextCard，不用渐变占位假装有封面
class _HeroCard extends StatelessWidget {
  final TutorialModel tutorial;
  final bool isDarkMode;
  const _HeroCard({required this.tutorial, required this.isDarkMode});

  @override
  Widget build(BuildContext context) {
    final topicRule = matchedTopicRuleFor(tutorial.tags);
    final topicLabel =
        topicRule?.label ??
        (tutorial.tags.isNotEmpty ? tutorial.tags.first : null);

    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () => _openTutorial(context, tutorial),
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
              height: 160,
              width: double.infinity,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  CachedNetworkImage(
                    imageUrl: tutorial.coverImage!,
                    fit: BoxFit.cover,
                    placeholder: (context, url) =>
                        Container(color: Theme.of(context).dividerColor),
                    errorWidget: (context, url, error) =>
                        _CoverPlaceholder(title: tutorial.title),
                  ),
                  if (topicLabel != null)
                    Positioned(
                      top: 10,
                      left: 10,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.65),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          topicLabel,
                          style: const TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    tutorial.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      height: 1.4,
                      color: Theme.of(context).textTheme.bodyLarge?.color,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      _AuthorAvatar(
                        avatar: tutorial.avatar,
                        username: tutorial.username,
                        radius: 9,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          tutorial.username,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            color: Theme.of(context).textTheme.bodySmall?.color,
                          ),
                        ),
                      ),
                      Text(
                        timeAgo(
                          AppLocalizations.of(context)!,
                          tutorial.createdAt,
                        ),
                        style: TextStyle(
                          fontSize: 11,
                          color: Theme.of(context).textTheme.bodySmall?.color,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Icon(
                        Icons.favorite_border,
                        size: 13,
                        color: Theme.of(context).textTheme.bodySmall?.color,
                      ),
                      const SizedBox(width: 3),
                      Text(
                        '${tutorial.likes}',
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

// 文字+缩略图——Feed 的主力卡片，没有封面图的教程也走这条（右侧缩略图
// 换成话题色渐变占位，不会因为没图就整卡看起来像坏掉了）
class _TextCard extends StatelessWidget {
  final TutorialModel tutorial;
  final bool isDarkMode;
  const _TextCard({required this.tutorial, required this.isDarkMode});

  @override
  Widget build(BuildContext context) {
    final topicRule = matchedTopicRuleFor(tutorial.tags);
    final topicLabel =
        topicRule?.label ??
        (tutorial.tags.isNotEmpty ? tutorial.tags.first : null);
    final badgeBg = topicRule?.bg ?? topicBadgeDefault.bg;
    final badgeFg = topicRule?.fg ?? topicBadgeDefault.fg;

    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () => _openTutorial(context, tutorial),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Theme.of(context).dividerColor, width: 0.5),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (topicLabel != null)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: badgeBg,
                        borderRadius: BorderRadius.circular(5),
                      ),
                      child: Text(
                        topicLabel,
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: badgeFg,
                        ),
                      ),
                    ),
                  const SizedBox(height: 6),
                  Text(
                    tutorial.title,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      height: 1.4,
                      color: Theme.of(context).textTheme.bodyLarge?.color,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      _AuthorAvatar(
                        avatar: tutorial.avatar,
                        username: tutorial.username,
                        radius: 8,
                      ),
                      const SizedBox(width: 5),
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
                      const SizedBox(width: 6),
                      Icon(
                        Icons.favorite_border,
                        size: 12,
                        color: Theme.of(context).textTheme.bodySmall?.color,
                      ),
                      const SizedBox(width: 3),
                      Text(
                        '${tutorial.likes}',
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
            const SizedBox(width: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: SizedBox(
                width: 72,
                height: 72,
                child: (tutorial.coverImage?.isNotEmpty ?? false)
                    ? CachedNetworkImage(
                        imageUrl: tutorial.coverImage!,
                        fit: BoxFit.cover,
                        placeholder: (context, url) =>
                            Container(color: Theme.of(context).dividerColor),
                        errorWidget: (context, url, error) =>
                            _CoverPlaceholder(title: tutorial.title),
                      )
                    : _CoverPlaceholder(title: tutorial.title),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// 双列小卡——一次渲染两条，缩略图矮一些（90px），标题最多两行
class _MiniRowCards extends StatelessWidget {
  final TutorialModel a;
  final TutorialModel b;
  final bool isDarkMode;
  const _MiniRowCards({
    required this.a,
    required this.b,
    required this.isDarkMode,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: _MiniCard(tutorial: a)),
        const SizedBox(width: 12),
        Expanded(child: _MiniCard(tutorial: b)),
      ],
    );
  }
}

class _MiniCard extends StatelessWidget {
  final TutorialModel tutorial;
  const _MiniCard({required this.tutorial});

  @override
  Widget build(BuildContext context) {
    final topicRule = matchedTopicRuleFor(tutorial.tags);
    final topicLabel =
        topicRule?.label ??
        (tutorial.tags.isNotEmpty ? tutorial.tags.first : null);
    final badgeBg = topicRule?.bg ?? topicBadgeDefault.bg;
    final badgeFg = topicRule?.fg ?? topicBadgeDefault.fg;

    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () => _openTutorial(context, tutorial),
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
              height: 90,
              width: double.infinity,
              child: (tutorial.coverImage?.isNotEmpty ?? false)
                  ? CachedNetworkImage(
                      imageUrl: tutorial.coverImage!,
                      fit: BoxFit.cover,
                      placeholder: (context, url) =>
                          Container(color: Theme.of(context).dividerColor),
                      errorWidget: (context, url, error) =>
                          _CoverPlaceholder(title: tutorial.title),
                    )
                  : _CoverPlaceholder(title: tutorial.title),
            ),
            Padding(
              padding: const EdgeInsets.all(8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (topicLabel != null)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: badgeBg,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        topicLabel,
                        style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w600,
                          color: badgeFg,
                        ),
                      ),
                    ),
                  const SizedBox(height: 5),
                  Text(
                    tutorial.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      height: 1.3,
                      color: Theme.of(context).textTheme.bodyLarge?.color,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Row(
                    children: [
                      Icon(
                        Icons.favorite_border,
                        size: 11,
                        color: Theme.of(context).textTheme.bodySmall?.color,
                      ),
                      const SizedBox(width: 3),
                      Text(
                        '${tutorial.likes}',
                        style: TextStyle(
                          fontSize: 10,
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
  const _AuthorAvatar({
    required this.avatar,
    required this.username,
    this.radius = 9,
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
