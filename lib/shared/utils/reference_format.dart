import 'dart:convert';

// 参考文献条目的解析 + GB/T 样式格式化——编辑器（block_card）和阅读端
// （tutorial_block_renderer）共用一份，别两处各写容易跑偏。纯 Dart，无 flutter 依赖。
// 一条参考文献的结构：{author, title, journal, year, url, doi}，全是字符串

// reference block 的 content（JSON 字符串）→ 条目列表。解析失败/空返回 []
List<Map<String, String>> parseReferences(String content) {
  if (content.trim().isEmpty) return [];
  try {
    final decoded = jsonDecode(content);
    if (decoded is List) {
      return decoded
          .whereType<Map>()
          .map(
            (m) => m.map(
              (k, v) => MapEntry(k.toString(), v?.toString() ?? ''),
            ),
          )
          .toList();
    }
  } catch (_) {
    // 脏数据/非 JSON 直接当空列表
  }
  return [];
}

String encodeReferences(List<Map<String, String>> refs) => jsonEncode(refs);

// GB/T 7714 风格：作者. 标题. 期刊/出版社, 年份.（缺哪段省哪段，不留多余标点）
String formatReference(Map<String, String> r) {
  final author = (r['author'] ?? '').trim();
  final title = (r['title'] ?? '').trim();
  final journal = (r['journal'] ?? '').trim();
  final year = (r['year'] ?? '').trim();
  final parts = <String>[];
  if (author.isNotEmpty) parts.add('$author.');
  if (title.isNotEmpty) parts.add('$title.');
  if (journal.isNotEmpty && year.isNotEmpty) {
    parts.add('$journal, $year.');
  } else if (journal.isNotEmpty) {
    parts.add('$journal.');
  } else if (year.isNotEmpty) {
    parts.add('$year.');
  }
  return parts.join(' ');
}

// 空条目模板
Map<String, String> emptyReference() => {
  'author': '',
  'title': '',
  'journal': '',
  'year': '',
  'url': '',
  'doi': '',
};
