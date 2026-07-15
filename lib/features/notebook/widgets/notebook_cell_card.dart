import 'package:flutter/material.dart';

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
  });

  // 导入数据文件生成的"数据集 cell"——橙色边框 + 暖黄头部 + 数据集徽标
  bool get _isDataset => cell.metadata?['isDataset'] == true;

  @override
  Widget build(BuildContext context) {
    final activeBorder = isDark
        ? const Color(0xFF6366F1).withValues(alpha: 0.4)
        : const Color(0xFFCFCFD4);
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
          color: _isDataset
              ? const Color(0xFFD97706)
              : (isActive ? activeBorder : idleBorder),
          width: (_isDataset || isActive) ? 1 : 0.5,
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
          _buildBody(),
          if (output != null && output!.isNotEmpty)
            buildNotebookCellOutput(output!, outputType, isDark),
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
      );
    }

    return NotebookCodeCellBody(
      cellType: cell.type,
      isDark: isDark,
      controller: controller,
      focusNode: focusNode,
      onTap: onActivate,
      onChanged: onChanged,
    );
  }

  // Cell 头部：语言彩色 pill + 数据集徽标 + 运行按钮（浅紫方形图标钮），
  // 选中时额外露出拖拽手柄/菜单。跟设计稿一致——语言用带色 pill 直接表意，
  // 运行是独立的图标钮而非文字标签
  Widget _buildHeader(BuildContext context) {
    final headerBg = _isDataset
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
          // 语言彩色 pill——Python 紫 / Markdown 绿 / LaTeX violet…
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: _langColor(
                cell.type,
              ).withValues(alpha: isDark ? 0.22 : 0.12),
              borderRadius: BorderRadius.circular(7),
            ),
            child: Text(
              _label(cell.type),
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: _langColor(cell.type),
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
          ],
          if (_isExecutable(cell.type)) _runButton(),
        ],
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
