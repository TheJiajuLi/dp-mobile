import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_math_fork/flutter_math.dart';

import '../../../shared/utils/latex_utils.dart';

// markdown/latex cell 的正文：未选中=渲染结果，选中=纯文本编辑。从
// notebook_editor_screen.dart 的 _buildCellBody 里拆出来，只处理这两种
// 类型（代码类走 notebook_code_cell.dart）
class NotebookMarkdownCellBody extends StatelessWidget {
  final String cellType; // 'markdown' | 'latex'
  final String code;
  final bool isActive;
  final bool isDark;
  final TextEditingController controller;
  final FocusNode focusNode;
  final VoidCallback onActivate;
  final ValueChanged<String> onChanged;
  // 空白 cell 按 Backspace/Delete 时删除本 cell（内容非空时不拦）
  final VoidCallback? onEmptyBackspace;

  const NotebookMarkdownCellBody({
    super.key,
    required this.cellType,
    required this.code,
    required this.isActive,
    required this.isDark,
    required this.controller,
    required this.focusNode,
    required this.onActivate,
    required this.onChanged,
    this.onEmptyBackspace,
  });

  // 包一层 Focus 拦 Backspace/Delete：空内容删本 cell，非空 ignored 交回输入框
  KeyEventResult _handleBackspace(KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final isDeleteKey =
        event.logicalKey == LogicalKeyboardKey.backspace ||
        event.logicalKey == LogicalKeyboardKey.delete;
    if (!isDeleteKey ||
        controller.text.isNotEmpty ||
        onEmptyBackspace == null) {
      return KeyEventResult.ignored;
    }
    onEmptyBackspace!();
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    if (!isActive) {
      return GestureDetector(
        onTap: onActivate,
        behavior: HitTestBehavior.opaque,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          child: code.trim().isEmpty
              ? Text(
                  cellType == 'latex' ? '点击输入 LaTeX 公式…' : '点击输入 Markdown…',
                  style: TextStyle(
                    fontSize: 13,
                    color: isDark
                        ? const Color(0xFF444444)
                        : const Color(0xFFCCCCCC),
                  ),
                )
              : cellType == 'latex'
              ? Math.tex(
                  preprocessLatex(code.trim()),
                  textStyle: TextStyle(
                    fontSize: 16,
                    color: isDark
                        ? const Color(0xFFE0E2F0)
                        : const Color(0xFF1A1A1A),
                  ),
                  onErrorFallback: (err) => Text(
                    code,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12,
                      color: Color(0xFFDC2626),
                    ),
                  ),
                )
              : MarkdownBody(
                  data: code,
                  styleSheet: MarkdownStyleSheet(
                    p: TextStyle(
                      fontSize: 14,
                      height: 1.6,
                      color: isDark
                          ? const Color(0xFFE0E2F0)
                          : const Color(0xFF1A1A1A),
                    ),
                  ),
                ),
        ),
      );
    }

    return Focus(
      onKeyEvent: (node, event) => _handleBackspace(event),
      // 限高 200：超出后编辑框内部自滚，不再无限撑高整个 Cell
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 200),
        child: TextField(
          controller: controller,
          focusNode: focusNode,
          maxLines: null,
        onTap: onActivate,
        // LaTeX 里直引号被替换成弯引号会破坏语法，公式块也关掉智能标点
        smartQuotesType: cellType == 'latex'
            ? SmartQuotesType.disabled
            : SmartQuotesType.enabled,
        smartDashesType: cellType == 'latex'
            ? SmartDashesType.disabled
            : SmartDashesType.enabled,
        style: TextStyle(
          fontSize: 14,
          height: 1.6,
          color: isDark ? const Color(0xFFE0E2F0) : const Color(0xFF1A1A1A),
        ),
        decoration: InputDecoration(
          // 同 code cell：显式关掉全局 InputDecorationTheme 的 filled 灰底，
          // 编辑 markdown/latex 时正文区也保持白底一致
          filled: false,
          border: InputBorder.none,
          isDense: true,
          contentPadding: const EdgeInsets.all(12),
          hintText: cellType == 'latex' ? '输入 LaTeX 公式…' : '输入 Markdown 内容…',
          hintStyle: TextStyle(
            fontSize: 14,
            color: isDark ? const Color(0xFF444444) : const Color(0xFFCCCCCC),
          ),
        ),
          onChanged: onChanged,
        ),
      ),
    );
  }
}
