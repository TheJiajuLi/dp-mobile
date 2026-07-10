enum BlockType { text, heading2, heading3, quote, formula, code, image, divider }

class AnswerBlock {
  final String id;
  BlockType type;
  String content;
  String? language; // code block 用

  AnswerBlock({
    required this.id,
    required this.type,
    this.content = '',
    this.language = 'Python',
  });

  // 转成纯文本发给后端——目前 question_answers.content 就是 TEXT 列，
  // 没有单独的富文本/blocks 存储结构，跟 tutorials.blocks 那套 JSON
  // 富文本不是一回事，这里选 Markdown 语法是最省事、后续真要渲染
  // 也有现成的 flutter_markdown 可以直接吃
  String toMarkdown() {
    switch (type) {
      case BlockType.text:
        return content;
      case BlockType.heading2:
        return '## $content';
      case BlockType.heading3:
        return '### $content';
      case BlockType.quote:
        return '> $content';
      case BlockType.formula:
        return '\$\$$content\$\$';
      case BlockType.code:
        return '```${language ?? ''}\n$content\n```';
      case BlockType.image:
        return '![]($content)';
      case BlockType.divider:
        return '---';
    }
  }
}

String blocksToContent(List<AnswerBlock> blocks) {
  return blocks.map((b) => b.toMarkdown()).where((s) => s.isNotEmpty).join('\n\n');
}
