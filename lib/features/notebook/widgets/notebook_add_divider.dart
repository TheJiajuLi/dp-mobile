import 'package:flutter/material.dart';

// 末尾「添加内容块」按钮——挂在 Cell 画布 ReorderableListView 的 footer，
// 从 notebook_editor_screen.dart 抽出来
class NotebookAddDivider extends StatelessWidget {
  final bool isDark;
  final VoidCallback onTap;

  const NotebookAddDivider({super.key, required this.isDark, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      key: const ValueKey('__final_add__'),
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.fromLTRB(4, 2, 4, 8),
        padding: const EdgeInsets.all(11),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isDark
                ? Colors.white.withValues(alpha: 0.08)
                : const Color(0xFFDDDDDD),
            width: 0.5,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.add,
              size: 14,
              color: isDark ? const Color(0xFF444444) : const Color(0xFFCCCCCC),
            ),
            const SizedBox(width: 6),
            Text(
              '添加内容块',
              style: TextStyle(
                fontSize: 12,
                color: isDark ? const Color(0xFF444444) : const Color(0xFFCCCCCC),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
