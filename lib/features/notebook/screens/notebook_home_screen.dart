import 'dart:ui' as ui;
import '../../../core/theme/app_colors.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../features/auth/auth_service.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../../shared/utils/greeting.dart';
import '../services/notebook_service.dart';

// 欢迎页重新走活泼的彩色方向：每个 notebook 图标取一组"浅底 + 同色字形"
// （$1=浅底 tint，$2=图标/角标 accent）。最近打开按稳定 hash 取，保证同一个
// notebook 每次颜色不变；模板卡各自显式指定。
const _palette = <(Color, Color)>[
  (Color(0xFFEDE9FE), Color(0xFF7C6FF0)), // 紫
  (Color(0xFFFEF3C7), Color(0xFFF59E0B)), // 琥珀
  (Color(0xFFDBEAFE), Color(0xFF3B82F6)), // 蓝
  (Color(0xFFFCE7F3), Color(0xFFC026D3)), // 品红
  (Color(0xFFDCFCE7), AppColors.success), // 绿
];

// 浅色卡片统一的一层极淡阴影，制造"浮起"的层次；深色不用
const _cardBorder = Color(0xFFEBEBEB);
List<BoxShadow>? _cardShadow(bool isDark) => isDark
    ? null
    : [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.03),
          blurRadius: 10,
          offset: const Offset(0, 2),
        ),
      ];

class NotebookHomeScreen extends ConsumerStatefulWidget {
  // HD 双栏内嵌时（HdNotebookPage）传 onOpen：打开 notebook 不再 push 新路由，
  // 而是回调给 HD 页面在同一标签内联切换到编辑器（保留 HD 侧栏/标签）。
  // 手机端不传，走原来的 context.push('/notebook/:id')
  final void Function(String nbId)? onOpen;
  // HD 根标签内嵌时（HdNotebookPage）传 false 隐藏返回键——根标签没有可 pop 的
  // 路由，Navigator.pop 会炸。手机端 push 进来（profile/main_shell）不传
  final bool showBackButton;
  const NotebookHomeScreen({
    super.key,
    this.onOpen,
    this.showBackButton = true,
  });
  @override
  ConsumerState<NotebookHomeScreen> createState() => _State();
}

class _State extends ConsumerState<NotebookHomeScreen> {
  List<Map<String, dynamic>> _recent = [];

  void _open(String id) {
    if (widget.onOpen != null) {
      widget.onOpen!(id);
    } else {
      context.push('/notebook/$id');
    }
  }
  NotebookService? _svc;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _init());
  }

  Future<void> _init() async {
    final user = ref.read(currentUserProvider);
    _svc = NotebookService(user?.id ?? 'guest');
    final recent = await _svc!.getRecentList();
    setState(() {
      _recent = recent;
      _loading = false;
    });
  }

  void _showNewSheet() {
    final l10n = AppLocalizations.of(context)!;
    final ctrl = TextEditingController();
    String type = 'python';
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => Container(
          decoration: BoxDecoration(
            color: Theme.of(ctx).cardColor,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          padding: EdgeInsets.fromLTRB(
            20,
            12,
            20,
            MediaQuery.of(ctx).viewInsets.bottom + 24,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
                margin: const EdgeInsets.only(bottom: 16),
              ),
              Text(
                l10n.newNotebook,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                l10n.chooseTypeSubtitle,
                style: TextStyle(fontSize: 13, color: Colors.grey[500]),
              ),
              const SizedBox(height: 20),
              TextField(
                controller: ctrl,
                autofocus: true,
                decoration: InputDecoration(
                  hintText: l10n.notebookNameHint,
                  filled: true,
                  fillColor: Theme.of(ctx).inputDecorationTheme.fillColor,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 12,
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  // 每种类型一个彩色图标盒（跟主页模板卡同款语言），选中态用
                  // 该类型自己的颜色描边+淡色底，跟主页的彩色语言一致
                  for (final t in [
                    (
                      'python',
                      'Python',
                      Icons.code_rounded,
                      AppColors.primary,
                      AppColors.primaryLight,
                    ),
                    (
                      'latex',
                      'LaTeX',
                      Icons.functions,
                      const Color(0xFF8B5CF6),
                      const Color(0xFFEDE9FE),
                    ),
                    (
                      'mixed',
                      l10n.langMixed,
                      Icons.layers_rounded,
                      const Color(0xFF2563EB),
                      const Color(0xFFEFF6FF),
                    ),
                  ])
                    Expanded(
                      child: GestureDetector(
                        onTap: () => setState(() => type = t.$1),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 160),
                          margin: EdgeInsets.only(right: t.$1 == 'mixed' ? 0 : 8),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          decoration: BoxDecoration(
                            color: type == t.$1
                                ? t.$4.withValues(alpha: 0.08)
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: type == t.$1
                                  ? t.$4
                                  : Colors.grey.withValues(alpha: 0.25),
                              width: type == t.$1 ? 1.5 : 0.5,
                            ),
                          ),
                          child: Column(
                            children: [
                              Container(
                                width: 38,
                                height: 38,
                                decoration: BoxDecoration(
                                  color: t.$5,
                                  borderRadius: BorderRadius.circular(11),
                                ),
                                child: Icon(t.$3, color: t.$4, size: 19),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                t.$2,
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: type == t.$1
                                      ? t.$4
                                      : (Theme.of(ctx).brightness ==
                                            Brightness.dark
                                          ? Colors.white70
                                          : const Color(0xFF555555)),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton(
                  onPressed: () async {
                    final name = ctrl.text.trim();
                    if (name.isEmpty) return;
                    final nb = await _svc!.create(name, type);
                    if (ctx.mounted) Navigator.pop(ctx);
                    if (mounted) _open(nb.id);
                  },
                  style: ElevatedButton.styleFrom(
                    // 品牌紫，跟主页 Hero「新建 Notebook」和顶栏「+」一套
                    backgroundColor: AppColors.primary,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.add, color: Colors.white, size: 18),
                      const SizedBox(width: 6),
                      Text(
                        l10n.create,
                        style: const TextStyle(
                          fontSize: 15,
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
        ),
      ),
    );
  }

  // 极光深色渐变 Hero：深紫渐变底 + 右上角光晕 + 底部柔光射线 + 毛玻璃
  // 「新建」按钮。深浅色统一走这套深色卡（跟个人主页头图区一样是刻意的
  // 局部深色，欢迎页需要一点氛围感，不套米白/无渐变那套静态规范）
  Widget _buildHero(AppLocalizations l10n) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 24),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF2A2158).withValues(alpha: 0.35),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Stack(
          children: [
            const Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Color(0xFF221C3E),
                      Color(0xFF322A66),
                      Color(0xFF1D2A5C),
                    ],
                  ),
                ),
              ),
            ),
            // 右上角紫蓝极光光晕
            Positioned(
              right: -50,
              top: -50,
              child: Container(
                width: 200,
                height: 200,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [Color(0x554F46E5), Color(0x004F46E5)],
                  ),
                ),
              ),
            ),
            // 底部柔光射线
            Positioned.fill(child: CustomPaint(painter: _RaysPainter())),
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    greetingText(context),
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.white.withValues(alpha: 0.5),
                      letterSpacing: 0.3,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    l10n.whereToStart,
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w700,
                      height: 1.2,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 18),
                  _glassNewButton(l10n),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // 毛玻璃「新建 Notebook」按钮：半透明白 + 细白描边 + 背景模糊，衬在深色
  // 渐变上是磨砂玻璃质感（Hero 是刻意的深色语境，符合毛玻璃只用在深色的规则）
  Widget _glassNewButton(AppLocalizations l10n) {
    return GestureDetector(
      onTap: _showNewSheet,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 12, sigmaY: 12),
          child: Container(
            width: double.infinity,
            height: 50,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.22),
                width: 0.8,
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.add, color: Colors.white, size: 18),
                const SizedBox(width: 6),
                Text(
                  l10n.newNotebook,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    // 浅色统一用首页同款米白 #FAFAF8
    final bg = isDark
        ? Theme.of(context).scaffoldBackgroundColor
        : const Color(0xFFFAFAF8);
    return Scaffold(
      backgroundColor: bg,
      // top/bottom 不在这层留白，顶栏自己用 SafeArea(bottom:false) 把
      // 白色背景铺进状态栏安全区，不然这层统一留白会露出 Scaffold 背景
      // 跟顶栏纯白刀切不连贯（跟 publish_screen.dart 顶栏是同一套处理）
      body: SafeArea(
        top: false,
        bottom: false,
        child: Column(
          children: [
            // 顶部栏——跟画布同底色，底部一条极淡分割线，不再是纯白刀切
            Container(
              decoration: BoxDecoration(
                color: bg,
                border: Border(
                  bottom: BorderSide(
                    color: isDark
                        ? Colors.white.withValues(alpha: 0.04)
                        : _cardBorder,
                    width: 0.5,
                  ),
                ),
              ),
              child: SafeArea(
                bottom: false,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  child: Row(
                    children: [
                      if (widget.showBackButton) ...[
                        GestureDetector(
                          onTap: () => Navigator.pop(context),
                          behavior: HitTestBehavior.opaque,
                          child: Row(
                            children: [
                              Icon(
                                Icons.arrow_back_ios,
                                size: 16,
                                color: isDark
                                    ? const Color(0xFF7A80A0)
                                    : const Color(0xFF888888),
                              ),
                              Text(
                                l10n.back,
                                style: TextStyle(
                                  fontSize: 13,
                                  color: isDark
                                      ? const Color(0xFF7A80A0)
                                      : const Color(0xFF888888),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                      ],
                      Text(
                        l10n.appNotebookTitle,
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: isDark
                              ? Colors.white
                              : const Color(0xFF1A1A1A),
                        ),
                      ),
                      // 顶栏右上角「+」已删除——Hero 的「新建 Notebook」和下面
                      // 的模板卡已经是充分的创建入口，这里多一个是冗余
                    ],
                  ),
                ),
              ),
            ),

            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : RefreshIndicator(
                      onRefresh: _init,
                      child: SingleChildScrollView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Hero——极光深色渐变卡（欢迎页重新做活）
                            _buildHero(l10n),

                            // 最近
                            if (_recent.isNotEmpty) ...[
                              _SectionHeader(
                                title: l10n.recentlyOpened,
                                action: l10n.viewAll,
                                onAction: () {},
                              ),
                              const SizedBox(height: 10),
                              ..._recent.map(
                                (nb) => _RecentCard(
                                  nb: nb,
                                  onTap: () => _open(nb['id'].toString()),
                                  onDelete: () async {
                                    await _svc!.delete(nb['id']);
                                    _init();
                                  },
                                ),
                              ),
                              const SizedBox(height: 20),
                            ],

                            // 模板
                            _SectionHeader(title: l10n.templates),
                            const SizedBox(height: 10),
                            SizedBox(
                              height: 122,
                              child: ListView(
                                scrollDirection: Axis.horizontal,
                                clipBehavior: Clip.none,
                                children: [
                                  for (final t in [
                                    (
                                      l10n.tagDataAnalysis,
                                      Icons.bar_chart,
                                      'python',
                                      const (
                                        AppColors.primaryLight,
                                        AppColors.primary,
                                      ),
                                      'data_analysis',
                                    ),
                                    (
                                      l10n.tagMachineLearning,
                                      Icons.psychology,
                                      'python',
                                      const (
                                        Color(0xFFFCE7F3),
                                        Color(0xFFC026D3),
                                      ),
                                      'machine_learning',
                                    ),
                                    (
                                      l10n.templateMathDerivation,
                                      Icons.functions,
                                      'latex',
                                      const (
                                        Color(0xFFEDE9FE),
                                        Color(0xFF8B5CF6),
                                      ),
                                      'math',
                                    ),
                                    (
                                      l10n.tagVisualization,
                                      Icons.show_chart,
                                      'python',
                                      const (
                                        Color(0xFFDCFCE7),
                                        AppColors.success,
                                      ),
                                      'visualization',
                                    ),
                                  ])
                                    _TemplateCard(
                                      name: t.$1,
                                      icon: t.$2,
                                      colors: t.$4,
                                      onTap: () async {
                                        final nb = await _svc!.create(
                                          t.$1,
                                          t.$3,
                                          template: t.$5,
                                        );
                                        if (context.mounted) {
                                          _open(nb.id);
                                        }
                                      },
                                    ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 80),
                          ],
                        ),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final String? action;
  final VoidCallback? onAction;
  const _SectionHeader({required this.title, this.action, this.onAction});
  @override
  Widget build(BuildContext context) => Row(
    children: [
      Text(
        title,
        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
      ),
      const Spacer(),
      if (action != null)
        GestureDetector(
          onTap: onAction,
          child: Text(
            action!,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: AppColors.primary,
            ),
          ),
        ),
    ],
  );
}

class _RecentCard extends StatelessWidget {
  final Map<String, dynamic> nb;
  final VoidCallback onTap;
  final VoidCallback onDelete;
  const _RecentCard({
    required this.nb,
    required this.onTap,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    // 图标字形 + 配色都按稳定 hash 取（同一个 notebook 每次一致），彩色不再
    // 是中性灰——欢迎页重新做活
    final icons = [
      Icons.bar_chart,
      Icons.functions,
      Icons.psychology,
      Icons.code,
      Icons.table_chart,
    ];
    final idx = (nb['id'] as String).hashCode.abs() % _palette.length;
    final (tint, accent) = _palette[idx];
    final lang = nb['lang'] ?? 'python';
    final badgeColor = accent;
    final updatedAt = nb['updatedAt'] as int? ?? 0;
    final diff = DateTime.now().millisecondsSinceEpoch ~/ 1000 - updatedAt;
    final timeStr = diff < 3600
        ? l10n.timeMinutesAgo(diff ~/ 60)
        : diff < 86400
        ? l10n.timeHoursAgo(diff ~/ 3600)
        : l10n.timeDaysAgo(diff ~/ 86400);

    return Dismissible(
      key: Key(nb['id']),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 16),
        decoration: BoxDecoration(
          color: Colors.red,
          borderRadius: BorderRadius.circular(14),
        ),
        child: const Icon(Icons.delete, color: Colors.white),
      ),
      onDismissed: (_) => onDelete(),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: isDark ? Theme.of(context).cardColor : Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              width: 0.5,
              color: isDark ? Theme.of(context).dividerColor : _cardBorder,
            ),
            boxShadow: _cardShadow(isDark),
          ),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: tint,
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Icon(icons[idx], color: accent, size: 23),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      nb['name'] ?? '',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: isDark ? Colors.white : const Color(0xFF1A1A1A),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: badgeColor.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            lang == 'latex'
                                ? 'LaTeX'
                                : lang == 'mixed'
                                ? l10n.langMixed
                                : 'Python',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color: badgeColor,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '${nb['cellCount'] ?? 0} cells',
                          style: const TextStyle(
                            fontSize: 12,
                            color: Color(0xFFCCCCCC),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          timeStr,
                          style: const TextStyle(
                            fontSize: 12,
                            color: Color(0xFFCCCCCC),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.chevron_right,
                color: Color(0xFFC7C7CC),
                size: 20,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TemplateCard extends StatelessWidget {
  final String name;
  final IconData icon;
  final (Color, Color) colors; // ($1=浅底, $2=图标色)
  final VoidCallback onTap;
  const _TemplateCard({
    required this.name,
    required this.icon,
    required this.colors,
    required this.onTap,
  });
  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return GestureDetector(
      onTap: onTap,
      // 英文文案（如"Machine Learning"）比中文长不少，固定95宽+不限行数的
      // Text 在英文下会把卡片撑到底部溢出——加宽一点，并且把文字限制在2行
      // 内、超出省略号收尾。上一版只加了maxLines/ellipsis没提高度，2行文字
      // 实测还是比留给它的34px高2px放不下——这次把卡片和外层横向ListView
      // 的SizedBox都从110提到122，留出实打实的余量，不再卡在临界值上
      child: Container(
        width: 108,
        height: 122,
        margin: const EdgeInsets.only(right: 10),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isDark ? Theme.of(context).cardColor : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            width: 0.5,
            color: isDark ? Theme.of(context).dividerColor : _cardBorder,
          ),
          boxShadow: _cardShadow(isDark),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: colors.$1,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: colors.$2, size: 22),
            ),
            const SizedBox(height: 8),
            Text(
              name,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: isDark ? Colors.white : const Color(0xFF1A1A1A),
              ),
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}

// Hero 底部的几道柔光射线：从底部中间往上发散，紫/蓝/绿低透明度渐变，
// 两头淡出——纯装饰，给深色渐变加一点极光氛围
class _RaysPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final origin = Offset(size.width * 0.5, size.height + 8);
    const dirs = [
      Offset(-0.55, -1),
      Offset(-0.25, -1),
      Offset(0.05, -1),
      Offset(0.38, -1),
      Offset(0.72, -0.9),
    ];
    const tints = [
      Color(0x33A78BFA),
      Color(0x2260A5FA),
      Color(0x334ADE80),
      Color(0x22A78BFA),
      Color(0x2234D399),
    ];
    for (var i = 0; i < dirs.length; i++) {
      final len = size.height * 0.78;
      final end = origin + Offset(dirs[i].dx * len, dirs[i].dy * len);
      final paint = Paint()
        ..strokeWidth = 7
        ..strokeCap = StrokeCap.round
        ..shader = ui.Gradient.linear(
          origin,
          end,
          [const Color(0x00FFFFFF), tints[i], const Color(0x00FFFFFF)],
          const [0.0, 0.35, 1.0],
        );
      canvas.drawLine(origin, end, paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
