import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_client.dart';
import '../../../shared/models/tutorial_model.dart';
import '../../auth/auth_service.dart';
import '../../aurora/models/aurora_progress_model.dart';

// 创作数据分析页——只展示有真实数据源的指标，不编趋势%/代码运行这类无接口
// 的假数字。数据全部来自：
//   · GET /auth/tutorials（本人已发布作品）→ 浏览/获赞/收藏、热门排行、
//     以及按发布时间分组的柱状图
//   · GET /auth/aurora/progress（仅极光创作者）→ 本月新增粉丝
// 本周/本月/全部 = 按作品的「发布时间」过滤这批已发布作品，统计的是「这段
// 时间发布的作品」的累计数据（不是「这段时间产生的浏览」——后者没数据源）。
const _primary = Color(0xFF6366F1);

class CreatorStatsScreen extends ConsumerStatefulWidget {
  const CreatorStatsScreen({super.key});

  @override
  ConsumerState<CreatorStatsScreen> createState() => _CreatorStatsScreenState();
}

class _CreatorStatsScreenState extends ConsumerState<CreatorStatsScreen> {
  int _period = 0; // 0本周 1本月 2全部
  bool _loading = true;

  // 全量已发布作品（一次拉回，周期切换在客户端按 createdAt 过滤，不再打接口）
  List<TutorialModel> _all = [];
  // 极光当月新增粉丝——非极光创作者为 null（不显示这格）
  int? _newFans;

  @override
  void initState() {
    super.initState();
    _loadStats();
  }

  Future<void> _loadStats() async {
    final user = ref.read(currentUserProvider);
    if (user == null) return;
    final api = ref.read(apiClientProvider);

    final res = await api.get(
      '/auth/tutorials',
      queryParameters: {
        'author': user.username,
        'status': 'published',
        'limit': 200,
      },
    );

    // 极光创作者才有「本月新增粉丝」的真实来源，其余用户不请求也不显示
    int? newFans;
    if (user.isAuroraCreator) {
      final ares = await api.get('/auth/aurora/progress');
      if (ares.success && ares.data is Map) {
        newFans = AuroraProgress.fromJson(
          Map<String, dynamic>.from(ares.data as Map),
        ).currentMonth.newFollowersCount;
      }
    }

    if (!mounted) return;

    final all = <TutorialModel>[];
    if (res.success && res.data != null) {
      final list = (res.data['tutorials'] as List? ?? [])
          .where((j) => (j as Map)['user_id'] == user.id)
          .map((j) => TutorialModel.fromJson(Map<String, dynamic>.from(j)))
          .toList();
      all.addAll(list);
    }

    setState(() {
      _all = all;
      _newFans = newFans;
      _loading = false;
    });
  }

  // 当前周期过滤后的作品（按发布时间）。全部=不过滤
  List<TutorialModel> get _filtered {
    if (_period == 2) return _all;
    final now = DateTime.now();
    final DateTime from = _period == 0
        ? DateTime(now.year, now.month, now.day).subtract(
            Duration(days: now.weekday - 1),
          ) // 本周一 00:00
        : DateTime(now.year, now.month, 1); // 本月 1 号 00:00
    final fromMs = from.millisecondsSinceEpoch;
    return _all.where((t) => t.createdAt >= fromMs).toList();
  }

  int get _views => _filtered.fold(0, (s, t) => s + t.views);
  int get _likes => _filtered.fold(0, (s, t) => s + t.likes);
  int get _saves => _filtered.fold(0, (s, t) => s + t.saveCount);

  List<TutorialModel> get _topArticles {
    final list = [..._filtered]..sort((a, b) => b.views.compareTo(a.views));
    return list.take(5).toList();
  }

  String _formatNum(int n) {
    if (n >= 10000) return '${(n / 10000).toStringAsFixed(1)}w';
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}k';
    return n.toString();
  }

  String get _periodLabel => const ['本周', '本月', '全部'][_period];

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
            '数据分析',
            style: TextStyle(
              fontSize: 19,
              fontWeight: FontWeight.w700,
              color: ink,
            ),
          ),
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator(strokeWidth: 2.4))
            : ListView(
                padding: const EdgeInsets.only(bottom: 32),
                children: [
                  _buildSegment(isDark, ink, muted),
                  _buildStatGrid(card, border, ink, muted),
                  _buildTrendCard(card, border, ink, muted, faint),
                  _buildTopArticles(card, border, ink, muted, faint),
                ],
              ),
      ),
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
                  const ['本周', '本月', '全部'][i],
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

  // —————————————————————————————— 总览格（浏览/获赞/收藏 + 极光新增粉丝）
  Widget _buildStatGrid(Color card, Color border, Color ink, Color muted) {
    final cells = <Widget>[
      _statCard('浏览量', _formatNum(_views), card, border, ink, muted),
      _statCard('获赞', _formatNum(_likes), card, border, ink, muted),
      _statCard('收藏', _formatNum(_saves), card, border, ink, muted),
      if (_newFans != null)
        _statCard('本月新增粉丝', '+${_newFans!}', card, border, ink, muted),
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
    String value,
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
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            value,
            style: TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.w700,
              color: ink,
              height: 1.0,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 6),
          Text(label, style: TextStyle(fontSize: 12, color: muted)),
        ],
      ),
    );
  }

  // —————————————————————————————— 发布趋势柱状图（按发布时间分组）
  // 全部：按最近6个月分组；本月：按本月每周分组；本周：按周一~今天每天分组。
  // 柱高 = 该分组内所有作品的浏览量之和（真实）。
  Widget _buildTrendCard(
    Color card,
    Color border,
    Color ink,
    Color muted,
    Color faint,
  ) {
    final bars = _computeBars();
    final maxV = bars.fold<int>(0, (m, b) => b.value > m ? b.value : m);
    final total = bars.fold<int>(0, (s, b) => s + b.value);

    return Container(
      margin: const EdgeInsets.fromLTRB(14, 12, 14, 0),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
      decoration: BoxDecoration(
        color: card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: border, width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '发布浏览趋势',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: ink,
                ),
              ),
              Text(
                '$_periodLabel ${_formatNum(total)} 次',
                style: const TextStyle(fontSize: 12.5, color: _primary),
              ),
            ],
          ),
          const SizedBox(height: 18),
          if (total == 0)
            SizedBox(
              height: 78,
              child: Center(
                child: Text(
                  _period == 2 ? '还没有已发布的作品' : '这段时间还没有发布作品',
                  style: TextStyle(fontSize: 12.5, color: faint),
                ),
              ),
            )
          else
            SizedBox(
              height: 78,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: List.generate(bars.length, (i) {
                  final b = bars[i];
                  final factor = maxV == 0 ? 0.0 : b.value / maxV;
                  final isLast = i == bars.length - 1;
                  return Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 3),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          Expanded(
                            child: FractionallySizedBox(
                              alignment: Alignment.bottomCenter,
                              // 有数据的分组至少给一点可见高度，0 的分组不画
                              heightFactor: b.value == 0
                                  ? 0.0
                                  : (0.14 + 0.86 * factor),
                              child: Container(
                                decoration: BoxDecoration(
                                  color: isLast
                                      ? _primary
                                      : _primary.withValues(alpha: 0.28),
                                  borderRadius: const BorderRadius.vertical(
                                    top: Radius.circular(4),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            b.label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 9.5, color: muted),
                          ),
                        ],
                      ),
                    ),
                  );
                }),
              ),
            ),
        ],
      ),
    );
  }

  // 按当前周期把已过滤的作品分组求浏览量和，返回 (标签, 值) 序列
  List<_Bar> _computeBars() {
    final items = _filtered;
    final now = DateTime.now();
    if (_period == 0) {
      // 本周：周一~今天，每天一根
      const names = ['一', '二', '三', '四', '五', '六', '日'];
      final monday = DateTime(
        now.year,
        now.month,
        now.day,
      ).subtract(Duration(days: now.weekday - 1));
      return List.generate(now.weekday, (i) {
        final dayStart = monday.add(Duration(days: i)).millisecondsSinceEpoch;
        final dayEnd = monday.add(Duration(days: i + 1)).millisecondsSinceEpoch;
        final v = items
            .where((t) => t.createdAt >= dayStart && t.createdAt < dayEnd)
            .fold<int>(0, (s, t) => s + t.views);
        return _Bar(i == now.weekday - 1 ? '今天' : names[i], v);
      });
    } else if (_period == 1) {
      // 本月：按周分组（第1周~当前周）
      final weeks = ((now.day - 1) ~/ 7) + 1;
      return List.generate(weeks, (i) {
        final ds = DateTime(
          now.year,
          now.month,
          i * 7 + 1,
        ).millisecondsSinceEpoch;
        final de = DateTime(
          now.year,
          now.month,
          i * 7 + 8,
        ).millisecondsSinceEpoch;
        final v = items
            .where((t) => t.createdAt >= ds && t.createdAt < de)
            .fold<int>(0, (s, t) => s + t.views);
        return _Bar('第${i + 1}周', v);
      });
    } else {
      // 全部：最近6个月，每月一根
      return List.generate(6, (idx) {
        final i = 5 - idx; // 从6个月前到本月
        final m = DateTime(now.year, now.month - i, 1);
        final ds = m.millisecondsSinceEpoch;
        final de = DateTime(m.year, m.month + 1, 1).millisecondsSinceEpoch;
        final v = items
            .where((t) => t.createdAt >= ds && t.createdAt < de)
            .fold<int>(0, (s, t) => s + t.views);
        return _Bar('${m.month}月', v);
      });
    }
  }

  // —————————————————————————————— 热门文章排行
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
          child: Text(
            '热门文章',
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: muted,
            ),
          ),
        ),
        if (top.isEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 18, 14, 18),
            child: Center(
              child: Text(
                '这段时间还没有发布作品',
                style: TextStyle(fontSize: 12.5, color: faint),
              ),
            ),
          )
        else
          ...top.asMap().entries.map(
            (e) => _artItem(e.key + 1, e.value, card, border, ink, muted),
          ),
      ],
    );
  }

  Widget _artItem(
    int rank,
    TutorialModel t,
    Color card,
    Color border,
    Color ink,
    Color muted,
  ) {
    // 金银铜（背景/文字）；4名开始用中性灰
    const rankColors = [
      [Color(0xFFFEF3C7), Color(0xFFD97706)], // 金
      [Color(0xFFF1F1F4), Color(0xFF8A8A8A)], // 银
      [Color(0xFFFBE9D8), Color(0xFF92400E)], // 铜
    ];
    final c = rank <= 3 ? rankColors[rank - 1] : [border, muted];

    return Container(
      margin: const EdgeInsets.fromLTRB(14, 0, 14, 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        color: card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: border, width: 0.5),
      ),
      child: Row(
        children: [
          Container(
            width: 22,
            height: 22,
            decoration: BoxDecoration(
              color: c[0],
              borderRadius: BorderRadius.circular(7),
            ),
            child: Center(
              child: Text(
                '$rank',
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  color: c[1],
                ),
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
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                    color: ink,
                  ),
                ),
                const SizedBox(height: 3),
                Row(
                  children: [
                    Icon(Icons.favorite_border, size: 12, color: muted),
                    const SizedBox(width: 3),
                    Text(
                      _formatNum(t.likes),
                      style: TextStyle(fontSize: 11.5, color: muted),
                    ),
                    const SizedBox(width: 12),
                    Icon(Icons.bookmark_border, size: 12, color: muted),
                    const SizedBox(width: 3),
                    Text(
                      _formatNum(t.saveCount),
                      style: TextStyle(fontSize: 11.5, color: muted),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                _formatNum(t.views),
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: ink,
                ),
              ),
              Text('浏览', style: TextStyle(fontSize: 10, color: muted)),
            ],
          ),
        ],
      ),
    );
  }
}

class _Bar {
  final String label;
  final int value;
  const _Bar(this.label, this.value);
}
