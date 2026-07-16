// LaTeX 渲染前的预处理。
//
// flutter_math_fork（KaTeX 端口）跟标准 LaTeX 一样：`\\` 换行只能出现在
// align/aligned/gathered/matrix/cases 这类环境里，裸写在普通公式里会直接
// 解析失败，整段 fall back 成红色原文。用户经常不知道这条规则、直接写
// 多行公式（`a \\ b`），所以这里在渲染前做个兜底：内容含 `\\` 又没有任何
// `\begin{...}` 环境时，自动包一层 `aligned`，让换行生效。
String preprocessLatex(String latex) {
  final trimmed = latex.trim();
  if (trimmed.isEmpty) return latex;
  // 剥掉结尾孤立的反斜杠：小梦常把行内公式闭合的 $ 误写成 \$，行内正则
  // `\$([^$\n]+)\$` 会把多出来的 \ 卷进公式体末尾（…v}\），KaTeX 遇到落单
  // 的 \ 直接解析失败、整段退化成红色源码。合法 LaTeX 里结尾单个 \ 永远是
  // 错误（\\ 换行必须成对），剥掉安全；结尾恰好是 \\（换行）时靠负向后顾
  // 不误伤
  final cleaned = trimmed.replaceFirst(RegExp(r'(?<!\\)\\$'), '').trim();
  if (cleaned.isEmpty) return latex;
  // 已经显式写了环境（aligned/gathered/matrix/cases/array/align…）的不动，
  // 避免嵌套 aligned 反而破坏结构
  if (cleaned.contains(r'\begin{')) return cleaned;
  // `\\`（两个连续反斜杠）= 换行符；单反斜杠的命令（\text/\vec…）不会命中
  if (cleaned.contains(r'\\')) {
    return '\\begin{aligned}\n$cleaned\n\\end{aligned}';
  }
  return cleaned;
}

// 行内公式切分：把一段文字按 $...$ / \(...\) / \[...\] 定界符切成有序段，
// 每段要么是纯文字、要么是一条公式。跟 inlineLatexText 用同一套定界符正则。
// 公式段的 raw 保留定界符原文——PDF 导出两端（收集端渲染 PNG、渲染端查图）
// 都拿它当 key，保证一致。纯 Dart、不依赖 flutter/pdf，两个世界都能 import
class InlineLatexSeg {
  final bool isFormula;
  final String raw; // 公式段：含定界符原文；文字段：原文
  const InlineLatexSeg(this.isFormula, this.raw);
}

final _inlineLatexPattern = RegExp(
  r'\$([^$\n]+)\$' // $...$
  r'|\\\((.+?)\\\)' // \(...\)
  r'|\\\[(.+?)\\\]', // \[...\]
  dotAll: true,
);

List<InlineLatexSeg> splitInlineLatex(String content) {
  final segs = <InlineLatexSeg>[];
  var last = 0;
  for (final m in _inlineLatexPattern.allMatches(content)) {
    if (m.start > last) {
      segs.add(InlineLatexSeg(false, content.substring(last, m.start)));
    }
    segs.add(InlineLatexSeg(true, m.group(0)!));
    last = m.end;
  }
  if (last < content.length) {
    segs.add(InlineLatexSeg(false, content.substring(last)));
  }
  return segs;
}

// 去掉公式外层定界符，得到送进 TeX 引擎的公式体
String latexInnerBody(String c) => c
    .replaceAll(r'$$', '')
    .replaceAll(r'$', '')
    .replaceAll(r'\[', '')
    .replaceAll(r'\]', '')
    .replaceAll(r'\(', '')
    .replaceAll(r'\)', '')
    .trim();
