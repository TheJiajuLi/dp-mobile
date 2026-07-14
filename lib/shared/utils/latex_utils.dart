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
  // 已经显式写了环境（aligned/gathered/matrix/cases/array/align…）的不动，
  // 避免嵌套 aligned 反而破坏结构
  if (trimmed.contains(r'\begin{')) return latex;
  // `\\`（两个连续反斜杠）= 换行符；单反斜杠的命令（\text/\vec…）不会命中
  if (trimmed.contains(r'\\')) {
    return '\\begin{aligned}\n$trimmed\n\\end{aligned}';
  }
  return latex;
}
