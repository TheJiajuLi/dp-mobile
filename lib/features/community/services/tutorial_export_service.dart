import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart' show Share;

import '../../../shared/utils/latex_utils.dart'
    show splitInlineLatex, latexInnerBody, kLatexInlineRenderSize;

// 真实的 block 结构是 tutorial_block_renderer.dart 里那套扁平结构
// {type, content, level?, language?, imageUrl?, fileName?, fileSize?,
// linkTitle?, linkUrl?, variant?, source?}——不是嵌套的 {type, data:{}}，
// type 也是 heading/code/latex/image/file/audio/video/link/quote/
// callout 这几种真实值（不是 header/math/formula/paragraph 这些猜的）。
// 这里的渲染分支照抄阅读视角那份的 switch，保证导出效果跟正式阅读页
// 看到的一致，不会各画各的
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

// text/heading/callout 块里的行内公式 → 用离屏渲染好的 PNG 内联进文字流
// （pw.WidgetSpan），文字段走 pw.TextSpan。没有对应 PNG（渲染失败/漏了）就
// 退回去掉定界符的纯文字，至少不露 $ 源码。整段无公式时直接返回 pw.Text（快
// 路径，避免 RichText 开销）。key 用 splitInlineLatex 出来的含定界符原文，跟
// 收集端 latex_image_renderer 完全一致
pw.Widget _inlineLatexRichText({
  required String content,
  required pw.TextStyle style,
  required Map<String, Uint8List> latexImages,
}) {
  final segs = splitInlineLatex(content);
  if (!segs.any((s) => s.isFormula)) {
    return pw.Text(content, style: style);
  }
  final fontSize = style.fontSize ?? 11;
  final spans = <pw.InlineSpan>[];
  for (final seg in segs) {
    if (!seg.isFormula) {
      if (seg.raw.isNotEmpty) {
        spans.add(pw.TextSpan(text: seg.raw, style: style));
      }
      continue;
    }
    final bytes = latexImages[seg.raw];
    if (bytes == null) {
      spans.add(pw.TextSpan(text: latexInnerBody(seg.raw), style: style));
      continue;
    }
    final img = pw.MemoryImage(bytes);
    final iw = (img.width ?? 1).toDouble();
    final ih = (img.height ?? 1).toDouble();
    // PNG 按 pixelRatio 3 截、行内公式按 kLatexInlineRenderSize 渲染。
    // 按「字号比例」等比缩放（不再把总高钉死成 字号×1.35）——后者对竖向延展
    // 小的公式（无上下标，如 F·dr）缩放系数更大、字形被放大，跟带上下标的
    // 公式大小对不上。按比例缩后每个公式字形都跟周围文字一个量级、彼此统一。
    // 超正文宽（515pt）再等比夹
    final ihLogical = ih / 3.0;
    final iwLogical = iw / 3.0;
    final scale = fontSize / kLatexInlineRenderSize;
    var w = iwLogical * scale;
    var h = ihLogical * scale;
    if (w > 515.0) {
      final s = 515.0 / w;
      w *= s;
      h *= s;
    }
    spans.add(
      pw.WidgetSpan(
        child: pw.Image(img, width: w, height: h),
      ),
    );
  }
  return pw.RichText(text: pw.TextSpan(children: spans));
}

// NotoSansSC 和数学符号 fallback 字体都不覆盖 emoji（🌟 这类），渲染时
// 一样缺字形——不像上标符号那样能找专门字体兜底，emoji 字形本身就没打算
// 让这两个字体覆盖，直接在渲染前过滤掉。只用在 PDF 导出，Markdown 导出
// 不受字体限制，不应用这个过滤，emoji 原样保留
String _stripEmoji(String text) {
  return text.replaceAll(
    RegExp(
      r'[\u{1F300}-\u{1F9FF}\u{2600}-\u{26FF}\u{2700}-\u{27BF}]',
      unicode: true,
    ),
    '',
  );
}

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

// 一块代码框（左细线+浅色底）。pdf 的 Container 不是 SpanningWidget，装不下
// 当前页剩余空间时 MultiPage 会整块挪到下一页（keep-together）；但如果单块
// 高度超过一整页，pdf 会直接抛 PdfException。所以调用方把长代码按行切成多
// 块，每块都保证不超过一页——既不跨页截断、每页也都带完整样式、还不会崩
pw.Widget _codeBox({
  required String code,
  required String language,
  required bool isDark,
  required PdfColor accentColor,
  required pw.Font font,
  required pw.Font boldFont,
  required pw.EdgeInsets margin,
  double padTop = 8,
  double padBottom = 8,
}) {
  return pw.Container(
    margin: margin,
    padding: pw.EdgeInsets.fromLTRB(10, padTop, 10, padBottom),
    width: double.infinity,
    decoration: pw.BoxDecoration(
      color: isDark ? PdfColor.fromHex('1A1A2E') : PdfColor.fromHex('F8F8F8'),
      border: pw.Border(left: pw.BorderSide(color: accentColor, width: 3)),
    ),
    child: pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        if (language.isNotEmpty) ...[
          pw.Text(
            language.toUpperCase(),
            style: pw.TextStyle(
              font: boldFont,
              fontSize: 8,
              color: accentColor,
            ),
          ),
          pw.SizedBox(height: 4),
        ],
        pw.Text(
          code,
          style: pw.TextStyle(
            font: font,
            fontSize: 9,
            color: isDark
                ? PdfColor.fromHex('E0E0FF')
                : PdfColor.fromHex('1A1A1A'),
            lineSpacing: 3,
          ),
        ),
      ],
    ),
  );
}

Future<Uint8List> buildTutorialPdfBytes({
  required Map<String, dynamic> tutorial,
  required List<dynamic> blocks,
  required String style,
  Map<String, Uint8List> latexImages = const {},
}) async {
  final pdf = pw.Document();
  final isDark = style == 'dark';

  final bgColor = isDark ? PdfColor.fromHex('0A0A1A') : PdfColors.white;
  final textColor = isDark ? PdfColors.white : PdfColor.fromHex('1A1A1A');
  final mutedColor = isDark ? PdfColors.grey400 : PdfColors.grey600;
  // 简洁样式不带紫色，用中性灰；深色样式保留紫色强调色（深色底下紫色
  // 本来就是唯一亮色，不能去掉，不然代码块左边线/语言标签没法跟正文
  // 区分开）
  final accentColor = style == 'clean'
      ? PdfColors.grey700
      : PdfColor.fromHex('6366F1');

  final font = await PdfGoogleFonts.notoSansSCRegular();
  final boldFont = await PdfGoogleFonts.notoSansSCMedium();
  // NotoSansSC 不覆盖上标（⁻⁸ 这类 U+207x）和部分数学符号——缺字形时会
  // 显示成一个方块/替代符号。加一个数学符号字体当 fallback，缺字形时
  // 换这个字体找，不至于整个字符空着或乱码
  final mathFont = await PdfGoogleFonts.notoSansMathRegular();
  final images = await _preloadImages(blocks);

  final title = _stripEmoji(tutorial['title']?.toString() ?? '');
  final author = tutorial['username']?.toString() ?? '';
  final dateStr = _formatDate(tutorial['created_at']);

  pdf.addPage(
    pw.MultiPage(
      pageTheme: pw.PageTheme(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(40),
        theme: pw.ThemeData.withFont(
          base: font,
          bold: boldFont,
          fontFallback: [mathFont],
        ),
        buildBackground: (context) => pw.FullPage(
          ignoreMargins: true,
          child: pw.Container(color: bgColor),
        ),
      ),
      build: (context) {
        final widgets = <pw.Widget>[];

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
          final content = _stripEmoji(block['content'] as String? ?? '');

          switch (type) {
            case 'heading':
              final level = block['level'] as int? ?? 2;
              widgets.add(
                pw.Padding(
                  padding: const pw.EdgeInsets.only(top: 12, bottom: 6),
                  child: _inlineLatexRichText(
                    content: content,
                    style: pw.TextStyle(
                      font: boldFont,
                      fontSize: level == 2 ? 16 : (level == 3 ? 14 : 12.5),
                      color: textColor,
                    ),
                    latexImages: latexImages,
                  ),
                ),
              );
              break;

            case 'code':
              {
                // content 是空的话之前会画出一个只有语言标签、没有代码的空
                // 深色框——看着像渲染坏了，其实是这个 block 本身就没有代码
                // 内容，直接跳过不画，不留一个看着莫名其妙的空框
                if (content.trim().isEmpty) break;
                final language = block['language'] as String? ?? '';
                // pdf 的 Container 不跨页：整块代码框装不下当前页剩余空间时，
                // MultiPage 会把整块挪到下一页，页底留一大段空白。之前每块 40
                // 行（≈半页）还是太粗，照样跳页。这里切成每块 ≤5 行（一小条），
                // MultiPage 就能在小条之间精准断页——先填满当前页剩余空间、再
                // 续到下一页，几乎不留空白。续块之间用 1.5pt 上下内边距衔接
                // （正好补齐块内 lineSpacing，两侧各 1.5≈一个行距），左细线+
                // 浅底连续，视觉上仍是一整块、不像被切开
                final lines = content.split('\n');
                const chunkSize = 5;
                for (var start = 0; start < lines.length; start += chunkSize) {
                  final end = math.min(start + chunkSize, lines.length);
                  final isFirst = start == 0;
                  final isLast = end >= lines.length;
                  widgets.add(
                    _codeBox(
                      code: lines.sublist(start, end).join('\n'),
                      // 只有第一块显示语言标签，后续续块不重复标签
                      language: isFirst ? language : '',
                      isDark: isDark,
                      accentColor: accentColor,
                      font: font,
                      boldFont: boldFont,
                      // 首/尾块保留 8pt 内边距，中间续块用 1.5pt 无缝衔接
                      padTop: isFirst ? 8 : 1.5,
                      padBottom: isLast ? 8 : 1.5,
                      margin: pw.EdgeInsets.only(
                        top: isFirst ? 8 : 0,
                        bottom: isLast ? 8 : 0,
                      ),
                    ),
                  );
                }
                break;
              }

            case 'latex':
              {
                // 优先用离屏渲染好的真实公式图片（renderTutorialLatexImages
                // 里用 flutter_math_fork 排版成 PNG）——pdf 包没有 TeX 引擎，
                // 这是唯一能得到真公式的路子。渲染失败/没有图时退回纯文本斜体
                final rawLatex = block['content'] as String? ?? '';
                final formulaBytes = latexImages[rawLatex];
                if (formulaBytes != null) {
                  final img = pw.MemoryImage(formulaBytes);
                  final iw = img.width;
                  final ih = img.height;
                  if (iw != null && ih != null && iw > 0 && ih > 0) {
                    // 图片像素 = 逻辑尺寸 × pixelRatio(3)，再按 96→72dpi 换成
                    // PDF point；太宽就等比缩到正文宽度内（A4 减页边距 ≈515pt）
                    var w = iw / 3.0 * 0.75;
                    var h = ih / 3.0 * 0.75;
                    const maxW = 515.0;
                    if (w > maxW) {
                      final s = maxW / w;
                      w *= s;
                      h *= s;
                    }
                    widgets.add(
                      pw.Padding(
                        padding: const pw.EdgeInsets.symmetric(vertical: 8),
                        child: pw.Center(
                          child: pw.Image(img, width: w, height: h),
                        ),
                      ),
                    );
                    break;
                  }
                }
                widgets.add(
                  pw.Padding(
                    padding: const pw.EdgeInsets.symmetric(vertical: 8),
                    child: pw.Center(
                      child: pw.Text(
                        _stripLatexDelimiters(content),
                        textAlign: pw.TextAlign.center,
                        style: pw.TextStyle(
                          font: font,
                          fontSize: 12,
                          color: isDark
                              ? PdfColors.white
                              : PdfColor.fromHex('4F46E5'),
                          fontStyle: pw.FontStyle.italic,
                        ),
                      ),
                    ),
                  ),
                );
                break;
              }

            case 'image':
              final imageUrl = block['imageUrl'] as String? ?? '';
              final bytes = images[imageUrl];
              if (bytes != null) {
                // 图片必须显式限高：只给 width 时 pw.Image 会按原图宽高比
                // 撑高，竖长图缩放后高度会超过一页可用高度，而 pw.Image 在
                // MultiPage 里不是 SpanningWidget、单块高于一页就直接抛
                // PdfException（整批导出全挂）。这里按内容区宽度等比缩放，
                // 再把高度 clamp 到单页可用高以内，竖长图也能塞进一页
                const contentW = 515.0;
                const maxPageH = 740.0;
                final img = pw.MemoryImage(bytes);
                final imageW = (img.width ?? 0).toDouble();
                final imageH = (img.height ?? 0).toDouble();
                // 拿不到原图尺寸时兜底用满高，靠 BoxFit.contain 保比例不溢出
                final scaledH = (imageW > 0 && imageH > 0)
                    ? imageH * (contentW / imageW)
                    : maxPageH;
                final finalH = scaledH > maxPageH ? maxPageH : scaledH;
                widgets.add(
                  pw.Container(
                    margin: const pw.EdgeInsets.symmetric(vertical: 8),
                    alignment: pw.Alignment.center,
                    // pw.Image 不像 Flutter 会把 infinity 夹到父约束——宽高都得
                    // 给有限值：宽用正文内容区 515pt（A4 595.28 − 两侧 margin 40），
                    // 高按原图等比缩放并 clamp 到单页可用高内，contain 保比例。
                    // 否则宽图溢出右边、竖长图超页高直接抛 PdfException
                    child: pw.Image(
                      img,
                      width: contentW,
                      height: finalH,
                      fit: pw.BoxFit.contain,
                    ),
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
                    color: isDark
                        ? PdfColor.fromHex('141420')
                        : PdfColors.grey100,
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
                          style: pw.TextStyle(
                            font: font,
                            fontSize: 9,
                            color: mutedColor,
                          ),
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
                    color: isDark
                        ? PdfColor.fromHex('141420')
                        : PdfColors.grey100,
                    border: pw.Border(
                      left: pw.BorderSide(color: calloutColor, width: 3),
                    ),
                  ),
                  child: _inlineLatexRichText(
                    content: content,
                    style: pw.TextStyle(
                      font: font,
                      fontSize: 10.5,
                      color: calloutColor,
                    ),
                    latexImages: latexImages,
                  ),
                ),
              );
              break;

            default: // text
              if (content.isNotEmpty) {
                widgets.add(
                  pw.Padding(
                    padding: const pw.EdgeInsets.only(bottom: 8),
                    // 行内 $...$ 走 PNG 内联渲染，不再是原始源码
                    child: _inlineLatexRichText(
                      content: content,
                      style: pw.TextStyle(
                        font: font,
                        fontSize: 11,
                        color: textColor,
                        lineSpacing: 4,
                      ),
                      latexImages: latexImages,
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
    child: pw.Text(
      label,
      style: pw.TextStyle(font: font, fontSize: 10, color: color),
    ),
  );
}

Future<void> shareTutorialAsMarkdown(
  Map<String, dynamic> tutorial,
  List<dynamic> blocks,
) async {
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
        sb.writeln(
          r'$$'
          '${_stripLatexDelimiters(content)}'
          r'$$',
        );
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
        sb.writeln(
          '[${(linkTitle?.isNotEmpty ?? false) ? linkTitle : linkUrl}]($linkUrl)',
        );
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

  await Share.share(
    sb.toString(),
    subject: tutorial['title']?.toString() ?? '文章',
  );
}
