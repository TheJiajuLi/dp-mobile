import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_math_fork/flutter_math.dart';

import 'formula_error.dart';
import 'tutorial_block_renderer.dart';

// 小梦回复内容的统一解析 + 渲染——极索页内直答和小梦对话页共用这一份，
// 不再各写一套正则（以前一处改了另一处漂，比如极索漏了 \(\)/\[\] 定界符
// 导致公式不渲染）。支持：Markdown 文字（标题/加粗/列表）、代码块（复用
// TutorialCodeBlock，自带复制+Pyodide运行）、块级公式 \[...\]/$$...$$、
// 以及**行内公式 \(...\)/$...$ 真正嵌在文字行内流排**（WidgetSpan）。

enum AiSegmentType { text, code, latexBlock, latexInline }

class AiSegment {
  final AiSegmentType type;
  final String content;
  final String language; // 仅 code 用
  const AiSegment({
    required this.type,
    required this.content,
    this.language = '',
  });
}

class _RawSegment {
  final String type;
  final String content;
  final String language;
  const _RawSegment({
    required this.type,
    required this.content,
    this.language = '',
  });
}

// 返回段落列表，每个段落是一串 AiSegment：
// - 代码块 / 块级公式各自独占一个单元素段落
// - 文字按换行拆成段，段内再解析行内公式，做到行内流排
List<List<AiSegment>> parseAiContent(String text) {
  final paragraphs = <List<AiSegment>>[];

  // 先切块级元素：代码块 / \[...\] / $$...$$
  final blockPattern = RegExp(
    r'```(\w*)\n([\s\S]*?)```'
    r'|\\\[([\s\S]*?)\\\]'
    r'|\$\$([\s\S]*?)\$\$',
  );

  var lastEnd = 0;
  final raw = <_RawSegment>[];
  for (final m in blockPattern.allMatches(text)) {
    if (m.start > lastEnd) {
      raw.add(
        _RawSegment(type: 'text', content: text.substring(lastEnd, m.start)),
      );
    }
    if (m.group(2) != null) {
      raw.add(
        _RawSegment(
          type: 'code',
          content: m.group(2)!,
          language: m.group(1) ?? '',
        ),
      );
    } else if (m.group(3) != null) {
      raw.add(_RawSegment(type: 'latexBlock', content: m.group(3)!));
    } else if (m.group(4) != null) {
      raw.add(_RawSegment(type: 'latexBlock', content: m.group(4)!));
    }
    lastEnd = m.end;
  }
  if (lastEnd < text.length) {
    raw.add(_RawSegment(type: 'text', content: text.substring(lastEnd)));
  }

  for (final seg in raw) {
    if (seg.type == 'code') {
      paragraphs.add([
        AiSegment(
          type: AiSegmentType.code,
          content: seg.content,
          language: seg.language,
        ),
      ]);
      continue;
    }
    if (seg.type == 'latexBlock') {
      paragraphs.add([
        AiSegment(type: AiSegmentType.latexBlock, content: seg.content),
      ]);
      continue;
    }
    // 文字段：按行拆，行内解析 \(...\)/$...$
    for (final line in seg.content.split('\n')) {
      if (line.trim().isEmpty) continue;
      paragraphs.add(_parseInline(line));
    }
  }

  return paragraphs;
}

List<AiSegment> _parseInline(String line) {
  final result = <AiSegment>[];
  final inlinePattern = RegExp(
    r'\\\(([\s\S]*?)\\\)'
    r'|\$([^\$\n]+)\$',
  );
  var last = 0;
  for (final m in inlinePattern.allMatches(line)) {
    if (m.start > last) {
      final t = line.substring(last, m.start);
      if (t.isNotEmpty) {
        result.add(AiSegment(type: AiSegmentType.text, content: t));
      }
    }
    final latex = m.group(1) ?? m.group(2) ?? '';
    if (latex.isNotEmpty) {
      result.add(AiSegment(type: AiSegmentType.latexInline, content: latex));
    }
    last = m.end;
  }
  if (last < line.length) {
    final t = line.substring(last);
    if (t.isNotEmpty) {
      result.add(AiSegment(type: AiSegmentType.text, content: t));
    }
  }
  return result.isEmpty
      ? [AiSegment(type: AiSegmentType.text, content: line)]
      : result;
}

class AiContentRenderer extends StatelessWidget {
  final String content;
  final bool isDark;
  const AiContentRenderer({
    super.key,
    required this.content,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    final paragraphs = parseAiContent(content);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: paragraphs.map((segs) {
        if (segs.length == 1 && segs[0].type == AiSegmentType.code) {
          return _buildCodeBlock(segs[0].content, segs[0].language);
        }
        if (segs.length == 1 && segs[0].type == AiSegmentType.latexBlock) {
          return _buildLatexBlock(segs[0].content);
        }
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: _buildTextParagraph(segs),
        );
      }).toList(),
    );
  }

  // 行内公式流排：无公式走 MarkdownBody（标题/加粗/列表），含公式走
  // Text.rich + WidgetSpan 把 Math.tex 嵌进文字行内
  Widget _buildTextParagraph(List<AiSegment> segs) {
    final hasInlineLatex = segs.any(
      (s) => s.type == AiSegmentType.latexInline,
    );
    if (!hasInlineLatex) {
      return MarkdownBody(
        data: segs.map((s) => s.content).join(),
        styleSheet: _mdStyle(),
      );
    }
    return Text.rich(
      TextSpan(
        children: segs.map((seg) {
          if (seg.type == AiSegmentType.text) {
            return TextSpan(
              text: seg.content,
              style: TextStyle(
                fontSize: 15,
                height: 1.8,
                color: isDark
                    ? const Color(0xFFE0E2F0)
                    : const Color(0xFF1A1A1A),
              ),
            );
          }
          return WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: Math.tex(
              seg.content.trim(),
              mathStyle: MathStyle.text,
              textStyle: TextStyle(
                fontSize: 14,
                color: isDark
                    ? const Color(0xFF9B98FF)
                    : const Color(0xFF4F46E5),
              ),
              onErrorFallback: (_) => Text(
                seg.content,
                style: TextStyle(
                  fontSize: 14,
                  color: isDark
                      ? const Color(0xFF9B98FF)
                      : const Color(0xFF4F46E5),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildLatexBlock(String latex) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1A1A35) : const Color(0xFFEEF0FF),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isDark ? const Color(0xFF2A2A50) : const Color(0xFFD0D4FF),
          width: 0.5,
        ),
      ),
      // 宽公式横向滚动，不撑破
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Math.tex(
          latex.trim(),
          mathStyle: MathStyle.display,
          textStyle: TextStyle(
            fontSize: 16,
            color: isDark ? const Color(0xFF9B98FF) : const Color(0xFF4F46E5),
          ),
          onErrorFallback: (_) => const FormulaErrorPlaceholder(),
        ),
      ),
    );
  }

  // 复用现有 TutorialCodeBlock——自带复制 + Pyodide 内联运行(python/js/sql)
  Widget _buildCodeBlock(String code, String lang) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: TutorialCodeBlock(
        content: code.trim(),
        language: lang.isEmpty ? 'python' : lang,
      ),
    );
  }

  MarkdownStyleSheet _mdStyle() => MarkdownStyleSheet(
    p: TextStyle(
      fontSize: 15,
      height: 1.8,
      color: isDark ? const Color(0xFFE0E2F0) : const Color(0xFF1A1A1A),
    ),
    h1: TextStyle(
      fontSize: 20,
      fontWeight: FontWeight.w600,
      color: isDark ? const Color(0xFFF0F2F8) : const Color(0xFF1A1A1A),
    ),
    h2: TextStyle(
      fontSize: 17,
      fontWeight: FontWeight.w600,
      color: isDark ? const Color(0xFFF0F2F8) : const Color(0xFF1A1A1A),
    ),
    h3: TextStyle(
      fontSize: 15,
      fontWeight: FontWeight.w600,
      color: isDark ? const Color(0xFFF0F2F8) : const Color(0xFF1A1A1A),
    ),
    strong: const TextStyle(fontWeight: FontWeight.w600),
    listBullet: TextStyle(
      fontSize: 15,
      color: isDark ? const Color(0xFFE0E2F0) : const Color(0xFF1A1A1A),
    ),
    blockquoteDecoration: BoxDecoration(
      border: const Border(left: BorderSide(color: Color(0xFF6366F1), width: 3)),
      color: isDark ? const Color(0xFF1A1A35) : const Color(0xFFEEF0FF),
    ),
  );
}
