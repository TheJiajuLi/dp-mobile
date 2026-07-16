import 'package:flutter/material.dart';
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
  });

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

    return TextField(
      controller: controller,
      focusNode: focusNode,
      maxLines: null,
      onTap: onActivate,
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
    );
  }
}
