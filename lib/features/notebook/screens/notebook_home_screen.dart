import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../features/auth/auth_service.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../../shared/utils/greeting.dart';
import '../services/notebook_service.dart';

// 中性主色（原品牌紫 #6366F1 已下线）：主按钮/强调用近黑，图标用中性灰。
const _accent = Color(0xFF1A1A1A);

// leading 图标容器的浅色底：按 notebook 的语言/类型分组取中性色调
// （不再是品牌色或饱和色）。
Color _langTint(String lang) => switch (lang) {
  'python' ||
  'sql' ||
  'javascript' ||
  'r' ||
  'julia' => const Color(0xFFF0F0F8),
  'latex' || 'math' || 'markdown' => const Color(0xFFF0F8F0),
  _ => const Color(0xFFFFF8F0),
};

// leading 图标里的字形色——跟着语言分组走一点点色彩暗示（代码类偏冷灰蓝、
// 公式/数学类偏冷绿），比一律 #888 更有识别度，但仍克制、不抢眼
Color _langIcon(String lang) => switch (lang) {
  'python' ||
  'sql' ||
  'javascript' ||
  'r' ||
  'julia' => const Color(0xFF7C7F9E),
  'latex' || 'math' || 'markdown' => const Color(0xFF6E9E7C),
  _ => const Color(0xFF9E8A6E),
};

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
  const NotebookHomeScreen({super.key});
  @override
  ConsumerState<NotebookHomeScreen> createState() => _State();
}

class _State extends ConsumerState<NotebookHomeScreen> {
  List<Map<String, dynamic>> _recent = [];
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
                  for (final t in [
                    ('python', 'Python', Icons.code),
                    ('latex', 'LaTeX', Icons.functions),
                    ('mixed', l10n.langMixed, Icons.layers),
                  ])
                    Expanded(
                      child: GestureDetector(
                        onTap: () => setState(() => type = t.$1),
                        child: Container(
                          margin: const EdgeInsets.only(right: 8),
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          decoration: BoxDecoration(
                            // 未选中不再用填充背景（深色下会糊成白块），
                            // 跟选中态一样只用边框区分
                            color: type == t.$1
                                ? _accent.withValues(alpha: 0.08)
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: type == t.$1
                                  ? _accent
                                  : Colors.grey.withValues(alpha: 0.35),
                            ),
                          ),
                          child: Column(
                            children: [
                              Icon(
                                t.$3,
                                color: type == t.$1 ? _accent : Colors.grey,
                                size: 20,
                              ),
                              const SizedBox(height: 4),
                              Text(
                                t.$2,
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                  color: type == t.$1
                                      ? _accent
                                      : Colors.grey[600],
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
                    if (mounted) context.push('/notebook/${nb.id}');
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _accent,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: Text(
                    l10n.create,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ],
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
                      const Spacer(),
                      // 新建：黑底白字（Notebook 已去紫化，唯一的紫留给编辑器里
                      // 每个 cell 的「▶运行」）
                      GestureDetector(
                        onTap: _showNewSheet,
                        child: Container(
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                            color: _accent,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(
                            Icons.add,
                            color: Colors.white,
                            size: 18,
                          ),
                        ),
                      ),
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
                            // Hero
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(20),
                              margin: const EdgeInsets.only(bottom: 24),
                              decoration: BoxDecoration(
                                color: isDark
                                    ? Theme.of(context).cardColor
                                    : Colors.white,
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(
                                  color: isDark
                                      ? Theme.of(context).dividerColor
                                      : _cardBorder,
                                  width: 0.5,
                                ),
                                boxShadow: _cardShadow(isDark),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    greetingText(context),
                                    style: const TextStyle(
                                      fontSize: 13,
                                      color: Color(0xFFAAAAAA),
                                      letterSpacing: 0.3,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    l10n.whereToStart,
                                    style: TextStyle(
                                      fontSize: 24,
                                      fontWeight: FontWeight.w700,
                                      height: 1.2,
                                      color: isDark
                                          ? Colors.white
                                          : const Color(0xFF1A1A1A),
                                    ),
                                  ),
                                  const SizedBox(height: 18),
                                  SizedBox(
                                    width: double.infinity,
                                    height: 50,
                                    child: ElevatedButton(
                                      onPressed: _showNewSheet,
                                      style: ElevatedButton.styleFrom(
                                        // Notebook 已去紫化，主操作用近黑
                                        backgroundColor: _accent,
                                        elevation: 0,
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(
                                            14,
                                          ),
                                        ),
                                      ),
                                      child: Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: [
                                          const Icon(
                                            Icons.add,
                                            color: Colors.white,
                                            size: 18,
                                          ),
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
                                ],
                              ),
                            ),

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
                                  onTap: () =>
                                      context.push('/notebook/${nb['id']}'),
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
                                    ),
                                    (
                                      l10n.tagMachineLearning,
                                      Icons.psychology,
                                      'python',
                                    ),
                                    (
                                      l10n.templateMathDerivation,
                                      Icons.functions,
                                      'latex',
                                    ),
                                    (
                                      l10n.tagVisualization,
                                      Icons.show_chart,
                                      'python',
                                    ),
                                  ])
                                    _TemplateCard(
                                      name: t.$1,
                                      icon: t.$2,
                                      lang: t.$3,
                                      onTap: () async {
                                        final nb = await _svc!.create(
                                          t.$1,
                                          t.$3,
                                        );
                                        if (context.mounted) {
                                          context.push('/notebook/${nb.id}');
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
            style: const TextStyle(fontSize: 14, color: Color(0xFF888888)),
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
    // 图标字形仍按稳定 hash 取，只是颜色统一为中性灰、底色按语言分组
    final icons = [
      Icons.bar_chart,
      Icons.functions,
      Icons.psychology,
      Icons.code,
      Icons.table_chart,
    ];
    final idx = (nb['id'] as String).hashCode.abs() % 5;
    final lang = nb['lang'] ?? 'python';
    // 语言标签用中性灰，不再用品牌/饱和色
    const badgeColor = Color(0xFF888888);
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
                  color: _langTint(lang),
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Icon(icons[idx], color: _langIcon(lang), size: 23),
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
                            style: const TextStyle(
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
  final String lang;
  final VoidCallback onTap;
  const _TemplateCard({
    required this.name,
    required this.icon,
    required this.lang,
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
                color: _langTint(lang),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: _langIcon(lang), size: 22),
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
