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

// 下面几个编辑类 block 之前是 StatelessWidget，TextField 的 controller
// 直接在 build() 里 new TextEditingController(...)——每次父级 setState
// （比如输入一个字触发 onChanged）都会重新创建一个新的 Controller 实例，
// 这会打断中文输入法的 composing 状态：候选词还没上屏，Controller 就被
// 换掉了，表现就是拼音字母直接原样上屏，打不出汉字。改成 StatefulWidget，
// Controller 在 initState 里只创建一次，父级重建时靠 State 复用，不会
// 重新 new，composing 状态不会被打断

class _TextBlock extends StatefulWidget {
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
  State<_TextBlock> createState() => _TextBlockState();
}

class _TextBlockState extends State<_TextBlock> {
  late final _ctrl = TextEditingController(text: widget.block.content)
    ..selection = TextSelection.collapsed(offset: widget.block.content.length);

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
      child: TextField(
        focusNode: widget.focusNode,
        controller: _ctrl,
        maxLines: null,
        onChanged: widget.onChanged,
        style: TextStyle(
          fontSize: widget.fontSize,
          fontWeight: widget.fontWeight,
          height: 1.7,
          color: widget.isDark ? Colors.white.withValues(alpha: 0.9) : const Color(0xFF1A1A1A),
        ),
        decoration: InputDecoration(
          hintText: widget.hint,
          hintStyle: TextStyle(
            fontSize: widget.fontSize,
            fontWeight: widget.fontWeight,
            color: widget.isDark ? Colors.white.withValues(alpha: 0.25) : Colors.grey[400],
          ),
          // 全局 InputDecorationTheme 深色下 filled:true+darkSurface，不显式
          // 关掉会透出一层深灰"夹心"，盖住正文气泡本身的底色（踩坑#13）
          filled: false,
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

class _QuoteBlock extends StatefulWidget {
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
  State<_QuoteBlock> createState() => _QuoteBlockState();
}

class _QuoteBlockState extends State<_QuoteBlock> {
  late final _ctrl = TextEditingController(text: widget.block.content)
    ..selection = TextSelection.collapsed(offset: widget.block.content.length);

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = widget.isDark;
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
        focusNode: widget.focusNode,
        controller: _ctrl,
        maxLines: null,
        onChanged: widget.onChanged,
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
          filled: false, // 见踩坑#13：不关掉全局 filled 会透出深灰底盖住引用块底色
          border: InputBorder.none,
          contentPadding: const EdgeInsets.fromLTRB(14, 8, 10, 8),
        ),
      ),
    );
  }
}

class _FormulaBlock extends StatefulWidget {
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
  State<_FormulaBlock> createState() => _FormulaBlockState();
}

class _FormulaBlockState extends State<_FormulaBlock> {
  late final _ctrl = TextEditingController(text: widget.block.content)
    ..selection = TextSelection.collapsed(offset: widget.block.content.length);

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = widget.isDark;
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
            focusNode: widget.focusNode,
            controller: _ctrl,
            maxLines: null,
            onChanged: widget.onChanged,
            style: const TextStyle(fontSize: 14, fontFamily: 'Georgia', fontStyle: FontStyle.italic, color: Color(0xFF4C1D95)),
            decoration: const InputDecoration(
              hintText: 'f(x) = ...',
              hintStyle: TextStyle(fontFamily: 'Georgia', fontStyle: FontStyle.italic, color: Color(0xFF9CA3AF)),
              filled: false, // 见踩坑#13
              border: InputBorder.none,
              contentPadding: EdgeInsets.zero,
            ),
          ),
        ],
      ),
    );
  }
}

class _CodeBlock extends StatefulWidget {
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
  State<_CodeBlock> createState() => _CodeBlockState();
}

class _CodeBlockState extends State<_CodeBlock> {
  late final _ctrl = TextEditingController(text: widget.block.content)
    ..selection = TextSelection.collapsed(offset: widget.block.content.length);

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = widget.isDark;
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
                  widget.block.language ?? 'Python',
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
              focusNode: widget.focusNode,
              controller: _ctrl,
              maxLines: null,
              onChanged: widget.onChanged,
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
                filled: false, // 见踩坑#13
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

class _ImageBlock extends StatefulWidget {
  final AnswerBlock block;
  final bool isDark;
  final ValueChanged<String> onChanged;

  const _ImageBlock({required this.block, required this.isDark, required this.onChanged});

  @override
  State<_ImageBlock> createState() => _ImageBlockState();
}

class _ImageBlockState extends State<_ImageBlock> {
  late final _ctrl = TextEditingController(text: widget.block.content)
    ..selection = TextSelection.collapsed(offset: widget.block.content.length);

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = widget.isDark;
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
              controller: _ctrl,
              onChanged: widget.onChanged,
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
