import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_client.dart';
import '../../../shared/models/tutorial_model.dart';
import '../../../shared/utils/topic_badge.dart';
import '../../../shared/widgets/app_toast.dart';
import '../../auth/auth_service.dart';

// 创作数据详情页——只展示有真实数据源的指标。真实数据来自 GET /auth/tutorials
// （本人已发布作品）客户端聚合：浏览/获赞/收藏/分享/评论、热门排行、互动分布。
// 近7天/本月/全部 = 按作品「发布时间」过滤，统计这段时间发布的作品的累计数据。
//
// 【待后端】浏览趋势折线（需按天数据）、代码运行统计（需 run-count/成功率）目前
// 没有数据源，先占位「数据统计中」，等后端 GET /auth/creator/stats 接口就绪后接。
// 环比% 也等那个接口（需跨周期对比），暂不显示——不编假数据。
const _primary = Color(0xFF6366F1);

class CreatorStatsScreen extends ConsumerStatefulWidget {
  const CreatorStatsScreen({super.key});

  @override
  ConsumerState<CreatorStatsScreen> createState() => _CreatorStatsScreenState();
}

class _CreatorStatsScreenState extends ConsumerState<CreatorStatsScreen> {
  int _period = 1; // 0=近7天 1=本月 2=全部
  bool _loading = true;

  // 全量已发布作品（一次拉回，周期切换在客户端按 createdAt 过滤）
  List<TutorialModel> _all = [];

  @override
  void initState() {
    super.initState();
    _loadStats();
  }

  Future<void> _loadStats() async {
    final user = ref.read(currentUserProvider);
    if (user == null) {
      setState(() => _loading = false);
      return;
    }
    final res = await ref
        .read(apiClientProvider)
        .get(
          '/auth/tutorials',
          queryParameters: {
            'author': user.username,
            'status': 'published',
            'limit': 200,
          },
        );
    if (!mounted) return;
    final all = <TutorialModel>[];
    if (res.success && res.data != null) {
      all.addAll(
        (res.data['tutorials'] as List? ?? [])
            .where((j) => (j as Map)['user_id'] == user.id)
            .map((j) => TutorialModel.fromJson(Map<String, dynamic>.from(j))),
      );
    }
    setState(() {
      _all = all;
      _loading = false;
    });
  }

  // 当前周期过滤后的作品（按发布时间）。全部=不过滤
  List<TutorialModel> get _filtered {
    if (_period == 2) return _all;
    final now = DateTime.now();
    final from = _period == 0
        ? now.subtract(const Duration(days: 7)) // 近7天（滚动）
        : DateTime(now.year, now.month, 1); // 本月 1 号 00:00
    final fromMs = from.millisecondsSinceEpoch;
    return _all.where((t) => t.createdAt >= fromMs).toList();
  }

  int get _views => _filtered.fold(0, (s, t) => s + t.views);
  int get _likes => _filtered.fold(0, (s, t) => s + t.likes);
  int get _saves => _filtered.fold(0, (s, t) => s + t.saveCount);
  int get _shares => _filtered.fold(0, (s, t) => s + t.shares);
  int get _comments => _filtered.fold(0, (s, t) => s + t.commentCount);

  List<TutorialModel> get _topArticles {
    final list = [..._filtered]..sort((a, b) => b.views.compareTo(a.views));
    return list.take(4).toList();
  }

  String _formatNum(int n) {
    if (n >= 10000) return '${(n / 10000).toStringAsFixed(1)}w';
    return n.toString().replaceAllMapped(
      RegExp(r'(\d)(?=(\d{3})+$)'),
      (m) => '${m[1]},',
    );
  }

  // 总览卡副标题——诚实版：不显示环比%（无跨周期数据），只标一句周期说明
  String get _periodSub => const ['近 7 天', '本月发布', '累计数据'][_period];

  String _timeAgo(int ms) {
    final d = DateTime.now().difference(
      DateTime.fromMillisecondsSinceEpoch(ms),
    );
    if (d.inDays >= 14) return '${d.inDays ~/ 7}周前';
    if (d.inDays >= 7) return '1周前';
    if (d.inDays >= 1) return '${d.inDays}天前';
    if (d.inHours >= 1) return '${d.inHours}小时前';
    return '刚刚';
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark
        ? Theme.of(context).scaffoldBackgroundColor
        : const Color(0xFFFAFAF8);
    final card = isDark ? const Color(0xFF17171F) : Colors.white;
    final border = isDark
        ? Colors.white.withValues(alpha: 0.06)
        : const Color(0xFFEDEDE9);
    final ink = isDark ? const Color(0xFFF0F2F8) : const Color(0xFF111111);
    final muted = isDark ? const Color(0xFF7A80A0) : const Color(0xFF888888);
    final faint = isDark ? const Color(0xFF5A5F78) : const Color(0xFFAAAAAA);

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: isDark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
      child: Scaffold(
        backgroundColor: bg,
        appBar: AppBar(
          backgroundColor: bg,
          elevation: 0,
          scrolledUnderElevation: 0,
          centerTitle: false,
          titleSpacing: 0,
          leading: IconButton(
            icon: Icon(Icons.arrow_back_ios_new, size: 18, color: ink),
            onPressed: () => context.pop(),
          ),
          title: Text(
            '数据详情',
            style: TextStyle(
              fontSize: 19,
              fontWeight: FontWeight.w700,
              color: ink,
            ),
          ),
          actions: [
            IconButton(
              icon: Icon(Icons.file_download_outlined, size: 20, color: muted),
              onPressed: () => showAppToast(context, '数据导出即将上线'),
            ),
          ],
        ),
        body: _loading
            ? _buildSkeleton(card, border)
            : ListView(
                padding: const EdgeInsets.only(bottom: 32),
                children: [
                  _buildSegment(isDark, ink, muted),
                  _buildStatGrid(card, border, ink, muted),
                  _buildTrendPlaceholder(card, border, ink, muted, faint),
                  _buildTopArticles(card, border, ink, muted, faint),
                  _buildEngagement(card, border, ink, muted),
                  _buildCodeRunPlaceholder(card, border, ink, muted, faint),
                ],
              ),
      ),
    );
  }

  // —————————————————————————————— 骨架屏
  Widget _buildSkeleton(Color card, Color border) {
    Widget box(double h, {double? w, EdgeInsets? m}) => Container(
      width: w,
      height: h,
      margin: m ?? const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: border,
        borderRadius: BorderRadius.circular(12),
      ),
    );
    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 32),
      physics: const NeverScrollableScrollPhysics(),
      children: [
        box(42),
        Row(
          children: [
            Expanded(child: box(96)),
            const SizedBox(width: 10),
            Expanded(child: box(96)),
          ],
        ),
        Row(
          children: [
            Expanded(child: box(96)),
            const SizedBox(width: 10),
            Expanded(child: box(96)),
          ],
        ),
        box(180),
        box(200),
      ],
    );
  }

  // —————————————————————————————— 时间段选择器
  Widget _buildSegment(bool isDark, Color ink, Color muted) {
    return Container(
      margin: const EdgeInsets.fromLTRB(14, 12, 14, 0),
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF111118) : const Color(0xFFF0F0F0),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: List.generate(3, (i) {
          final selected = _period == i;
          return Expanded(
            child: GestureDetector(
              onTap: () => setState(() => _period = i),
              behavior: HitTestBehavior.opaque,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                padding: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(
                  color: selected
                      ? (isDark ? const Color(0xFF23232E) : Colors.white)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                  boxShadow: selected && !isDark
                      ? [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.06),
                            blurRadius: 6,
                            offset: const Offset(0, 1),
                          ),
                        ]
                      : null,
                ),
                child: Text(
                  const ['近7天', '本月', '全部'][i],
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                    color: selected ? ink : muted,
                  ),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }

  // —————————————————————————————— 总览四格
  Widget _buildStatGrid(Color card, Color border, Color ink, Color muted) {
    final cells = [
      _statCard(
        '浏览量',
        _views,
        Icons.visibility_outlined,
        _primary,
        card,
        border,
        ink,
        muted,
      ),
      _statCard(
        '获赞',
        _likes,
        Icons.thumb_up_outlined,
        const Color(0xFF16A34A),
        card,
        border,
        ink,
        muted,
      ),
      _statCard(
        '收藏',
        _saves,
        Icons.bookmark_border,
        const Color(0xFFD97706),
        card,
        border,
        ink,
        muted,
      ),
      _statCard(
        '分享',
        _shares,
        Icons.share_outlined,
        _primary,
        card,
        border,
        ink,
        muted,
      ),
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 0),
      child: GridView.count(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        crossAxisCount: 2,
        childAspectRatio: 1.7,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
        children: cells,
      ),
    );
  }

  Widget _statCard(
    String label,
    int value,
    IconData icon,
    Color iconColor,
    Color card,
    Color border,
    Color ink,
    Color muted,
  ) {
    return Container(
      decoration: BoxDecoration(
        color: card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: border, width: 0.5),
      ),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            children: [
              Icon(icon, size: 14, color: iconColor),
              const SizedBox(width: 5),
              Text(label, style: TextStyle(fontSize: 12, color: muted)),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            _formatNum(value),
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w700,
              color: ink,
              height: 1.0,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            _periodSub,
            style: const TextStyle(fontSize: 11.5, color: Color(0xFF16A34A)),
          ),
        ],
      ),
    );
  }

  // —————————————————————————————— 浏览趋势（占位·待后端）
  Widget _buildTrendPlaceholder(
    Color card,
    Color border,
    Color ink,
    Color muted,
    Color faint,
  ) {
    return _card(
      card,
      border,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                '浏览趋势',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: ink,
                ),
              ),
              const Spacer(),
              _legendDot(_primary, '浏览', muted),
              const SizedBox(width: 10),
              _legendDot(const Color(0xFF16A34A), '获赞', muted),
            ],
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 120,
            child: Center(child: _comingSoon(muted, faint)),
          ),
        ],
      ),
    );
  }

  Widget _legendDot(Color c, String label, Color muted) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 7,
        height: 7,
        decoration: BoxDecoration(color: c, shape: BoxShape.circle),
      ),
      const SizedBox(width: 4),
      Text(label, style: TextStyle(fontSize: 11.5, color: muted)),
    ],
  );

  // 「数据统计中」占位——待后端 /auth/creator/stats 接口
  Widget _comingSoon(Color muted, Color faint) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(Icons.insights_outlined, size: 26, color: faint),
      const SizedBox(height: 8),
      Text('数据统计中', style: TextStyle(fontSize: 13, color: muted)),
      const SizedBox(height: 3),
      Text('功能即将上线', style: TextStyle(fontSize: 11, color: faint)),
    ],
  );

  // —————————————————————————————— 热门文章
  Widget _buildTopArticles(
    Color card,
    Color border,
    Color ink,
    Color muted,
    Color faint,
  ) {
    final top = _topArticles;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 22, 14, 8),
          child: Row(
            children: [
              Text(
                '热门文章',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: ink,
                ),
              ),
              const Spacer(),
              GestureDetector(
                onTap: () => context.push('/creator/works'),
                child: const Text(
                  '查看全部',
                  style: TextStyle(fontSize: 12.5, color: _primary),
                ),
              ),
            ],
          ),
        ),
        if (top.isEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
            child: Center(
              child: Text(
                '这段时间还没有发布作品',
                style: TextStyle(fontSize: 12.5, color: faint),
              ),
            ),
          )
        else
          _card(
            card,
            border,
            padding: EdgeInsets.zero,
            margin: const EdgeInsets.fromLTRB(14, 0, 14, 0),
            child: Column(
              children: [
                for (var i = 0; i < top.length; i++) ...[
                  if (i > 0)
                    Divider(height: 0.5, thickness: 0.5, color: border),
                  _artRow(i + 1, top[i], ink, muted),
                ],
              ],
            ),
          ),
      ],
    );
  }

  Widget _artRow(int rank, TutorialModel t, Color ink, Color muted) {
    final isTop = rank <= 2;
    final category = t.tags.isNotEmpty
        ? t.tags.first
        : (topicCategoryLabelFor(t.tags) ?? '');
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          Container(
            width: 24,
            height: 24,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: isTop ? _primary : const Color(0x11000000),
              shape: BoxShape.circle,
            ),
            child: Text(
              '$rank',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: isTop ? Colors.white : muted,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  t.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: ink,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  category.isEmpty
                      ? _timeAgo(t.createdAt)
                      : '$category · ${_timeAgo(t.createdAt)}',
                  style: TextStyle(fontSize: 11.5, color: muted),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Text(
            _formatNum(t.views),
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: ink,
            ),
          ),
        ],
      ),
    );
  }

  // —————————————————————————————— 互动分布
  Widget _buildEngagement(Color card, Color border, Color ink, Color muted) {
    final rows = [
      ('浏览', _views, _primary),
      ('获赞', _likes, const Color(0xFF16A34A)),
      ('收藏', _saves, const Color(0xFFD97706)),
      ('分享', _shares, const Color(0xFF2563EB)),
      ('评论', _comments, const Color(0xFFEC4899)),
    ];
    final maxV = rows.fold<int>(0, (m, r) => r.$2 > m ? r.$2 : m);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 22, 14, 8),
          child: Text(
            '互动分布',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: ink,
            ),
          ),
        ),
        _card(
          card,
          border,
          child: Column(
            children: [
              for (final r in rows) ...[
                if (r != rows.first) const SizedBox(height: 14),
                Row(
                  children: [
                    SizedBox(
                      width: 34,
                      child: Text(
                        r.$1,
                        style: TextStyle(fontSize: 13, color: muted),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(99),
                        child: LinearProgressIndicator(
                          value: maxV == 0 ? 0 : (r.$2 / maxV).clamp(0.0, 1.0),
                          minHeight: 8,
                          backgroundColor: const Color(0x14000000),
                          valueColor: AlwaysStoppedAnimation(r.$3),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    SizedBox(
                      width: 52,
                      child: Text(
                        _formatNum(r.$2),
                        textAlign: TextAlign.right,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: ink,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  // —————————————————————————————— 代码运行统计（占位·待后端）
  Widget _buildCodeRunPlaceholder(
    Color card,
    Color border,
    Color ink,
    Color muted,
    Color faint,
  ) {
    return _card(
      card,
      border,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '代码运行统计',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: ink,
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(height: 92, child: Center(child: _comingSoon(muted, faint))),
        ],
      ),
    );
  }

  // 通用卡片外壳
  Widget _card(
    Color card,
    Color border, {
    required Widget child,
    EdgeInsets? padding,
    EdgeInsets? margin,
  }) {
    return Container(
      margin: margin ?? const EdgeInsets.fromLTRB(14, 12, 14, 0),
      padding: padding ?? const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: border, width: 0.5),
      ),
      child: child,
    );
  }
}
