import 'package:flutter/material.dart';

import '../models/answer_block.dart';

class AnswerBlockWidget extends StatelessWidget {
  final AnswerBlock block;
  final bool isDark;
  final ValueChanged<String> onChanged;
  final VoidCallback onDelete;
  final FocusNode focusNode;

  const AnswerBlockWidget({
    super.key,
    required this.block,
    required this.isDark,
    required this.onChanged,
    required this.onDelete,
    required this.focusNode,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        _buildContent(context),
        // 删除按钮：右上角，只在 focus 时显示
        Positioned(
          right: 4,
          top: 4,
          child: AnimatedBuilder(
            animation: focusNode,
            builder: (ctx, _) => AnimatedOpacity(
              opacity: focusNode.hasFocus ? 1 : 0,
              duration: const Duration(milliseconds: 150),
              child: GestureDetector(
                onTap: onDelete,
                child: Container(
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(
                    color: isDark
                        ? Colors.white.withValues(alpha: 0.1)
                        : Colors.black.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Icon(
                    Icons.close,
                    size: 13,
                    color: isDark ? Colors.white.withValues(alpha: 0.5) : Colors.grey[500],
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildContent(BuildContext context) {
    switch (block.type) {
      case BlockType.text:
        return _TextBlock(block: block, isDark: isDark, onChanged: onChanged, focusNode: focusNode);
      case BlockType.heading2:
        return _TextBlock(
          block: block,
          isDark: isDark,
          onChanged: onChanged,
          focusNode: focusNode,
          fontSize: 18,
          fontWeight: FontWeight.w700,
          hint: '标题...',
        );
      case BlockType.heading3:
        return _TextBlock(
          block: block,
          isDark: isDark,
          onChanged: onChanged,
          focusNode: focusNode,
          fontSize: 15,
          fontWeight: FontWeight.w600,
          hint: '小标题...',
        );
      case BlockType.quote:
        return _QuoteBlock(block: block, isDark: isDark, onChanged: onChanged, focusNode: focusNode);
      case BlockType.formula:
        return _FormulaBlock(block: block, isDark: isDark, onChanged: onChanged, focusNode: focusNode);
      case BlockType.code:
        return _CodeBlock(block: block, isDark: isDark, onChanged: onChanged, focusNode: focusNode);
      case BlockType.image:
        return _ImageBlock(block: block, isDark: isDark, onChanged: onChanged);
      case BlockType.divider:
        return _DividerBlock(isDark: isDark);
    }
  }
}

class _TextBlock extends StatelessWidget {
  final AnswerBlock block;
  final bool isDark;
  final ValueChanged<String> onChanged;
  final FocusNode focusNode;
  final double fontSize;
  final FontWeight fontWeight;
  final String hint;

  const _TextBlock({
    required this.block,
    required this.isDark,
    required this.onChanged,
    required this.focusNode,
    this.fontSize = 14,
    this.fontWeight = FontWeight.w400,
    this.hint = '写点什么...',
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
      child: TextField(
        focusNode: focusNode,
        controller: TextEditingController(text: block.content)
          ..selection = TextSelection.collapsed(offset: block.content.length),
        maxLines: null,
        onChanged: onChanged,
        style: TextStyle(
          fontSize: fontSize,
          fontWeight: fontWeight,
          height: 1.7,
          color: isDark ? Colors.white.withValues(alpha: 0.9) : const Color(0xFF1A1A1A),
        ),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: TextStyle(
            fontSize: fontSize,
            fontWeight: fontWeight,
            color: isDark ? Colors.white.withValues(alpha: 0.25) : Colors.grey[400],
          ),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(color: const Color(0xFF6366F1).withValues(alpha: 0.3), width: 0.5),
          ),
          enabledBorder: const OutlineInputBorder(
            borderRadius: BorderRadius.all(Radius.circular(8)),
            borderSide: BorderSide(color: Colors.transparent, width: 0.5),
          ),
        ),
      ),
    );
  }
}

class _QuoteBlock extends StatelessWidget {
  final AnswerBlock block;
  final bool isDark;
  final ValueChanged<String> onChanged;
  final FocusNode focusNode;

  const _QuoteBlock({
    required this.block,
    required this.isDark,
    required this.onChanged,
    required this.focusNode,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 2),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF6366F1).withValues(alpha: 0.08) : const Color(0xFFF9F9FF),
        border: const Border(left: BorderSide(color: Color(0xFF6366F1), width: 3)),
        borderRadius: const BorderRadius.only(
          topRight: Radius.circular(8),
          bottomRight: Radius.circular(8),
        ),
      ),
      child: TextField(
        focusNode: focusNode,
        controller: TextEditingController(text: block.content)
          ..selection = TextSelection.collapsed(offset: block.content.length),
        maxLines: null,
        onChanged: onChanged,
        style: TextStyle(
          fontSize: 14,
          fontStyle: FontStyle.italic,
          height: 1.6,
          color: isDark ? Colors.white.withValues(alpha: 0.7) : const Color(0xFF555555),
        ),
        decoration: InputDecoration(
          hintText: '引用内容...',
          hintStyle: TextStyle(
            fontStyle: FontStyle.italic,
            color: isDark ? Colors.white.withValues(alpha: 0.25) : Colors.grey[400],
          ),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.fromLTRB(14, 8, 10, 8),
        ),
      ),
    );
  }
}

class _FormulaBlock extends StatelessWidget {
  final AnswerBlock block;
  final bool isDark;
  final ValueChanged<String> onChanged;
  final FocusNode focusNode;

  const _FormulaBlock({
    required this.block,
    required this.isDark,
    required this.onChanged,
    required this.focusNode,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 2),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF8B5CF6).withValues(alpha: 0.08) : const Color(0xFFFAF0FF),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFF8B5CF6).withValues(alpha: 0.2), width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'LaTeX 公式',
            style: TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.w600,
              letterSpacing: .06,
              color: Color(0xFF8B5CF6),
            ),
          ),
          const SizedBox(height: 6),
          TextField(
            focusNode: focusNode,
            controller: TextEditingController(text: block.content)
              ..selection = TextSelection.collapsed(offset: block.content.length),
            maxLines: null,
            onChanged: onChanged,
            style: const TextStyle(fontSize: 14, fontFamily: 'Georgia', fontStyle: FontStyle.italic, color: Color(0xFF4C1D95)),
            decoration: const InputDecoration(
              hintText: 'f(x) = ...',
              hintStyle: TextStyle(fontFamily: 'Georgia', fontStyle: FontStyle.italic, color: Color(0xFF9CA3AF)),
              border: InputBorder.none,
              contentPadding: EdgeInsets.zero,
            ),
          ),
        ],
      ),
    );
  }
}

class _CodeBlock extends StatelessWidget {
  final AnswerBlock block;
  final bool isDark;
  final ValueChanged<String> onChanged;
  final FocusNode focusNode;

  const _CodeBlock({
    required this.block,
    required this.isDark,
    required this.onChanged,
    required this.focusNode,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 2),
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withValues(alpha: 0.03) : const Color(0xFFF7F7FB),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isDark ? Colors.white.withValues(alpha: 0.08) : const Color(0xFFE8E8EE),
          width: 0.5,
        ),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: isDark ? Colors.white.withValues(alpha: 0.04) : const Color(0xFFF2F2F8),
              border: Border(
                bottom: BorderSide(
                  color: isDark ? Colors.white.withValues(alpha: 0.06) : const Color(0xFFEBEBEB),
                  width: 0.5,
                ),
              ),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(8),
                topRight: Radius.circular(8),
              ),
            ),
            child: Row(
              children: [
                Text(
                  block.language ?? 'Python',
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF6366F1),
                    letterSpacing: .04,
                  ),
                ),
                const Spacer(),
                Text(
                  '复制',
                  style: TextStyle(fontSize: 10, color: isDark ? Colors.white.withValues(alpha: 0.3) : Colors.grey[400]),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(10),
            child: TextField(
              focusNode: focusNode,
              controller: TextEditingController(text: block.content)
                ..selection = TextSelection.collapsed(offset: block.content.length),
              maxLines: null,
              onChanged: onChanged,
              style: TextStyle(
                fontSize: 12,
                fontFamily: 'Menlo',
                height: 1.7,
                color: isDark ? const Color(0xFF93C5FD) : const Color(0xFF1E40AF),
              ),
              decoration: InputDecoration(
                hintText: '# 在此输入代码',
                hintStyle: TextStyle(
                  fontFamily: 'Menlo',
                  fontSize: 12,
                  color: isDark ? Colors.white.withValues(alpha: 0.2) : Colors.grey[400],
                ),
                border: InputBorder.none,
                contentPadding: EdgeInsets.zero,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ImageBlock extends StatelessWidget {
  final AnswerBlock block;
  final bool isDark;
  final ValueChanged<String> onChanged;

  const _ImageBlock({required this.block, required this.isDark, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 2),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isDark ? Colors.white.withValues(alpha: 0.08) : const Color(0xFFEBEBEB),
          width: 0.5,
        ),
      ),
      child: Column(
        children: [
          Container(
            height: 80,
            decoration: BoxDecoration(
              color: isDark ? Colors.white.withValues(alpha: 0.03) : const Color(0xFFF5F5F5),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(8),
                topRight: Radius.circular(8),
              ),
            ),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.image_outlined,
                    size: 28,
                    color: isDark ? Colors.white.withValues(alpha: 0.2) : Colors.grey[300],
                  ),
                  const SizedBox(height: 5),
                  Text(
                    '图片上传即将支持',
                    style: TextStyle(
                      fontSize: 12,
                      color: isDark ? Colors.white.withValues(alpha: 0.2) : Colors.grey[400],
                    ),
                  ),
                ],
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            child: TextField(
              onChanged: onChanged,
              controller: TextEditingController(text: block.content)
                ..selection = TextSelection.collapsed(offset: block.content.length),
              style: TextStyle(
                fontSize: 12,
                color: isDark ? Colors.white.withValues(alpha: 0.4) : Colors.grey[500],
              ),
              decoration: InputDecoration(
                hintText: '图片描述（可选）',
                hintStyle: TextStyle(
                  fontSize: 12,
                  color: isDark ? Colors.white.withValues(alpha: 0.2) : Colors.grey[400],
                ),
                border: InputBorder.none,
                contentPadding: EdgeInsets.zero,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DividerBlock extends StatelessWidget {
  final bool isDark;
  const _DividerBlock({required this.isDark});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: Container(
              height: 0.5,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Colors.transparent,
                    isDark ? Colors.white.withValues(alpha: 0.15) : Colors.grey.withValues(alpha: 0.3),
                  ],
                ),
              ),
            ),
          ),
          ...List.generate(
            3,
            (_) => Container(
              width: 4,
              height: 4,
              margin: const EdgeInsets.symmetric(horizontal: 4),
              decoration: BoxDecoration(
                color: isDark ? Colors.white.withValues(alpha: 0.2) : Colors.grey.withValues(alpha: 0.4),
                shape: BoxShape.circle,
              ),
            ),
          ),
          Expanded(
            child: Container(
              height: 0.5,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    isDark ? Colors.white.withValues(alpha: 0.15) : Colors.grey.withValues(alpha: 0.3),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
