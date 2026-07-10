import 'package:flutter/material.dart';

import '../models/answer_block.dart';

class BlockPickerSheet extends StatelessWidget {
  final ValueChanged<BlockType> onSelect;

  const BlockPickerSheet({super.key, required this.onSelect});

  static void show(BuildContext context, ValueChanged<BlockType> onSelect) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => BlockPickerSheet(onSelect: onSelect),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? const Color(0xFF1A1A2E) : Colors.white;

    final options = [
      (BlockType.text, '正文', Icons.notes, const Color(0xFF555555), const Color(0xFFF5F5F5)),
      (BlockType.heading2, '标题', Icons.title, const Color(0xFF6366F1), const Color(0xFFEEF2FF)),
      (BlockType.heading3, '小标题', Icons.text_fields, const Color(0xFF16A34A), const Color(0xFFF0FFF4)),
      (BlockType.quote, '引用', Icons.format_quote, const Color(0xFF6366F1), const Color(0xFFEEF0FF)),
      (BlockType.formula, '公式', Icons.functions, const Color(0xFF8B5CF6), const Color(0xFFFAF0FF)),
      (BlockType.code, '代码', Icons.code, const Color(0xFF1D4ED8), const Color(0xFFEFF6FF)),
      (BlockType.image, '图片', Icons.image_outlined, const Color(0xFFD97706), const Color(0xFFFFF7ED)),
      (BlockType.divider, '分割线', Icons.horizontal_rule, const Color(0xFF888888), const Color(0xFFF5F5F5)),
    ];

    return Container(
      decoration: BoxDecoration(
        color: bg,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
      ),
      padding: const EdgeInsets.fromLTRB(8, 12, 8, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 36,
            height: 3,
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
              color: isDark ? Colors.white.withValues(alpha: 0.2) : Colors.grey[300],
              borderRadius: BorderRadius.circular(99),
            ),
          ),
          Text(
            '添加内容块',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              letterSpacing: .06,
              color: isDark ? Colors.white.withValues(alpha: 0.4) : Colors.grey[400],
            ),
          ),
          const SizedBox(height: 10),
          GridView.count(
            crossAxisCount: 4,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            children: options
                .map(
                  (opt) => GestureDetector(
                    onTap: () {
                      Navigator.pop(context);
                      onSelect(opt.$1);
                    },
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: opt.$5,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Icon(opt.$3, size: 22, color: opt.$4),
                        ),
                        const SizedBox(height: 5),
                        Text(
                          opt.$2,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                            color: isDark ? Colors.white.withValues(alpha: 0.7) : const Color(0xFF555555),
                          ),
                        ),
                      ],
                    ),
                  ),
                )
                .toList(),
          ),
        ],
      ),
    );
  }
}
