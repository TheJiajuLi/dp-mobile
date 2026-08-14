import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_client.dart';
import '../../../shared/widgets/app_toast.dart';

// 创作数据详情页——接入 GET /auth/creator/stats?period=week|month|all。
// 有真实数据的字段正常显示；无数据源的字段明确标注（不编假数据）：
//   · views / shares → 累计总数（无逐日/无环比），副标题「累计总浏览/分享」
//   · viewsChange / sharesChange → 不显示环比
//   · trend[].views → 趋势图只画 likes 单线（没有逐日浏览）
//   · codeRuns / codeSuccessRate → 显示「暂无统计」
// 真实：likes/saves/comments、likesChange/savesChange 环比、trend[].likes 逐日
// 点赞、topArticles Top5、codeArticles 含代码文章数。
const _primary = AppColors.primary;
const _green = AppColors.success;

class CreatorStatsScreen extends ConsumerStatefulWidget {
  // HD 双栏内嵌时（HdProfilePage 右栏）隐藏返回键——根级标签内没有可 pop 的路由
  final bool showBackButton;
  const CreatorStatsScreen({super.key, this.showBackButton = true});

  @override
  ConsumerState<CreatorStatsScreen> createState() => _CreatorStatsScreenState();
}

class _CreatorStatsScreenState extends ConsumerState<CreatorStatsScreen> {
  int _period = 1; // 0=week 1=month 2=all
  bool _loading = true;
  Map<String, dynamic> _data = {};

  static const _periodParams = ['week', 'month', 'all'];

  @override
  void initState() {
    super.initState();
    _loadStats();
  }

  Future<void> _loadStats() async {
    setState(() => _loading = true);
    final res = await ref
        .read(apiClientProvider)
        .get(
          '/auth/creator/stats',
          queryParameters: {'period': _periodParams[_period]},
        );
    if (!mounted) return;
    setState(() {
      _data = res.success && res.data is Map
          ? Map<String, dynamic>.from(res.data as Map)
          : {};
      _loading = false;
    });
  }

  void _onPeriod(int i) {
    if (i == _period) return;
    setState(() => _period = i);
    _loadStats();
  }

  // —————————————————————————————— 字段读取（都做 null 兜底）
  int _int(String key) => (_data[key] as num?)?.toInt() ?? 0;
  num? _num(String key) => _data[key] as num?;

  List<Map<String, dynamic>> get _trend => ((_data['trend'] as List?) ?? [])
      .map((e) => Map<String, dynamic>.from(e as Map))
      .toList();

  List<Map<String, dynamic>> get _topArticles =>
      ((_data['topArticles'] as List?) ?? [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();

  String _formatNum(int n) {
    if (n >= 10000) return '${(n / 10000).toStringAsFixed(1)}w';
    return n.toString().replaceAllMapped(
      RegExp(r'(\d)(?=(\d{3})+$)'),
      (m) => '${m[1]},',
    );
  }

  String _timeAgo(dynamic createdAt) {
    var ms = (createdAt as num?)?.toInt() ?? 0;
    if (ms > 0 && ms < 100000000000) ms *= 1000; // 秒级 → 毫秒
    if (ms == 0) return '';
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
          automaticallyImplyLeading: widget.showBackButton,
          leading: widget.showBackButton
              ? IconButton(
                  icon: Icon(Icons.arrow_back_ios_new, size: 18, color: ink),
                  onPressed: () => context.pop(),
                )
              : null,
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
            ? _buildSkeleton(border)
            : ListView(
                padding: const EdgeInsets.only(bottom: 32),
                children: [
                  _buildSegment(isDark, ink, muted),
                  _buildStatGrid(card, border, ink, muted, faint),
                  _buildTrendCard(card, border, ink, muted, faint),
                  _buildTopArticles(card, border, ink, muted, faint),
                  _buildEngagement(card, border, ink, muted),
                  _buildCodeRun(card, border, ink, muted, faint),
                ],
              ),
      ),
    );
  }

  // —————————————————————————————— 骨架屏
  Widget _buildSkeleton(Color border) {
    Widget box(double h) => Container(
      height: h,
      margin: const EdgeInsets.only(bottom: 10),
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

  // —————————————————————————————— 时间段选择器（切换重新请求）
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
              onTap: () => _onPeriod(i),
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
  Widget _buildStatGrid(
    Color card,
    Color border,
    Color ink,
    Color muted,
    Color faint,
  ) {
    final cells = [
      // 浏览：累计总数，无环比、副标题标注「累计总浏览」
      _statCard(
        '浏览量',
        _int('views'),
        Icons.visibility_outlined,
        _primary,
        card,
        border,
        ink,
        muted,
        faint,
        subtitle: '累计总浏览',
      ),
      // 获赞：真实 + 环比%
      _statCard(
        '获赞',
        _int('likes'),
        Icons.thumb_up_outlined,
        _green,
        card,
        border,
        ink,
        muted,
        faint,
        change: _num('likesChange'),
      ),
      // 收藏：真实 + 环比%
      _statCard(
        '收藏',
        _int('saves'),
        Icons.bookmark_border,
        const Color(0xFFD97706),
        card,
        border,
        ink,
        muted,
        faint,
        change: _num('savesChange'),
      ),
      // 分享：累计总数，无环比、副标题标注「累计总分享」
      _statCard(
        '分享',
        _int('shares'),
        Icons.share_outlined,
        _primary,
        card,
        border,
        ink,
        muted,
        faint,
        subtitle: '累计总分享',
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
    Color faint, {
    num? change,
    String? subtitle,
  }) {
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
          // 副标题：累计字段显示中性说明；环比字段显示 ↑/↓ %
          subtitle != null
              ? Text(subtitle, style: TextStyle(fontSize: 11.5, color: faint))
              : _changeChip(change, faint),
        ],
      ),
    );
  }

  // 环比标签——正绿↑ / 负红↓ / 0持平 / null 无数据
  Widget _changeChip(num? change, Color faint) {
    if (change == null) {
      return Text('暂无环比', style: TextStyle(fontSize: 11.5, color: faint));
    }
    if (change == 0) {
      return Text('持平', style: TextStyle(fontSize: 11.5, color: faint));
    }
    final up = change > 0;
    final c = up ? _green : const Color(0xFFEF4444);
    return Row(
      children: [
        Icon(
          up ? Icons.arrow_upward : Icons.arrow_downward,
          size: 11,
          color: c,
        ),
        const SizedBox(width: 2),
        Text(
          '${change.abs().toStringAsFixed(0)}% 较上期',
          style: TextStyle(fontSize: 11.5, color: c),
        ),
      ],
    );
  }

  // —————————————————————————————— 获赞趋势（真实逐日 likes 单线）
  Widget _buildTrendCard(
    Color card,
    Color border,
    Color ink,
    Color muted,
    Color faint,
  ) {
    final trend = _trend;
    final values = trend
        .map((e) => (e['likes'] as num?)?.toDouble() ?? 0)
        .toList();
    final labels = trend.map((e) => _shortDate(e['date'])).toList();
    return _card(
      card,
      border,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                '获赞趋势',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: ink,
                ),
              ),
              const Spacer(),
              // 图例只有获赞（没有逐日浏览数据，不画浏览线）
              _legendDot(_green, '获赞', muted),
            ],
          ),
          const SizedBox(height: 10),
          if (values.length < 2)
            SizedBox(
              height: 120,
              child: Center(
                child: Text(
                  '暂无数据',
                  style: TextStyle(fontSize: 13, color: faint),
                ),
              ),
            )
          else ...[
            SizedBox(
              height: 120,
              child: CustomPaint(
                size: Size.infinite,
                painter: _TrendLinePainter(values: values, color: _green),
              ),
            ),
            const SizedBox(height: 6),
            _xAxisLabels(labels, faint),
          ],
        ],
      ),
    );
  }

  String _shortDate(dynamic date) {
    final s = date?.toString() ?? '';
    // 支持 '2026-07-10' / '07-10' / ISO
    final m = RegExp(r'(\d{1,2})-(\d{1,2})(?!\d)').allMatches(s).toList();
    if (m.isEmpty) return s;
    final last = m.last;
    return '${int.parse(last.group(1)!)}/${int.parse(last.group(2)!)}';
  }

  Widget _xAxisLabels(List<String> labels, Color faint) {
    if (labels.isEmpty) return const SizedBox.shrink();
    // 均匀取 4 个标签，避免挤在一起
    final picks = <String>[];
    final n = labels.length;
    for (final idx in [0, (n / 3).floor(), (2 * n / 3).floor(), n - 1]) {
      final i = idx.clamp(0, n - 1);
      if (!picks.contains(labels[i])) picks.add(labels[i]);
    }
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: picks
          .map((l) => Text(l, style: TextStyle(fontSize: 10.5, color: faint)))
          .toList(),
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

  // —————————————————————————————— 热门文章 Top5
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
                '这段时间还没有热门文章',
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

  Widget _artRow(int rank, Map<String, dynamic> a, Color ink, Color muted) {
    final isTop = rank <= 2;
    final title = a['title']?.toString() ?? '';
    final views = (a['views'] as num?)?.toInt() ?? 0;
    final category = a['category']?.toString() ?? '';
    final ago = _timeAgo(a['createdAt']);
    final sub = [
      if (category.isNotEmpty) category,
      if (ago.isNotEmpty) ago,
    ].join(' · ');
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
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: ink,
                  ),
                ),
                if (sub.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(sub, style: TextStyle(fontSize: 11.5, color: muted)),
                ],
              ],
            ),
          ),
          const SizedBox(width: 10),
          Text(
            _formatNum(views),
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
      ('浏览', _int('views'), _primary),
      ('获赞', _int('likes'), _green),
      ('收藏', _int('saves'), const Color(0xFFD97706)),
      ('分享', _int('shares'), const Color(0xFF2563EB)),
      ('评论', _int('comments'), const Color(0xFFEC4899)),
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

  // —————————————————————————————— 代码运行统计
  // 总运行次数/成功率暂无数据源 → 「暂无统计」；含代码文章数真实
  Widget _buildCodeRun(
    Color card,
    Color border,
    Color ink,
    Color muted,
    Color faint,
  ) {
    Widget cell(String label, String value, {bool real = true}) => Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: card == Colors.white
              ? const Color(0xFFF7F7F9)
              : Colors.white.withValues(alpha: 0.03),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: [
            Text(
              value,
              style: TextStyle(
                fontSize: real ? 20 : 12.5,
                fontWeight: real ? FontWeight.w700 : FontWeight.w500,
                color: real ? _primary : faint,
              ),
            ),
            const SizedBox(height: 4),
            Text(label, style: TextStyle(fontSize: 11, color: muted)),
          ],
        ),
      ),
    );
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
          const SizedBox(height: 12),
          Row(
            children: [
              cell('总运行次数', '暂无统计', real: false),
              const SizedBox(width: 10),
              cell('运行成功率', '暂无统计', real: false),
              const SizedBox(width: 10),
              cell('含代码文章', '${_int('codeArticles')}'),
            ],
          ),
        ],
      ),
    );
  }

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

// 单线趋势折线——直线段折线 + 数据点 + 线下渐变填充
class _TrendLinePainter extends CustomPainter {
  final List<double> values;
  final Color color;
  const _TrendLinePainter({required this.values, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    if (values.length < 2) return;
    const padT = 8.0, padB = 6.0;
    final maxV = values.reduce((a, b) => a > b ? a : b);
    final minV = values.reduce((a, b) => a < b ? a : b);
    final range = (maxV - minV).abs() < 1e-6 ? 1.0 : (maxV - minV);
    final dx = size.width / (values.length - 1);

    Offset pt(int i) {
      final x = dx * i;
      final norm = (values[i] - minV) / range;
      final y = padT + (1 - norm) * (size.height - padT - padB);
      return Offset(x, y);
    }

    final pts = List.generate(values.length, pt);

    // 线下渐变填充
    final fill = Path()..moveTo(pts.first.dx, size.height);
    for (final p in pts) {
      fill.lineTo(p.dx, p.dy);
    }
    fill
      ..lineTo(pts.last.dx, size.height)
      ..close();
    canvas.drawPath(
      fill,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [color.withValues(alpha: 0.22), color.withValues(alpha: 0.0)],
        ).createShader(Offset.zero & size),
    );

    // 折线
    final line = Path()..moveTo(pts.first.dx, pts.first.dy);
    for (final p in pts.skip(1)) {
      line.lineTo(p.dx, p.dy);
    }
    canvas.drawPath(
      line,
      Paint()
        ..color = color
        ..strokeWidth = 2.2
        ..style = PaintingStyle.stroke
        ..strokeJoin = StrokeJoin.round
        ..strokeCap = StrokeCap.round,
    );

    // 数据点
    for (final p in pts) {
      canvas.drawCircle(p, 3, Paint()..color = color);
      canvas.drawCircle(p, 1.4, Paint()..color = Colors.white);
    }
  }

  @override
  bool shouldRepaint(_TrendLinePainter old) =>
      old.values != values || old.color != color;
}
