import 'package:flutter/material.dart';

// 末尾「添加内容块」按钮——挂在 Cell 画布 ReorderableListView 的 footer，
// 从 notebook_editor_screen.dart 抽出来
class NotebookAddDivider extends StatelessWidget {
  final bool isDark;
  final VoidCallback onTap;

  const NotebookAddDivider({
    super.key,
    required this.isDark,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      key: const ValueKey('__final_add__'),
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.fromLTRB(4, 2, 4, 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(
            0xFF6366F1,
          ).withValues(alpha: isDark ? 0.08 : 0.05),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: const Color(
              0xFF6366F1,
            ).withValues(alpha: isDark ? 0.2 : 0.15),
            width: 1,
          ),
        ),
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.add, size: 15, color: Color(0xFF6366F1)),
            SizedBox(width: 6),
            Text(
              '添加内容块',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Color(0xFF6366F1),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
