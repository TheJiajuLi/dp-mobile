import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart' show Share;

// 真实的 block 结构是 tutorial_block_renderer.dart 里那套扁平结构
// {type, content, level?, language?, imageUrl?, fileName?, fileSize?,
// linkTitle?, linkUrl?, variant?, source?}——不是嵌套的 {type, data:{}}，
// type 也是 heading/code/latex/image/file/audio/video/link/quote/
// callout 这几种真实值（不是 header/math/formula/paragraph 这些猜的）。
// 这里的渲染分支照抄阅读视角那份的 switch，保证导出效果跟正式阅读页
// 看到的一致，不会各画各的
class TutorialPdfStyle {
  final String key; // clean / dark / brand
  const TutorialPdfStyle(this.key);

  bool get isDark => key == 'dark';
  bool get isBrand => key == 'brand';
}

List<dynamic> parseTutorialBlocks(dynamic raw) {
  if (raw is String) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) return decoded;
    } catch (_) {}
    return [];
  }
  if (raw is List) return raw;
  return [];
}

String _stripLatexDelimiters(String content) =>
    content.replaceAll(r'$$', '').trim();

String _formatDate(dynamic ts) {
  if (ts == null) return '';
  final seconds = ts is num ? ts.toInt() : int.tryParse(ts.toString()) ?? 0;
  final dt = DateTime.fromMillisecondsSinceEpoch(seconds * 1000);
  return '${dt.year}/${dt.month.toString().padLeft(2, '0')}/${dt.day.toString().padLeft(2, '0')}';
}

// 正文里出现的 imageUrl（封面图这里不处理，封面图不在 blocks 里）都是
// 网络图——pw.MultiPage 的 build 回调是同步的，没法在里面 await，所以
// 必须提前把用到的图全部下载好传进去，而不是像最初 demo 那样干脆放
// "[图片]" 占位——图片本来就是文章正文真实存在的内容，不是无法渲染的
// 富媒体（跟音频/视频/文件那种本来就不适合塞进静态 PDF 的类型不一样）
Future<Map<String, Uint8List>> _preloadImages(List<dynamic> blocks) async {
  final urls = blocks
      .whereType<Map>()
      .where((b) => b['type'] == 'image')
      .map((b) => b['imageUrl'] as String? ?? '')
      .where((u) => u.isNotEmpty)
      .toSet();
  final dio = Dio();
  final result = <String, Uint8List>{};
  for (final url in urls) {
    try {
      final res = await dio.get<List<int>>(
        url,
        options: Options(responseType: ResponseType.bytes),
      );
      final data = res.data;
      if (data != null) result[url] = Uint8List.fromList(data);
    } catch (_) {
      // 下载失败就不放进 map，渲染时找不到对应 key 会退化成文字占位
    }
  }
  return result;
}

Future<Uint8List> buildTutorialPdfBytes({
  required Map<String, dynamic> tutorial,
  required List<dynamic> blocks,
  required String style,
}) async {
  final pdf = pw.Document();
  final isDark = style == 'dark';
  final isBrand = style == 'brand';

  final bgColor = isDark ? PdfColor.fromHex('0A0A1A') : PdfColors.white;
  final textColor = isDark ? PdfColors.white : PdfColor.fromHex('1A1A1A');
  final mutedColor = isDark ? PdfColors.grey400 : PdfColors.grey600;
  // 简洁样式不带品牌紫色，用中性灰；深色/极梦都保留紫色强调色（深色底下
  // 紫色本来就是唯一亮色，不能去掉，不然公式框/代码语言标签没法跟正文
  // 区分开）
  final accentColor = style == 'clean'
      ? PdfColors.grey700
      : PdfColor.fromHex('6366F1');

  final font = await PdfGoogleFonts.notoSansSCRegular();
  final boldFont = await PdfGoogleFonts.notoSansSCMedium();
  final images = await _preloadImages(blocks);

  final title = tutorial['title']?.toString() ?? '';
  final author = tutorial['username']?.toString() ?? '';
  final dateStr = _formatDate(tutorial['created_at']);

  pdf.addPage(
    pw.MultiPage(
      pageTheme: pw.PageTheme(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(40),
        theme: pw.ThemeData.withFont(base: font, bold: boldFont),
        buildBackground: (context) =>
            pw.FullPage(ignoreMargins: true, child: pw.Container(color: bgColor)),
      ),
      build: (context) {
        final widgets = <pw.Widget>[];

        // 极梦品牌头部——紫色线 + Logo 文案，只在"极梦"样式下出现；
        // 简洁/深色样式不带这条，避免三种样式看起来都一样
        if (isBrand) {
          widgets.add(
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text(
                  '极梦 DreamingPolar',
                  style: pw.TextStyle(
                    font: boldFont,
                    fontSize: 10,
                    color: accentColor,
                  ),
                ),
                pw.Text(
                  '第 ${context.pageNumber} 页 / 共 ${context.pagesCount} 页',
                  style: pw.TextStyle(font: font, fontSize: 8, color: mutedColor),
                ),
              ],
            ),
          );
          widgets.add(pw.SizedBox(height: 10));
          widgets.add(pw.Divider(color: accentColor, thickness: 1.5));
          widgets.add(pw.SizedBox(height: 14));
        }

        widgets.add(
          pw.Text(
            title,
            style: pw.TextStyle(font: boldFont, fontSize: 20, color: textColor),
          ),
        );
        widgets.add(pw.SizedBox(height: 8));
        widgets.add(
          pw.Text(
            [
              if (author.isNotEmpty) author,
              if (dateStr.isNotEmpty) dateStr,
              '极梦知识平台',
            ].join(' · '),
            style: pw.TextStyle(font: font, fontSize: 10, color: mutedColor),
          ),
        );
        widgets.add(pw.SizedBox(height: 8));
        widgets.add(pw.Divider(color: mutedColor, thickness: 0.5));
        widgets.add(pw.SizedBox(height: 10));

        for (final raw in blocks) {
          if (raw is! Map) continue;
          final block = Map<String, dynamic>.from(raw);
          final type = block['type'] as String? ?? 'text';
          final content = block['content'] as String? ?? '';

          switch (type) {
            case 'heading':
              final level = block['level'] as int? ?? 2;
              widgets.add(
                pw.Padding(
                  padding: const pw.EdgeInsets.only(top: 12, bottom: 6),
                  child: pw.Text(
                    content,
                    style: pw.TextStyle(
                      font: boldFont,
                      fontSize: level == 2 ? 16 : (level == 3 ? 14 : 12.5),
                      color: textColor,
                    ),
                  ),
                ),
              );
              break;

            case 'code':
              final language = block['language'] as String? ?? '';
              widgets.add(
                pw.Container(
                  margin: const pw.EdgeInsets.symmetric(vertical: 6),
                  padding: const pw.EdgeInsets.all(10),
                  width: double.infinity,
                  decoration: pw.BoxDecoration(
                    color: PdfColor.fromHex('1E1E2E'),
                    borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
                  ),
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      if (language.isNotEmpty) ...[
                        pw.Text(
                          language,
                          style: pw.TextStyle(
                            font: font,
                            fontSize: 8,
                            color: PdfColor.fromHex('9B9EF8'),
                          ),
                        ),
                        pw.SizedBox(height: 4),
                      ],
                      pw.Text(
                        content,
                        style: pw.TextStyle(
                          font: font,
                          fontSize: 9,
                          color: PdfColor.fromHex('E0E0FF'),
                          lineSpacing: 3,
                        ),
                      ),
                    ],
                  ),
                ),
              );
              break;

            case 'latex':
              widgets.add(
                pw.Container(
                  margin: const pw.EdgeInsets.symmetric(vertical: 6),
                  padding: const pw.EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  width: double.infinity,
                  // pdf 包的 BoxDecoration 不允许非均匀 border（只设左边框）
                  // 同时给 borderRadius——两个一起会在渲染时断言失败
                  // "A borderRadius can only be given for a uniform Border"，
                  // 保留左边框设计，去掉圆角
                  decoration: pw.BoxDecoration(
                    color: isDark
                        ? PdfColor.fromHex('1A1829')
                        : PdfColor.fromHex('F5F5FF'),
                    border: pw.Border(
                      left: pw.BorderSide(color: accentColor, width: 3),
                    ),
                  ),
                  child: pw.Text(
                    _stripLatexDelimiters(content),
                    textAlign: pw.TextAlign.center,
                    style: pw.TextStyle(font: font, fontSize: 11, color: accentColor),
                  ),
                ),
              );
              break;

            case 'image':
              final imageUrl = block['imageUrl'] as String? ?? '';
              final bytes = images[imageUrl];
              if (bytes != null) {
                widgets.add(
                  pw.Container(
                    margin: const pw.EdgeInsets.symmetric(vertical: 8),
                    child: pw.Image(pw.MemoryImage(bytes)),
                  ),
                );
              } else {
                widgets.add(_placeholderBox(font, mutedColor, '[图片加载失败]'));
              }
              break;

            case 'file':
              final fileName = block['fileName'] as String? ?? content;
              widgets.add(_placeholderBox(font, mutedColor, '[文件] $fileName'));
              break;

            case 'audio':
              final fileName = block['fileName'] as String? ?? content;
              widgets.add(_placeholderBox(font, mutedColor, '[音频] $fileName'));
              break;

            case 'video':
              final fileName = block['fileName'] as String? ?? content;
              widgets.add(_placeholderBox(font, mutedColor, '[视频] $fileName'));
              break;

            case 'link':
              final linkTitle = block['linkTitle'] as String?;
              final linkUrl = block['linkUrl'] as String? ?? content;
              widgets.add(
                pw.Padding(
                  padding: const pw.EdgeInsets.symmetric(vertical: 4),
                  child: pw.Text(
                    (linkTitle?.isNotEmpty ?? false)
                        ? '$linkTitle ($linkUrl)'
                        : linkUrl,
                    style: pw.TextStyle(
                      font: font,
                      fontSize: 10.5,
                      color: accentColor,
                      decoration: pw.TextDecoration.underline,
                    ),
                  ),
                ),
              );
              break;

            case 'quote':
              final source = block['source'] as String?;
              widgets.add(
                pw.Container(
                  margin: const pw.EdgeInsets.symmetric(vertical: 6),
                  padding: const pw.EdgeInsets.all(10),
                  width: double.infinity,
                  decoration: pw.BoxDecoration(
                    color: isDark ? PdfColor.fromHex('141420') : PdfColors.grey100,
                    border: pw.Border(
                      left: pw.BorderSide(color: mutedColor, width: 3),
                    ),
                  ),
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(
                        content,
                        style: pw.TextStyle(
                          font: font,
                          fontSize: 10.5,
                          fontStyle: pw.FontStyle.italic,
                          color: textColor,
                        ),
                      ),
                      if (source != null && source.isNotEmpty) ...[
                        pw.SizedBox(height: 4),
                        pw.Text(
                          '— $source',
                          style: pw.TextStyle(font: font, fontSize: 9, color: mutedColor),
                        ),
                      ],
                    ],
                  ),
                ),
              );
              break;

            case 'callout':
              final variant = block['variant'] as String? ?? 'info';
              final calloutColor = {
                'tip': PdfColor.fromHex('16A34A'),
                'warning': PdfColor.fromHex('D97706'),
                'info': accentColor,
              }[variant]!;
              widgets.add(
                pw.Container(
                  margin: const pw.EdgeInsets.symmetric(vertical: 6),
                  padding: const pw.EdgeInsets.all(10),
                  width: double.infinity,
                  decoration: pw.BoxDecoration(
                    color: isDark ? PdfColor.fromHex('141420') : PdfColors.grey100,
                    border: pw.Border(
                      left: pw.BorderSide(color: calloutColor, width: 3),
                    ),
                  ),
                  child: pw.Text(
                    content,
                    style: pw.TextStyle(font: font, fontSize: 10.5, color: calloutColor),
                  ),
                ),
              );
              break;

            default: // text
              if (content.isNotEmpty) {
                widgets.add(
                  pw.Padding(
                    padding: const pw.EdgeInsets.only(bottom: 8),
                    child: pw.Text(
                      content,
                      style: pw.TextStyle(
                        font: font,
                        fontSize: 11,
                        color: textColor,
                        lineSpacing: 4,
                      ),
                    ),
                  ),
                );
              }
              break;
          }
        }

        return widgets;
      },
      footer: (context) => pw.Padding(
        padding: const pw.EdgeInsets.only(top: 8),
        child: pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text(
              'dreamingpolar.com',
              style: pw.TextStyle(font: font, fontSize: 8, color: mutedColor),
            ),
            pw.Text(
              '© ${DateTime.now().year} 极梦 · 保留所有权利',
              style: pw.TextStyle(font: font, fontSize: 8, color: mutedColor),
            ),
          ],
        ),
      ),
    ),
  );

  return pdf.save();
}

pw.Widget _placeholderBox(pw.Font font, PdfColor color, String label) {
  return pw.Container(
    margin: const pw.EdgeInsets.symmetric(vertical: 6),
    padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 10),
    width: double.infinity,
    decoration: const pw.BoxDecoration(
      color: PdfColors.grey200,
      borderRadius: pw.BorderRadius.all(pw.Radius.circular(4)),
    ),
    child: pw.Text(label, style: pw.TextStyle(font: font, fontSize: 10, color: color)),
  );
}

Future<void> shareTutorialAsMarkdown(Map<String, dynamic> tutorial, List<dynamic> blocks) async {
  final sb = StringBuffer();
  sb.writeln('# ${tutorial['title'] ?? ''}');
  sb.writeln();
  sb.writeln('> 作者：${tutorial['username'] ?? ''} · 来源：极梦 DreamingPolar');
  sb.writeln();

  for (final raw in blocks) {
    if (raw is! Map) continue;
    final block = Map<String, dynamic>.from(raw);
    final type = block['type'] as String? ?? 'text';
    final content = block['content'] as String? ?? '';

    switch (type) {
      case 'heading':
        final level = block['level'] as int? ?? 2;
        sb.writeln('${'#' * level} $content');
        sb.writeln();
        break;
      case 'code':
        final language = block['language'] as String? ?? '';
        sb.writeln('```$language');
        sb.writeln(content);
        sb.writeln('```');
        sb.writeln();
        break;
      case 'latex':
        sb.writeln(r'$$' '${_stripLatexDelimiters(content)}' r'$$');
        sb.writeln();
        break;
      case 'image':
        final imageUrl = block['imageUrl'] as String? ?? '';
        if (imageUrl.isNotEmpty) {
          sb.writeln('![image]($imageUrl)');
          sb.writeln();
        }
        break;
      case 'file':
      case 'audio':
      case 'video':
        final fileName = block['fileName'] as String? ?? content;
        sb.writeln('[$fileName]($content)');
        sb.writeln();
        break;
      case 'link':
        final linkTitle = block['linkTitle'] as String?;
        final linkUrl = block['linkUrl'] as String? ?? content;
        sb.writeln('[${(linkTitle?.isNotEmpty ?? false) ? linkTitle : linkUrl}]($linkUrl)');
        sb.writeln();
        break;
      case 'quote':
        final source = block['source'] as String?;
        sb.writeln('> $content');
        if (source != null && source.isNotEmpty) sb.writeln('> — $source');
        sb.writeln();
        break;
      case 'callout':
        sb.writeln('> $content');
        sb.writeln();
        break;
      default:
        if (content.isNotEmpty) {
          sb.writeln(content);
          sb.writeln();
        }
        break;
    }
  }

  await Share.share(sb.toString(), subject: tutorial['title']?.toString() ?? '文章');
}
