import 'package:flutter/material.dart';

// 代码块语言选择器的候选项——发布页代码块的语言选择器（工具栏里那个
// 语言选择条）和高亮语言兜底共用同一份。导入的代码块 language 可能是
// 'text'/'jsx'/'ts'/'bash' 等各种值，不在这个列表里时按 python 兜底
// （见 block_card.dart 的 _buildCodeBlock）。code block 特意不放 latex——
// LaTeX 是独立的 block 类型，两条路径都能表示公式只会互相打架
const kCodeLanguages = [
  'python',
  'javascript',
  'typescript',
  'jsx',
  'tsx',
  'sql',
  'html',
  'css',
  'json',
  'yaml',
  'bash',
  'shell',
  'markdown',
  'dart',
  'java',
  'kotlin',
  'swift',
  'rust',
  'go',
  'r',
  'cpp',
  'c',
  'plaintext',
];

// 语言显示成首字母大写（python → Python），value 仍用小写原值
String capLang(String l) =>
    l.isEmpty ? l : l[0].toUpperCase() + l.substring(1);

// 极简、启发式的语法高亮——不是真正的语言 tokenizer/解析器，只是按正则
// 把注释/字符串/数字/关键字找出来上色，发布页代码块编辑态和阅读态
// （tutorial_block_renderer.dart）共用同一份，配色跟观感才不会两边各画
// 各的、慢慢跑偏
const codeCommentColor = Color(0xFF6A9955);
const codeStringColor = Color(0xFFCE9178);
const codeNumberColor = Color(0xFFB5CEA8);
const codeKeywordColor = Color(0xFFC586C0);

const _pythonKeywords = {
  'import',
  'from',
  'as',
  'def',
  'class',
  'return',
  'if',
  'elif',
  'else',
  'for',
  'while',
  'in',
  'not',
  'and',
  'or',
  'try',
  'except',
  'finally',
  'with',
  'lambda',
  'pass',
  'break',
  'continue',
  'none',
  'true',
  'false',
  'yield',
  'global',
  'nonlocal',
  'assert',
  'del',
  'raise',
  'is',
};

const _jsKeywords = {
  'import',
  'from',
  'as',
  'export',
  'default',
  'function',
  'return',
  'if',
  'else',
  'for',
  'while',
  'in',
  'of',
  'try',
  'catch',
  'finally',
  'const',
  'let',
  'var',
  'class',
  'extends',
  'new',
  'this',
  'typeof',
  'instanceof',
  'null',
  'undefined',
  'true',
  'false',
  'async',
  'await',
  'yield',
  'break',
  'continue',
  'throw',
  'switch',
  'case',
};

const _sqlKeywords = {
  'select',
  'from',
  'where',
  'group',
  'by',
  'order',
  'join',
  'left',
  'right',
  'inner',
  'outer',
  'on',
  'as',
  'insert',
  'into',
  'values',
  'update',
  'set',
  'delete',
  'create',
  'table',
  'and',
  'or',
  'not',
  'null',
  'limit',
  'distinct',
  'having',
  'union',
  'all',
};

Set<String> _keywordsFor(String language) => switch (language) {
  'python' => _pythonKeywords,
  'javascript' => _jsKeywords,
  'sql' => _sqlKeywords,
  _ => const <String>{},
};

final _tokenPattern = RegExp(
  r'(#.*$|//.*$|--.*$)'
  r'''|('(?:[^'\\]|\\.)*'|"(?:[^"\\]|\\.)*")'''
  r'|\b\d+\.?\d*\b'
  r'|\b[A-Za-z_][A-Za-z0-9_]*\b',
  multiLine: true,
);

List<TextSpan> highlightCode(String code, String language, TextStyle base) {
  final keywords = _keywordsFor(language);
  final spans = <TextSpan>[];
  var lastEnd = 0;

  for (final m in _tokenPattern.allMatches(code)) {
    if (m.start > lastEnd) {
      spans.add(TextSpan(text: code.substring(lastEnd, m.start), style: base));
    }
    final text = m.group(0)!;
    Color? color;
    if (text.startsWith('#') ||
        text.startsWith('//') ||
        text.startsWith('--')) {
      color = codeCommentColor;
    } else if (text.startsWith("'") || text.startsWith('"')) {
      color = codeStringColor;
    } else if (RegExp(r'^\d').hasMatch(text)) {
      color = codeNumberColor;
    } else if (keywords.contains(text.toLowerCase())) {
      color = codeKeywordColor;
    }
    spans.add(
      TextSpan(
        text: text,
        style: color != null ? base.copyWith(color: color) : base,
      ),
    );
    lastEnd = m.end;
  }
  if (lastEnd < code.length) {
    spans.add(TextSpan(text: code.substring(lastEnd), style: base));
  }
  return spans;
}

// 让 TextFormField 编辑代码时也能实时显示高亮色——默认的 TextEditingController
// 只会用统一一种颜色画整段文字，覆盖 buildTextSpan 换成按 token 上色的版本，
// 光标/选区行为完全不受影响，只是绘制层面换了一下
class HighlightingCodeController extends TextEditingController {
  String language;

  HighlightingCodeController({super.text, required this.language});

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    return TextSpan(
      children: highlightCode(text, language, style ?? const TextStyle()),
    );
  }
}
