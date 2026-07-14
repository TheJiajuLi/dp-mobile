import 'package:flutter/material.dart';

// 代码类 cell（python/sql/javascript/r/julia/html）的正文——始终是等宽
// 编辑框，跟 markdown/latex 那种"未选中渲染/选中编辑"不是一回事，从
// notebook_editor_screen.dart 的 _buildCellBody 里拆出来
class NotebookCodeCellBody extends StatelessWidget {
  final String cellType;
  final bool isDark;
  final TextEditingController controller;
  final FocusNode focusNode;
  final VoidCallback onTap;
  final ValueChanged<String> onChanged;

  const NotebookCodeCellBody({
    super.key,
    required this.cellType,
    required this.isDark,
    required this.controller,
    required this.focusNode,
    required this.onTap,
    required this.onChanged,
  });

  static String hintFor(String type) => switch (type) {
    'sql' => '-- 输入 SQL…',
    _ => '# 输入代码…',
  };

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: isDark ? Colors.transparent : const Color(0xFFF8F9FC),
      child: TextField(
        controller: controller,
        focusNode: focusNode,
        maxLines: null,
        onTap: onTap,
        style: TextStyle(
          fontFamily: 'monospace',
          fontSize: 12,
          height: 1.7,
          color: isDark ? const Color(0xFFE0E2F0) : const Color(0xFF1A1A1A),
        ),
        decoration: InputDecoration(
          border: InputBorder.none,
          isDense: true,
          contentPadding: const EdgeInsets.all(12),
          hintText: hintFor(cellType),
          hintStyle: TextStyle(
            fontFamily: 'monospace',
            fontSize: 12,
            color: isDark ? const Color(0xFF444444) : const Color(0xFFCCCCCC),
          ),
        ),
        onChanged: onChanged,
      ),
    );
  }
}
