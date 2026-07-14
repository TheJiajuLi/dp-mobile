import 'package:flutter/material.dart';

import '../models/answer_block.dart';

class FormatToolbar extends StatelessWidget {
  final ValueChanged<BlockType> onAddBlock;
  final VoidCallback onBold;
  final VoidCallback onItalic;

  const FormatToolbar({
    super.key,
    required this.onAddBlock,
    required this.onBold,
    required this.onItalic,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final divColor = isDark ? Colors.white.withValues(alpha: 0.06) : const Color(0xFFEBEBEB);

    return Container(
      height: 44,
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF0D0D1A) : const Color(0xFFFAFAF8),
        border: Border(top: BorderSide(color: divColor, width: 0.5)),
      ),
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        children: [
          _FmtBtn('B', onBold, bold: true, isDark: isDark),
          _FmtBtn('I', onItalic, italic: true, isDark: isDark),
          _Sep(isDark: isDark),
          _FmtBtn('H2', () => onAddBlock(BlockType.heading2), isDark: isDark),
          _FmtBtn('H3', () => onAddBlock(BlockType.heading3), isDark: isDark),
          _FmtBtn('❝', () => onAddBlock(BlockType.quote), isDark: isDark),
          _Sep(isDark: isDark),
          _FmtBtn('∑', () => onAddBlock(BlockType.formula), isDark: isDark),
          _FmtBtn('</>', () => onAddBlock(BlockType.code), isDark: isDark),
          // 图片上传后端未上线，暂时不提供入口（原来点进去只是个"即将支持"占位）
        ],
      ),
    );
  }
}

class _FmtBtn extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  final bool bold;
  final bool italic;
  final bool isDark;

  const _FmtBtn(
    this.label,
    this.onTap, {
    this.bold = false,
    this.italic = false,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(right: 4),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(borderRadius: BorderRadius.circular(6)),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: bold ? FontWeight.w900 : FontWeight.w500,
            fontStyle: italic ? FontStyle.italic : FontStyle.normal,
            color: isDark ? Colors.white.withValues(alpha: 0.6) : const Color(0xFF555555),
          ),
        ),
      ),
    );
  }
}

class _Sep extends StatelessWidget {
  final bool isDark;
  const _Sep({required this.isDark});

  @override
  Widget build(BuildContext context) => Container(
    width: 0.5,
    height: 20,
    margin: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
    color: isDark ? Colors.white.withValues(alpha: 0.1) : const Color(0xFFE0E0E0),
  );
}
