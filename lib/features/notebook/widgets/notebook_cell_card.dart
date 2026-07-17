import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/notebook_model.dart';
import 'notebook_cell_output.dart';
import 'notebook_code_cell.dart';
import 'notebook_markdown_cell.dart';

// 单张 Cell 卡片：头部（语言点+标签+运行+拖拽/菜单）+ 正文（代码编辑器
// 或 markdown/latex 渲染-编辑）+ 输出区。从 notebook_editor_screen.dart
// 的 _buildCell/_buildCellHeader/_buildCellBody 拆出来，状态（是否激活/
// 运行中/输出内容）全部由父级通过参数传入，这里不读任何 State 字段，
// 只通过回调把交互报给父级
class NotebookCellCard extends StatelessWidget {
  final NotebookCell cell;
  final int index;
  final bool isActive;
  final bool isDark;
  final bool isRunning;
  final TextEditingController controller;
  final FocusNode focusNode;
  final String? output;
  final String? outputType;
  final VoidCallback onActivate;
  final ValueChanged<String> onChanged;
  final VoidCallback onRun;
  final void Function(String type) onAddBelow;
  final VoidCallback onDelete;
  // 点语言 pill 切换代码语言（只对代码类 cell 生效）
  final void Function(String type)? onChangeLanguage;
  // 空白 cell 按 Backspace/Delete 删除本 cell
  final VoidCallback? onEmptyBackspace;
  // 点 ✨ 小梦按钮：代码/公式块 AI 辅助（Pro 门禁在编辑器侧校验）
  final VoidCallback? onAiAssist;
  // 小梦输出区折叠态 + 折叠/展开切换。三态：无输出→onAiAssist 开菜单；有输出且
  // 展开→onAiToggle 折叠；折叠→onAiToggle 展开
  final bool aiCollapsed;
  final VoidCallback? onAiToggle;
  // R Cell 头部的内核状态小指示（加载中/就绪/不可用），由编辑器按 engine.rStatus
  // 构建传入；非 R cell 为 null 不显示
  final Widget? kernelStatus;
  // 保存图表——image 输出下方「保存图表」按钮
  final VoidCallback? onSaveChart;
  // SQL cell 头部下方的「可用表」提示——编辑器扫描已运行的 DataFrame 算出
  final String? tableHint;

  const NotebookCellCard({
    super.key,
    required this.cell,
    required this.index,
    required this.isActive,
    required this.isDark,
    required this.isRunning,
    required this.controller,
    required this.focusNode,
    required this.output,
    required this.outputType,
    required this.onActivate,
    required this.onChanged,
    required this.onRun,
    required this.onAddBelow,
    required this.onDelete,
    this.onChangeLanguage,
    this.onEmptyBackspace,
    this.onAiAssist,
    this.aiCollapsed = false,
    this.onAiToggle,
    this.kernelStatus,
    this.onSaveChart,
    this.tableHint,
  });

  // 复制按钮给代码块/Markdown/LaTeX（图片没有可复制的文本）
  bool get _copyable => cell.type != 'image';

  // AI 辅助只给代码块和公式块（markdown/image 不给）
  bool get _aiEligible =>
      cell.type == 'latex' ||
      const {
        'python',
        'sql',
        'javascript',
        'r',
        'julia',
        'html',
      }.contains(cell.type);

  // 导入数据文件生成的"数据集 cell"——橙色边框 + 暖黄头部 + 数据集徽标
  bool get _isDataset => cell.metadata?['isDataset'] == true;

  // 可视化 cell（python + isVisualization 标记）——绿色边框 + 浅绿头部 +
  // 绿色「可视化」pill（区别于代码块的紫）
  bool get _isViz => cell.metadata?['isVisualization'] == true;

  @override
  Widget build(BuildContext context) {
    // 选中态也走浅灰细描边，不再用偏深的 #CFCFD4 / 深色下的紫框——跟代码块
    // 那种简约、纯净一致，只比 idle 略深一点点点明"这是当前编辑的 cell"
    final activeBorder = isDark
        ? Colors.white.withValues(alpha: 0.12)
        : const Color(0xFFE2E2E6);
    final idleBorder = isDark
        ? Colors.white.withValues(alpha: 0.06)
        : const Color(0xFFEBEBEB);

    return Container(
      key: ValueKey(cell.id),
      margin: const EdgeInsets.fromLTRB(4, 0, 4, 6),
      // 圆角从10涨到14后更显眼——不加这个的话代码块（有色底、没输出区
      // 收口）会在底部露出方角，盖过外层描边的圆角
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1A1A2A) : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: _isViz
              ? const Color(0xFF16A34A)
              : _isDataset
              ? const Color(0xFFD97706)
              : (isActive ? activeBorder : idleBorder),
          width: (_isViz || _isDataset || isActive) ? 1 : 0.5,
        ),
        // 浅色下加一层很淡的浮起阴影——跟底部工具栏同一套（alpha 0.06/
        // blur 12），卡片从背景的紫光晕上"浮"起来，不是纯靠描边贴在背景上
        boxShadow: isDark
            ? null
            : [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 12,
                  offset: const Offset(0, 3),
                ),
              ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeader(context),
          if (cell.type == 'sql' && tableHint != null) _buildSqlTableHint(),
          _buildBody(),
          // 折叠态（aiCollapsed）隐藏输出区，只留顶部 ✨（变灰）供展开
          if (output != null && output!.isNotEmpty && !aiCollapsed)
            Stack(
              children: [
                buildNotebookCellOutput(
                  output!,
                  outputType,
                  isDark,
                  onSaveChart: outputType == 'image' ? onSaveChart : null,
                ),
                // 输出区右上角小 ✨——展开态下继续用 AI 功能（打开菜单）。
                // 不复用顶部那个 ✨（顶部此时管折叠）
                if (_aiEligible && onAiAssist != null)
                  Positioned(top: 6, right: 8, child: _outputRegenBtn()),
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    // 图片块没有可编辑正文，图片本身走输出区渲染
    if (cell.type == 'image') return const SizedBox.shrink();

    if (cell.type == 'markdown' || cell.type == 'latex') {
      return NotebookMarkdownCellBody(
        cellType: cell.type,
        code: cell.code,
        isActive: isActive,
        isDark: isDark,
        controller: controller,
        focusNode: focusNode,
        onActivate: onActivate,
        onChanged: onChanged,
        onEmptyBackspace: onEmptyBackspace,
      );
    }

    return NotebookCodeCellBody(
      cellType: cell.type,
      isDark: isDark,
      controller: controller,
      focusNode: focusNode,
      onTap: onActivate,
      onChanged: onChanged,
      onEmptyBackspace: onEmptyBackspace,
    );
  }

  // SQL cell 专属：头部下方一条细提示，动态显示当前可查询的表（=已运行的
  // DataFrame），让用户不用回翻就知道能 SELECT 哪些表
  Widget _buildSqlTableHint() {
    const sqlColor = Color(0xFF0EA5E9);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      color: isDark
          ? sqlColor.withValues(alpha: 0.06)
          : const Color(0xFFF0F9FF),
      child: Row(
        children: [
          const Icon(Icons.table_chart_outlined, size: 12, color: sqlColor),
          const SizedBox(width: 5),
          Expanded(
            child: Text(
              tableHint!,
              style: const TextStyle(
                fontSize: 11,
                color: sqlColor,
                height: 1.3,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  // Cell 头部：语言彩色 pill + 数据集徽标 + 运行按钮（浅紫方形图标钮），
  // 选中时额外露出拖拽手柄/菜单。跟设计稿一致——语言用带色 pill 直接表意，
  // 运行是独立的图标钮而非文字标签
  Widget _buildHeader(BuildContext context) {
    final headerBg = _isViz
        ? (isDark
              ? const Color(0xFF16A34A).withValues(alpha: 0.10)
              : const Color(0xFFF0FFF5))
        : _isDataset
        ? (isDark
              ? const Color(0xFFD97706).withValues(alpha: 0.10)
              : const Color(0xFFFFFBEB))
        : (isDark
              ? Colors.white.withValues(alpha: 0.03)
              : const Color(0xFFF7F7F9));
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: headerBg,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
        border: Border(
          bottom: BorderSide(
            color: isDark
                ? Colors.white.withValues(alpha: 0.05)
                : const Color(0xFFEFEFEF),
            width: 0.5,
          ),
        ),
      ),
      child: Row(
        children: [
          // 语言 pill 的底色所有 cell 统一用 Python 那种极浅的中性紫（近白）——
          // 不再每种语言各自上色（markdown 的浅绿底会显得发灰），视觉统一；
          // 类型区分只靠文字颜色（Python 紫 / Markdown 绿 / LaTeX violet）
          // 可视化 cell：绿色「可视化」pill（不可切语言）；其余：语言 pill
          if (_isViz)
            Container(
              padding: const EdgeInsets.fromLTRB(9, 4, 9, 4),
              decoration: BoxDecoration(
                color: const Color(
                  0xFF16A34A,
                ).withValues(alpha: isDark ? 0.22 : 0.12),
                borderRadius: BorderRadius.circular(7),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.bar_chart_outlined,
                    size: 12,
                    color: Color(0xFF16A34A),
                  ),
                  SizedBox(width: 4),
                  Text(
                    '可视化',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF16A34A),
                    ),
                  ),
                ],
              ),
            )
          else
            GestureDetector(
              // 代码类 cell 点 pill 可切换语言（弹底部选择器）；markdown/latex/
              // 图片没有"语言"概念，pill 不可点
              onTap: (_isExecutable(cell.type) && onChangeLanguage != null)
                  ? () => showLanguagePickerSheet(
                      context,
                      current: cell.type,
                      onSelect: onChangeLanguage!,
                    )
                  : null,
              child: Container(
                padding: const EdgeInsets.fromLTRB(10, 4, 8, 4),
                decoration: BoxDecoration(
                  color: const Color(
                    0xFF6366F1,
                  ).withValues(alpha: isDark ? 0.22 : 0.12),
                  borderRadius: BorderRadius.circular(7),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _label(cell.type),
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: _langColor(cell.type),
                      ),
                    ),
                    // 可切换时给个下拉小箭头，暗示"点一下能换语言"
                    if (_isExecutable(cell.type) &&
                        onChangeLanguage != null) ...[
                      const SizedBox(width: 3),
                      Icon(
                        Icons.expand_more,
                        size: 14,
                        color: _langColor(cell.type),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          if (_isDataset) ...[
            const SizedBox(width: 8),
            Flexible(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: isDark
                      ? const Color(0xFFD97706).withValues(alpha: 0.20)
                      : const Color(0xFFFEF3C7),
                  borderRadius: BorderRadius.circular(7),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.storage_outlined,
                      size: 11,
                      color: Color(0xFFD97706),
                    ),
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text(
                        '数据集 · ${cell.metadata?['fileName'] ?? '数据'}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFFD97706),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
          if (kernelStatus != null) ...[
            const SizedBox(width: 8),
            kernelStatus!,
          ],
          const Spacer(),
          // 选中时露出拖拽手柄 + 菜单（放在运行按钮左侧，运行按钮保持最右）
          if (isActive) ...[
            ReorderableDragStartListener(
              index: index,
              child: Icon(
                Icons.drag_handle,
                size: 16,
                color: isDark
                    ? const Color(0xFF666666)
                    : const Color(0xFFBBBBBB),
              ),
            ),
            const SizedBox(width: 10),
            GestureDetector(
              onTap: () => showCellActionsSheet(
                context,
                onAddBelow: onAddBelow,
                onDelete: onDelete,
              ),
              child: Icon(
                Icons.more_horiz,
                size: 16,
                color: isDark
                    ? const Color(0xFF666666)
                    : const Color(0xFFBBBBBB),
              ),
            ),
            const SizedBox(width: 10),
            // 复制本 cell 的内容（cell.code）
            if (_copyable) ...[
              GestureDetector(
                onTap: () => _copyCell(context),
                child: Icon(
                  Icons.copy_outlined,
                  size: 15,
                  color: isDark
                      ? const Color(0xFF666666)
                      : const Color(0xFFBBBBBB),
                ),
              ),
              const SizedBox(width: 10),
            ],
          ],
          // ✨ 小梦 AI 辅助——代码/公式块可用，放在运行按钮左侧
          if (_aiEligible && onAiAssist != null) ...[
            _aiButton(),
            const SizedBox(width: 6),
          ],
          if (_isExecutable(cell.type)) _runButton(),
        ],
      ),
    );
  }

  // 复制 cell 内容（cell.code）到剪贴板 + 绿色「已复制」提示
  void _copyCell(BuildContext context) {
    Clipboard.setData(ClipboardData(text: cell.code));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('已复制'),
        duration: Duration(seconds: 1),
        backgroundColor: Color(0xFF16A34A),
      ),
    );
  }

  // ✨ 小梦按钮——严格三态：
  //   无输出       → onAiAssist 开 AI 菜单（紫色）
  //   有输出且展开 → onAiToggle 折叠（点完变灰）
  //   折叠         → onAiToggle 展开（点完变紫）
  // 颜色只跟折叠态走：折叠=灰、否则=紫
  Widget _aiButton() {
    const accent = Color(0xFF6366F1);
    const grey = Color(0xFF9AA0AE);
    final hasOutput = output != null && output!.isNotEmpty;
    final color = aiCollapsed ? grey : accent;
    return GestureDetector(
      onTap: () {
        if (!hasOutput) {
          onAiAssist?.call();
        } else {
          onAiToggle?.call();
        }
      },
      child: Container(
        width: 34,
        height: 28,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: color.withValues(alpha: isDark ? 0.22 : 0.10),
          borderRadius: BorderRadius.circular(9),
        ),
        child: Icon(Icons.auto_awesome_outlined, size: 16, color: color),
      ),
    );
  }

  // 输出区右上角的小 ✨——展开态下点它继续用 AI（打开菜单）
  Widget _outputRegenBtn() {
    const accent = Color(0xFF6366F1);
    return GestureDetector(
      onTap: onAiAssist,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.all(5),
        decoration: BoxDecoration(
          color: (isDark ? Colors.black : Colors.white).withValues(alpha: 0.55),
          borderRadius: BorderRadius.circular(7),
        ),
        child: const Icon(
          Icons.auto_awesome_outlined,
          size: 13,
          color: accent,
        ),
      ),
    );
  }

  // 运行按钮——跟顶栏「全部运行」同款淡紫底紫字胶囊：播放图标 + "运行"，
  // 运行中换成小转圈
  Widget _runButton() {
    const accent = Color(0xFF6366F1);
    return GestureDetector(
      onTap: isRunning ? null : onRun,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: accent.withValues(alpha: isDark ? 0.16 : 0.1),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isRunning)
              const SizedBox(
                width: 13,
                height: 13,
                child: CircularProgressIndicator(
                  strokeWidth: 1.6,
                  color: accent,
                ),
              )
            else
              const Icon(Icons.play_arrow_rounded, size: 15, color: accent),
            const SizedBox(width: 4),
            const Text(
              '运行',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: accent,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // 语言 pill 的主色：代码类紫、markdown 绿、latex violet、图片灰
  Color _langColor(String type) => switch (type) {
    'markdown' => const Color(0xFF16A34A),
    'latex' => const Color(0xFF7C3AED),
    'image' => const Color(0xFF888888),
    _ => const Color(0xFF6366F1),
  };

  String _label(String type) => switch (type) {
    'python' => 'Python',
    'sql' => 'SQL',
    'javascript' => 'JavaScript',
    'r' => 'R',
    'julia' => 'Julia',
    'latex' => 'LaTeX',
    'markdown' => 'Markdown',
    'html' => 'HTML',
    'image' => '图片',
    _ => type,
  };

  bool _isExecutable(String type) =>
      const {'python', 'sql', 'javascript', 'r', 'julia'}.contains(type);
}

// 语言选择器——点代码 cell 的语言 pill 弹出，跟顶栏「更多」同一套底部弹层语言
// （抓手 + 图标方框 + 主/副标题 + 当前项打勾）
void showLanguagePickerSheet(
  BuildContext context, {
  required String current,
  required void Function(String type) onSelect,
}) {
  const langs = [
    ('python', 'Python', '数据分析 · 科学计算', Color(0xFF6366F1)),
    ('javascript', 'JavaScript', '前端逻辑 · 快速脚本', Color(0xFFD97706)),
    ('sql', 'SQL', '跨表查询已定义的 DataFrame', Color(0xFF0EA5E9)),
    ('r', 'R', '统计建模 · 可视化', Color(0xFF2563EB)),
    ('julia', 'Julia', '高性能数值计算', Color(0xFF9333EA)),
  ];
  final isDark = Theme.of(context).brightness == Brightness.dark;
  final card = isDark ? const Color(0xFF17171F) : Colors.white;
  final ink = isDark ? const Color(0xFFF0F2F8) : const Color(0xFF1A1A1A);
  final muted = isDark ? const Color(0xFF7A80A0) : const Color(0xFF888888);

  showModalBottomSheet(
    context: context,
    backgroundColor: Colors.transparent,
    builder: (ctx) => Container(
      decoration: BoxDecoration(
        color: card,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.only(top: 10, bottom: 8),
              decoration: BoxDecoration(
                color: Colors.grey.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(99),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 10),
              child: Row(
                children: [
                  Text(
                    '选择语言',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: ink,
                    ),
                  ),
                ],
              ),
            ),
            for (final l in langs)
              InkWell(
                onTap: () {
                  Navigator.pop(ctx);
                  if (l.$1 != current) onSelect(l.$1);
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 9,
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: l.$4.withValues(alpha: isDark ? 0.22 : 0.12),
                          borderRadius: BorderRadius.circular(11),
                        ),
                        child: Container(
                          width: 12,
                          height: 12,
                          decoration: BoxDecoration(
                            color: l.$4,
                            shape: BoxShape.circle,
                          ),
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              l.$2,
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                                color: ink,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              l.$3,
                              style: TextStyle(fontSize: 12, color: muted),
                            ),
                          ],
                        ),
                      ),
                      if (l.$1 == current)
                        const Icon(
                          Icons.check,
                          size: 18,
                          color: Color(0xFF6366F1),
                        ),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    ),
  );
}

// Cell ⋯ 菜单：下方添加各类型 / 删除
void showCellActionsSheet(
  BuildContext context, {
  required void Function(String type) onAddBelow,
  required VoidCallback onDelete,
}) {
  showModalBottomSheet(
    context: context,
    backgroundColor: Colors.transparent,
    builder: (ctx) => Container(
      decoration: BoxDecoration(
        color: Theme.of(ctx).cardColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final t in const [
              ('markdown', '下方添加文字'),
              ('python', '下方添加代码'),
              ('latex', '下方添加公式'),
            ])
              ListTile(
                tileColor: Colors.transparent,
                leading: const Icon(Icons.add, size: 20),
                title: Text(t.$2),
                onTap: () {
                  Navigator.pop(ctx);
                  onAddBelow(t.$1);
                },
              ),
            ListTile(
              tileColor: Colors.transparent,
              leading: const Icon(
                Icons.delete_outline,
                size: 20,
                color: Color(0xFFDC2626),
              ),
              title: const Text(
                '删除此块',
                style: TextStyle(color: Color(0xFFDC2626)),
              ),
              onTap: () {
                Navigator.pop(ctx);
                onDelete();
              },
            ),
          ],
        ),
      ),
    ),
  );
}
