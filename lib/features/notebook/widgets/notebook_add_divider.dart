import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';

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
          // 去掉紫色 pill 底色，只留一圈浅灰描边——跟代码块那种简约、纯净
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isDark
                ? Colors.white.withValues(alpha: 0.06)
                : const Color(0xFFEBEBEB),
            width: 0.5,
          ),
        ),
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.add, size: 15, color: AppColors.primary),
            SizedBox(width: 6),
            Text(
              '添加内容块',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppColors.primary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
