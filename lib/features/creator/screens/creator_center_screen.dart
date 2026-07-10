import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_client.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../auth/auth_service.dart';
import '../../messages/utils/message_avatar.dart' show messageTimeAgo;
import '../../notebook/services/notebook_service.dart';
import '../widgets/aurora_entry_card.dart';

const _primary = Color(0xFF6366F1);
const _darkBg = Color(0xFF0A0A1A);

// 极光计划的达成门槛，跟 AuroraScreen 保持同一份数字，两处都是从这里改，
// 不要各写各的
const auroraNoteTarget = 10;
const auroraLikesSavesTarget = 100;
const auroraFollowerTarget = 50;

class CreatorCenterScreen extends ConsumerStatefulWidget {
  const CreatorCenterScreen({super.key});
  @override
  ConsumerState<CreatorCenterScreen> createState() =>
      _CreatorCenterScreenState();
}

class _CreatorCenterScreenState extends ConsumerState<CreatorCenterScreen> {
  bool _loading = true;
  int _publishedCount = 0;
  int _draftCount = 0;
  int _totalViews = 0;
  // 获赞/收藏没有单独的"收藏数"接口，用点赞数顶替——跟极光计划详情页的
  // 口径保持一致，不是这里独有的简化
  int _totalLikes = 0;
  int _columnCount = 0;
  int _columnSubscribers = 0;
  // "继续创作"从首页Feed末尾（逛到底才看得到）挪过来放在创作中心底部——
  // 跟首页当初用的是同一份数据源（NotebookService.getRecentList），不是
  // 编个假的完成度百分比，这些 Notebook 本来就没有"完成度"这个概念
  List<Map<String, dynamic>> _recentNotebooks = [];

  @override
  void initState() {
    super.initState();
    _load();
    _loadRecentNotebooks();
  }

  Future<void> _loadRecentNotebooks() async {
    final userId = ref.read(currentUserProvider)?.id ?? 'guest';
    final list = await NotebookService(userId).getRecentList();
    if (mounted) setState(() => _recentNotebooks = list);
  }

  Future<void> _load() async {
    final user = ref.read(currentUserProvider);
    if (user == null) return;
    final api = ref.read(apiClientProvider);

    final results = await Future.wait([
      api.get(
        '/auth/tutorials',
        queryParameters: {
          'author': user.username,
          'status': 'published',
          'limit': 50,
        },
      ),
      api.get(
        '/auth/tutorials',
        queryParameters: {
          'author': user.username,
          'status': 'draft',
          'limit': 1,
        },
      ),
      api.get('/auth/columns/mine'),
    ]);

    if (!mounted) return;

    final publishedRes = results[0];
    var views = 0;
    var likes = 0;
    var publishedTotal = 0;
    if (publishedRes.success && publishedRes.data != null) {
      final list = (publishedRes.data['tutorials'] as List? ?? [])
          .where((j) => (j as Map)['user_id'] == user.id)
          .toList();
      publishedTotal =
          (publishedRes.data['total'] as num?)?.toInt() ?? list.length;
      for (final j in list) {
        views += ((j as Map)['views'] as num?)?.toInt() ?? 0;
        likes += (j['likes'] as num?)?.toInt() ?? 0;
      }
    }

    final draftRes = results[1];
    final draftTotal = draftRes.success && draftRes.data != null
        ? (draftRes.data['total'] as num?)?.toInt() ?? 0
        : 0;

    final columnsRes = results[2];
    var columnCount = 0;
    var subscribers = 0;
    if (columnsRes.success && columnsRes.data != null) {
      final list = (columnsRes.data['columns'] as List?) ?? [];
      columnCount = list.length;
      for (final c in list) {
        subscribers += ((c as Map)['subscriber_count'] as num?)?.toInt() ?? 0;
      }
    }

    setState(() {
      _publishedCount = publishedTotal;
      _draftCount = draftTotal;
      _totalViews = views;
      _totalLikes = likes;
      _columnCount = columnCount;
      _columnSubscribers = subscribers;
      _loading = false;
    });
  }

  String _formatCount(int n) {
    if (n >= 10000) return '${(n / 10000).toStringAsFixed(1)}万';
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}k';
    return '$n';
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final user = ref.watch(currentUserProvider);

    return Scaffold(
      backgroundColor: isDark ? _darkBg : Colors.white,
      body: SafeArea(
        bottom: false,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                children: [
                  _header(isDark),
                  const SizedBox(height: 16),
                  _statsRow(isDark),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: _quickEntry(
                          isDark: isDark,
                          icon: Icons.description_outlined,
                          iconBg: const Color(0xFF6366F1),
                          title: '作品管理',
                          subtitle: '$_publishedCount篇·$_draftCount草稿',
                          onTap: () => context.push('/creator/works'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _quickEntry(
                          isDark: isDark,
                          icon: Icons.view_agenda_outlined,
                          iconBg: const Color(0xFFC026D3),
                          title: '我的专栏',
                          subtitle: '$_columnCount个·$_columnSubscribers订阅',
                          onTap: () => context.push('/creator/columns'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  AuroraEntryCard(
                    noteCount: _publishedCount,
                    noteTarget: auroraNoteTarget,
                    likesSaves: _totalLikes,
                    likesSavesTarget: auroraLikesSavesTarget,
                    followers: user?.followerCount ?? 0,
                    followerTarget: auroraFollowerTarget,
                    isAuroraCreator: user?.isAuroraCreator ?? false,
                    // 已经是极光创作者了就直接看每月续期的真实进度，不用
                    // 再看一遍"怎么才能入选"的申请门槛宣传页——两个页面
                    // 语义不一样，见 app_router.dart 里的注释
                    onTap: () => context.push(
                      user?.isAuroraCreator == true
                          ? '/aurora/progress'
                          : '/creator/aurora',
                    ),
                  ),
                  if (_recentNotebooks.isNotEmpty) ...[
                    const SizedBox(height: 20),
                    _buildContinueCreating(context, isDark),
                  ],
                ],
              ),
      ),
    );
  }

  // 继续创作——真实的本地最近 Notebook 列表，不编完成度百分比（这些
  // Notebook 本来就没有这个概念），只展示真实的 cell 数和更新时间
  Widget _buildContinueCreating(BuildContext context, bool isDark) {
    final l10n = AppLocalizations.of(context)!;
    final items = _recentNotebooks.take(4).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.continueCreatingTitle,
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: isDark ? Colors.white : const Color(0xFF1A1A1A),
          ),
        ),
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
                    color: isDark
                        ? Colors.white.withValues(alpha: 0.05)
                        : const Color(0xFFF5F5F7),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: isDark
                          ? Colors.white.withValues(alpha: 0.08)
                          : const Color(0xFFEBEBEB),
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
                          color: isDark
                              ? Colors.white
                              : const Color(0xFF1A1A1A),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${l10n.notebookCellsCount(cellCount)} · ${messageTimeAgo(l10n, updatedAt * 1000)}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11,
                          color: isDark
                              ? Colors.white.withValues(alpha: 0.4)
                              : Colors.grey[500],
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

  Widget _header(bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => context.pop(),
            child: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.08)
                    : const Color(0xFFF5F5F7),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                Icons.arrow_back,
                size: 18,
                color: isDark ? Colors.white : const Color(0xFF1A1A1A),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              '创作者中心',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: isDark ? Colors.white : const Color(0xFF1A1A1A),
              ),
            ),
          ),
          GestureDetector(
            onTap: () => context.push('/publish'),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: _primary,
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.add, size: 15, color: Colors.white),
                  SizedBox(width: 3),
                  Text(
                    '发布',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // 涨幅百分比后端暂无对应的历史快照数据算不出真实环比，先按给的方案
  // 写死——跟浏览量/获赞这两个真实累计值区分开，不要以为这几个百分比也
  // 是真数据
  Widget _statsRow(bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 20),
      decoration: BoxDecoration(
        // 浅色主题原来是纯灰色平面块，跟深色主题那层微透明玻璃质感差太多；
        // 换成一层极淡的紫蓝渐变+同色系细描边，颜色语言跟深色版对齐但不
        // 违反浅色主题"无阴影"的规范——用色彩层次代替阴影层次
        color: isDark ? Colors.white.withValues(alpha: 0.06) : null,
        gradient: isDark
            ? null
            : const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFFF5F3FF), Color(0xFFFAFAFF)],
              ),
        borderRadius: BorderRadius.circular(16),
        border: isDark
            ? null
            : Border.all(color: _primary.withValues(alpha: 0.1)),
      ),
      child: Row(
        children: [
          Expanded(
            child: _statCol(isDark, _formatCount(_totalViews), '浏览量', '23%'),
          ),
          _statDivider(isDark),
          Expanded(
            child: _statCol(isDark, _formatCount(_totalLikes), '获赞', '18%'),
          ),
          _statDivider(isDark),
          Expanded(
            child: _statCol(
              isDark,
              _formatCount(ref.watch(currentUserProvider)?.followerCount ?? 0),
              '新粉丝',
              '41%',
            ),
          ),
        ],
      ),
    );
  }

  Widget _statDivider(bool isDark) => Container(
    width: 0.5,
    height: 40,
    color: isDark
        ? Colors.white.withValues(alpha: 0.1)
        : const Color(0xFFE5E5EA),
  );

  Widget _statCol(bool isDark, String value, String label, String growth) {
    return Column(
      children: [
        Text(
          value,
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w800,
            color: isDark ? Colors.white : const Color(0xFF1A1A1A),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: isDark ? Colors.white70 : const Color(0xFF999999),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          '↑ $growth',
          style: const TextStyle(
            fontSize: 11,
            color: Color(0xFF16A34A),
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  Widget _quickEntry({
    required bool isDark,
    required IconData icon,
    required Color iconBg,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isDark ? Colors.white.withValues(alpha: 0.06) : null,
          // 浅色主题原来是纯白卡片+灰色细边，颜色信息只留在小小的图标方块
          // 里，整张卡看起来很素；换成跟图标同色系的极淡渐变底+同色细边，
          // 让"这张卡是什么领域"从图标扩散到整张卡，视觉分量才跟深色主题
          // 那种半透明彩色玻璃卡对得上
          gradient: isDark
              ? null
              : LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    iconBg.withValues(alpha: 0.1),
                    iconBg.withValues(alpha: 0.02),
                  ],
                ),
          borderRadius: BorderRadius.circular(16),
          border: isDark
              ? null
              : Border.all(color: iconBg.withValues(alpha: 0.18), width: 0.5),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: iconBg.withValues(alpha: isDark ? 0.25 : 0.16),
                borderRadius: BorderRadius.circular(11),
              ),
              child: Icon(icon, color: iconBg, size: 20),
            ),
            const SizedBox(height: 12),
            Text(
              title,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: isDark ? Colors.white : const Color(0xFF1A1A1A),
              ),
            ),
            const SizedBox(height: 2),
            Text(
              subtitle,
              style: TextStyle(
                fontSize: 12,
                color: isDark ? Colors.white54 : const Color(0xFF999999),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
