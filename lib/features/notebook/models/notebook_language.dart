import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';

// 语言选择器只覆盖"代码"这一类cell（python/r/julia/sql）——latex/markdown/
// html 是完全不同的渲染方式，不是"代码语言的变体"，不接入这个切换器
enum NotebookLanguage { python, r, julia, sql }

extension NotebookLanguageX on NotebookLanguage {
  String get displayName => switch (this) {
    NotebookLanguage.python => 'Python',
    NotebookLanguage.r => 'R',
    NotebookLanguage.julia => 'Julia',
    NotebookLanguage.sql => 'SQL',
  };

  // 跟 _buildCell 里 badgeColor 的取色保持一致，同一语言在列表页/编辑页
  // 看到的应该是同一个颜色
  Color get dotColor => switch (this) {
    NotebookLanguage.python => AppColors.primary,
    NotebookLanguage.r => const Color(0xFF2563EB),
    NotebookLanguage.julia => const Color(0xFF9333EA),
    NotebookLanguage.sql => const Color(0xFF0EA5E9),
  };

  String get snippetLabel => switch (this) {
    NotebookLanguage.python => 'PYTHON 常用片段',
    NotebookLanguage.r => 'R 常用片段',
    NotebookLanguage.julia => 'JULIA 常用片段',
    NotebookLanguage.sql => 'SQL 常用片段',
  };

  // CodeMirror 6 里传给 window.setLanguage() 的 key——跟 _editorHtml
  // 里 langMap 的 key 一一对应
  String get cmKey => switch (this) {
    NotebookLanguage.python => 'python',
    NotebookLanguage.r => 'r',
    NotebookLanguage.julia => 'julia',
    NotebookLanguage.sql => 'sql',
  };

  List<NotebookSnippet> get snippets => switch (this) {
    NotebookLanguage.python => const [
      NotebookSnippet('print()', 'print()'),
      NotebookSnippet('import', 'import numpy as np'),
      NotebookSnippet('def fn():', 'def fn():\n    '),
      NotebookSnippet('for i in', 'for i in range():\n    '),
      NotebookSnippet('if __main__', 'if __name__ == "__main__":\n    '),
      NotebookSnippet('lambda', 'lambda x: x'),
      NotebookSnippet('list comp', '[x for x in items]'),
      NotebookSnippet('dict comp', '{k: v for k, v in d.items()}'),
    ],
    NotebookLanguage.r => const [
      NotebookSnippet('cat()', 'cat()'),
      NotebookSnippet('library()', 'library(tidyverse)'),
      NotebookSnippet('function()', 'fn <- function(x) {\n  \n}'),
      NotebookSnippet('data.frame()', 'data.frame()'),
      NotebookSnippet('ggplot()', 'ggplot(data, aes(x, y))'),
      NotebookSnippet('%>%', ' %>% '),
      NotebookSnippet('lm()', 'lm(y ~ x, data = df)'),
      NotebookSnippet('summary()', 'summary(df)'),
    ],
    NotebookLanguage.julia => const [
      NotebookSnippet('println()', 'println()'),
      NotebookSnippet('using', 'using Statistics'),
      NotebookSnippet('function', 'function fn(x)\n  \nend'),
      NotebookSnippet('@show', '@show x'),
      NotebookSnippet('map()', 'map(x -> x^2, arr)'),
      NotebookSnippet('|>', 'x |> fn'),
      NotebookSnippet('comprehension', '[x^2 for x in 1:10]'),
      NotebookSnippet('@time', '@time fn()'),
    ],
    NotebookLanguage.sql => const [
      NotebookSnippet('SELECT', 'SELECT * FROM '),
      NotebookSnippet('WHERE', 'WHERE '),
      NotebookSnippet('LEFT JOIN', 'LEFT JOIN  ON '),
      NotebookSnippet('GROUP BY', 'GROUP BY '),
      NotebookSnippet('ORDER BY', 'ORDER BY  DESC'),
      NotebookSnippet('LIMIT', 'LIMIT 100'),
      NotebookSnippet('COUNT(*)', 'COUNT(*) AS cnt'),
      NotebookSnippet('HAVING', 'HAVING COUNT(*) > 1'),
    ],
  };
}

// cell.type（字符串，见 notebook_model.dart）到 NotebookLanguage 的映射——
// 只有这4种真正的"代码语言"cell才有对应值，latex/markdown/html 返回 null
NotebookLanguage? notebookLanguageFromCellType(String type) => switch (type) {
  'python' => NotebookLanguage.python,
  'r' => NotebookLanguage.r,
  'julia' => NotebookLanguage.julia,
  'sql' => NotebookLanguage.sql,
  _ => null,
};

class NotebookSnippet {
  final String label;
  final String code;
  const NotebookSnippet(this.label, this.code);
}
