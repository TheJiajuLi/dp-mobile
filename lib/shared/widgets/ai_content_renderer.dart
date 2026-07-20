import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_math_fork/flutter_math.dart';

import '../utils/latex_utils.dart';

import 'tutorial_block_renderer.dart';

// 小梦回复内容的统一解析 + 渲染——极索页内直答和小梦对话页共用这一份，
// 不再各写一套正则（以前一处改了另一处漂，比如极索漏了 \(\)/\[\] 定界符
// 导致公式不渲染）。支持：Markdown 文字（标题/加粗/列表）、代码块（复用
// TutorialCodeBlock，自带复制+Pyodide运行）、块级公式 \[...\]/$$...$$、
// 以及**行内公式 \(...\)/$...$ 真正嵌在文字行内流排**（WidgetSpan）。

enum AiSegmentType { text, code, latexBlock, latexInline, image }

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
// - 两个块级元素之间的整段文字一起解析行内公式（不按行拆，跨行 \(...\)
//   也能配上闭合），渲染层再按行补 Markdown（标题/加粗/列表）
List<List<AiSegment>> parseAiContent(String text) {
  final paragraphs = <List<AiSegment>>[];

  // 先切块级元素：代码块 / \[...\] / $$...$$
  // 定界符用 \\+ 而不是 \\——小梦（和多数大模型）经常把 LaTeX 定界符
  // 双重转义成 \\[...\\]，收尾用 \\+ 会把结尾多余的反斜杠全吃掉，不然
  // 会漏一个 \ 进公式内容里让 Math.tex 直接报错、退化成纯文字（这正是
  // "看起来没渲染成 LaTeX"的根因）。dotAll 冗余但保底
  final blockPattern = RegExp(
    r'```(\w*)\n([\s\S]*?)```'
    r'|\\+\[([\s\S]*?)\\+\]'
    r'|\$\$([\s\S]*?)\$\$'
    // 图片：![alt](url) —— 论坛帖子里图片块序列化成这个语法（group 5=url）
    r'|!\[[^\]]*\]\(([^)]+)\)',
    dotAll: true,
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
    } else if (m.group(5) != null) {
      raw.add(_RawSegment(type: 'image', content: m.group(5)!.trim()));
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
    if (seg.type == 'image') {
      paragraphs.add([
        AiSegment(type: AiSegmentType.image, content: seg.content),
      ]);
      continue;
    }
    // 文字段：整段一起解析行内公式，**不按行拆**——不然跨行的 \(...\)
    // （开定界在这行、闭定界在下一行）永远配不上闭合，会原样露出 \( 和
    // 公式源码（Bug 2）。块级 Markdown（标题/加粗/列表）留到渲染层处理
    if (seg.content.trim().isEmpty) continue;
    paragraphs.add(_parseInlineMultiline(seg.content));
  }

  return paragraphs;
}

// 整段（可能多行）解析行内公式。\(...\) 用 [\s\S]*? 可跨行；单 $...$ 仍
// 限定在同一行（[^\$\n]+），因为真实数学里 $…$ 几乎不跨行，放开跨行反而
// 容易被正文里落单的一个 $ 吃掉一大段
List<AiSegment> _parseInlineMultiline(String text) {
  final result = <AiSegment>[];
  final inlinePattern = RegExp(
    r'\\+\(([\s\S]*?)\\+\)'
    r'|\$([^\$\n]+)\$',
    multiLine: true,
    dotAll: true,
  );
  var last = 0;
  for (final m in inlinePattern.allMatches(text)) {
    if (m.start > last) {
      final t = text.substring(last, m.start);
      if (t.isNotEmpty) {
        result.add(AiSegment(type: AiSegmentType.text, content: t));
      }
    }
    final latex = m.group(1) ?? m.group(2) ?? '';
    if (latex.trim().isNotEmpty) {
      result.add(
        AiSegment(type: AiSegmentType.latexInline, content: latex.trim()),
      );
    }
    last = m.end;
  }
  if (last < text.length) {
    final t = text.substring(last);
    if (t.isNotEmpty) {
      result.add(AiSegment(type: AiSegmentType.text, content: t));
    }
  }
  return result.isEmpty
      ? [AiSegment(type: AiSegmentType.text, content: text)]
      : result;
}

class AiContentRenderer extends StatelessWidget {
  final String content;
  final bool isDark;
  // true 时代码块底部多一个「在 Notebook 运行」按钮（极索 CoT 回答用）——
  // 其它场景（论坛/小梦聊天/发布预览）默认关，不额外加建 Notebook 入口
  final bool codeToNotebook;
  const AiContentRenderer({
    super.key,
    required this.content,
    required this.isDark,
    this.codeToNotebook = false,
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
        if (segs.length == 1 && segs[0].type == AiSegmentType.image) {
          return _buildImage(segs[0].content);
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
    final hasInlineLatex = segs.any((s) => s.type == AiSegmentType.latexInline);
    // 纯文字（无行内公式）走 MarkdownBody，标题/加粗/列表/表格全套都有
    if (!hasInlineLatex) {
      return MarkdownBody(
        data: segs.map((s) => s.content).join(),
        styleSheet: _mdStyle(),
      );
    }
    // 含行内公式：必须走 Text.rich 才能把公式嵌进文字流，但 Text.rich 不
    // 认 Markdown，所以对文字片段做一层轻量 Markdown（行首 #/##/### 标题、
    // -/* 列表、行内 **加粗**）——不然 ###、** 会原样露出来（Bug 1）
    final spans = <InlineSpan>[];
    for (final seg in segs) {
      if (seg.type == AiSegmentType.latexInline) {
        spans.add(
          WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: Math.tex(
              preprocessLatex(seg.content.trim()),
              mathStyle: MathStyle.text,
              textStyle: _bodyStyle(),
              onErrorFallback: (_) => _latexError(seg.content),
            ),
          ),
        );
      } else {
        spans.addAll(_markdownLiteSpans(seg.content));
      }
    }
    return Text.rich(TextSpan(children: spans));
  }

  // 混排段落里的文字片段可能是多行的（整段一起解析，不再按行拆），逐行
  // 判断行首标题/列表标记，行内再处理 **加粗**，其余原样。换行用 \n span
  // 保留，公式片段由调用方以 WidgetSpan 插在这些 span 之间
  List<InlineSpan> _markdownLiteSpans(String text) {
    final spans = <InlineSpan>[];
    final lines = text.split('\n');
    for (var i = 0; i < lines.length; i++) {
      var line = lines[i];
      var base = _bodyStyle();
      // #{1,6}——小梦经常用 #### 当小节标题，只认 1-3 会让 #### 原样露出来
      // （截图里的"#### 直观理解/例子/关键概念"）。sizes 补满 6 级，避免
      // level>3 时越界
      final heading = RegExp(r'^(#{1,6})\s+').firstMatch(line);
      if (heading != null) {
        final level = heading.group(1)!.length;
        line = line.substring(heading.end);
        const sizes = [20.0, 17.0, 15.0, 14.0, 13.5, 13.0];
        base = TextStyle(
          fontSize: sizes[level - 1],
          fontWeight: FontWeight.w600,
          height: 1.8,
          color: isDark ? const Color(0xFFF0F2F8) : const Color(0xFF1A1A1A),
        );
      } else {
        final bullet = RegExp(r'^\s*[-*]\s+').firstMatch(line);
        if (bullet != null) {
          line = '•  ${line.substring(bullet.end)}';
        }
      }
      // 行内 **加粗**：按 ** 切，落在奇数段的是加粗内容
      final parts = line.split('**');
      for (var j = 0; j < parts.length; j++) {
        if (parts[j].isEmpty) continue;
        spans.add(
          TextSpan(
            text: parts[j],
            style: j.isOdd ? base.copyWith(fontWeight: FontWeight.w600) : base,
          ),
        );
      }
      if (i < lines.length - 1) spans.add(const TextSpan(text: '\n'));
    }
    return spans;
  }

  // 图片段（![](url)）——圆角图片，加载失败给友好占位
  Widget _buildImage(String url) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: Image.network(
        url,
        fit: BoxFit.cover,
        width: double.infinity,
        errorBuilder: (c, e, s) => Container(
          height: 120,
          alignment: Alignment.center,
          color: isDark ? Colors.white10 : const Color(0xFFF0F0F0),
          child: Text(
            '图片加载失败',
            style: TextStyle(
              fontSize: 12,
              color: isDark ? Colors.white38 : Colors.grey,
            ),
          ),
        ),
      ),
    ),
  );

  TextStyle _bodyStyle() => TextStyle(
    fontSize: 15,
    height: 1.8,
    color: isDark ? const Color(0xFFE0E2F0) : const Color(0xFF1A1A1A),
  );

  // 公式渲染失败时不弹"公式渲染失败"红提示，直接把原始 LaTeX 源码用等宽
  // 字体露出来——用户至少能看到内容，也方便反馈是哪条公式挂了（Bug 3）
  Widget _latexError(String src) => Text(
    src,
    style: TextStyle(
      fontSize: 13,
      fontFamily: 'monospace',
      color: isDark ? const Color(0xFFB8BAD0) : const Color(0xFF555555),
    ),
  );

  Widget _buildLatexBlock(String latex) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      // 去掉紫色 pill 底色——公式不再从正文里跳出来当色块，只留一圈中性
      // 细描边把展示式框住，跟正文融为一体
      decoration: BoxDecoration(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isDark ? const Color(0xFF33333F) : const Color(0xFFE8E8ED),
          width: 0.5,
        ),
      ),
      // 宽公式横向滚动，不撑破
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Math.tex(
          preprocessLatex(latex.trim()),
          mathStyle: MathStyle.display,
          // 字色跟正文一致，不再用品牌紫
          textStyle: TextStyle(
            fontSize: 16,
            color: isDark ? const Color(0xFFE0E2F0) : const Color(0xFF1A1A1A),
          ),
          onErrorFallback: (_) => _latexError(latex.trim()),
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
        // 小梦 AI 回答里的代码是用户自己的对话内容，不是"他人笔记"，不拦截
        isSelfPreview: true,
        allowOpenInNotebook: codeToNotebook,
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
    // h4-h6：不设的话 flutter_markdown 用默认样式（偏小、没加粗），#### 小节
    // 标题会显得比正文还弱。补上跟行内 lite 路径一致的字号/字重
    h4: TextStyle(
      fontSize: 14,
      fontWeight: FontWeight.w600,
      color: isDark ? const Color(0xFFF0F2F8) : const Color(0xFF1A1A1A),
    ),
    h5: TextStyle(
      fontSize: 13.5,
      fontWeight: FontWeight.w600,
      color: isDark ? const Color(0xFFF0F2F8) : const Color(0xFF1A1A1A),
    ),
    h6: TextStyle(
      fontSize: 13,
      fontWeight: FontWeight.w600,
      color: isDark ? const Color(0xFFF0F2F8) : const Color(0xFF1A1A1A),
    ),
    strong: const TextStyle(fontWeight: FontWeight.w600),
    listBullet: TextStyle(
      fontSize: 15,
      color: isDark ? const Color(0xFFE0E2F0) : const Color(0xFF1A1A1A),
    ),
    blockquoteDecoration: BoxDecoration(
      border: const Border(
        left: BorderSide(color: Color(0xFF6366F1), width: 3),
      ),
      color: isDark ? const Color(0xFF1A1A35) : const Color(0xFFEEF0FF),
    ),
    // 不设置的话 flutter_markdown 的 --- 分割线默认渲染成一整条实心灰
    // 色块，很显眼、像一条"带子"横在正文中间——改成克制的 0.5px 细线
    horizontalRuleDecoration: BoxDecoration(
      border: Border(
        top: BorderSide(
          color: isDark ? const Color(0xFF3A3A5C) : const Color(0xFFE0E0E0),
          width: 0.5,
        ),
      ),
    ),
  );
}
