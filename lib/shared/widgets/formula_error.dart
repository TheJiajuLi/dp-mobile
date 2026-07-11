import 'package:flutter/material.dart';

// 公式（Math.tex）渲染失败时的友好占位——不再把一整段红色 LaTeX 源码糊出来。
// 私信/群聊/小梦对话三处公式气泡共用
class FormulaErrorPlaceholder extends StatelessWidget {
  const FormulaErrorPlaceholder({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withValues(alpha: 0.05)
            : const Color(0xFFF5F5F5),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.functions, size: 14, color: Colors.grey[400]),
          const SizedBox(width: 6),
          Text(
            '公式渲染失败',
            style: TextStyle(fontSize: 12, color: Colors.grey[400]),
          ),
        ],
      ),
    );
  }
}
