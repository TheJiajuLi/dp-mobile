// LaTeX 渲染前的预处理。
//
// flutter_math_fork（KaTeX 端口）跟标准 LaTeX 一样：`\\` 换行只能出现在
// align/aligned/gathered/matrix/cases 这类环境里，裸写在普通公式里会直接
// 解析失败，整段 fall back 成红色原文。用户经常不知道这条规则、直接写
// 多行公式（`a \\ b`），所以这里在渲染前做个兜底：内容含 `\\` 又没有任何
// `\begin{...}` 环境时，自动包一层 `aligned`，让换行生效。
// 行内公式离屏渲染的字号——latex_image_renderer 按这个尺寸渲染 PNG，PDF
// 导出（tutorial_export_service._inlineLatexRichText）按它做字号比例缩放。
// 两端必须一致，抽成共享常量，别再各自硬编码 15 跑偏
const double kLatexInlineRenderSize = 15.0;

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

// 反引号代码内联 `...`——里面的 $ / $$ 是字面示例（LaTeX 语法教程会写
// `$...$` 来讲"美元符号怎么用"），不能当公式，否则会被误渲成黑块
final _codeSpanPattern = RegExp(r'`[^`\n]*`');

List<InlineLatexSeg> splitInlineLatex(String content) {
  final segs = <InlineLatexSeg>[];
  var last = 0;
  // 先把代码内联切出来当"字面文字段"，其余部分再找公式
  for (final cm in _codeSpanPattern.allMatches(content)) {
    if (cm.start > last) {
      _splitFormulas(segs, content.substring(last, cm.start));
    }
    segs.add(InlineLatexSeg(false, cm.group(0)!));
    last = cm.end;
  }
  if (last < content.length) {
    _splitFormulas(segs, content.substring(last));
  }
  return segs;
}

void _splitFormulas(List<InlineLatexSeg> segs, String text) {
  var last = 0;
  for (final m in _inlineLatexPattern.allMatches(text)) {
    if (m.start > last) {
      segs.add(InlineLatexSeg(false, text.substring(last, m.start)));
    }
    segs.add(InlineLatexSeg(true, m.group(0)!));
    last = m.end;
  }
  if (last < text.length) {
    segs.add(InlineLatexSeg(false, text.substring(last)));
  }
}

// 公式体能不能真的用 Math.tex 排出来：空、或"裸数学里含 CJK"（把中文当公式，
// Math.tex 排不出、会渲成黑豆腐块）都算不可渲染。\text{中文}/\mathrm{...} 里的
// CJK 能正常渲染，所以先剥掉它们的内容再判
bool isRenderableLatexBody(String body) {
  final b = body.trim();
  if (b.isEmpty) return false;
  final stripped = b.replaceAll(
    RegExp(r'\\(text|mathrm|mbox|textbf|textit|textrm)\s*\{[^}]*\}'),
    '',
  );
  if (RegExp(r'[㐀-䶿一-鿿豈-﫿]').hasMatch(stripped)) {
    return false;
  }
  return true;
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
