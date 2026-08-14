import 'dart:convert';
import '../../core/theme/app_colors.dart';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../utils/latex_utils.dart';
import '../utils/reference_format.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../features/auth/auth_service.dart';
import '../../features/notebook/models/notebook_model.dart';
import '../../features/notebook/services/notebook_service.dart';
import '../../l10n/generated/app_localizations.dart';
import '../services/pyodide_engine.dart';
import '../utils/block_text_style.dart';
import '../utils/code_highlight.dart';
import '../utils/pro_access.dart';
import 'ai_content_renderer.dart';
import 'app_toast.dart';

const _primary = AppColors.primary;

// 教程详情页（阅读视角）和发布页的实时预览抽屉共用同一套渲染逻辑——
// 之前只有 tutorial_detail_screen.dart 自己一份私有实现，只认
// text/heading/code/latex/image/callout 六种类型。发布页新增的
// file/audio/video/link 这几种 block 后端能存能读（实测确认过，
// blocks 字段本身不校验类型），但阅读视角一直没有对应的渲染分支，
// 发布出去的内容里这几种 block 在读者那边等于是空的——抽出来共用一份，
// 加齐这几个分支，预览和实际发布效果才不会各画各的、慢慢跑偏
Widget buildTutorialBlockWidget(
  BuildContext context,
  AppLocalizations l10n,
  Map<String, dynamic> block, {
  // 阅读页专用排版：正文放大到 16/1.85、callout 带灯泡图标。只有文章阅读页
  // 传 true，发布预览抽屉不受影响（默认 false）
  bool readingMode = false,
  // 代码块运行门禁：自己的内容（作者预览草稿/看自己已发布文章）传 true 不
  // 拦截；读者阅读他人文章传 false（默认），非 Pro 运行时弹会员 Sheet
  bool isSelfPreview = false,
  // latex 块的公式编号（文档内第 n 个参与编号的公式）——调用处按位置算好传进
  // 来；null=不编号（autoNumber 关 或 非 latex）
  int? equationNumber,
}) {
  final type = block['type'] as String? ?? 'text';
  final content = block['content'] as String? ?? '';

  switch (type) {
    case 'heading':
      final level = block['level'] as int? ?? 2;
      // 阅读页把标题层级拉开（数字杂志感）：H1 28 / H2 22 / H3 19，负字距 +
      // 收紧行高；编辑器/预览保持原来紧凑的 20/17/15
      final headingStyle = applyBlockTextFormat(
        readingMode
            ? TextStyle(
                fontSize: level == 1
                    ? 28
                    : level == 2
                    ? 22
                    : 19,
                fontWeight: level == 3 ? FontWeight.w600 : FontWeight.w700,
                height: level == 1
                    ? 1.3
                    : level == 2
                    ? 1.35
                    : 1.4,
                letterSpacing: level == 1
                    ? -0.3
                    : level == 2
                    ? -0.2
                    : -0.1,
                color: Theme.of(context).textTheme.bodyLarge?.color,
              )
            : TextStyle(
                fontSize: level == 2
                    ? 20
                    : level == 3
                    ? 17
                    : 15,
                fontWeight: FontWeight.w700,
                color: Theme.of(context).textTheme.bodyLarge?.color,
              ),
        isBold: block['bold'] == true,
        isItalic: block['italic'] == true,
        isUnderline: block['underline'] == true,
        isStrike: block['strike'] == true,
        textColorValue: (block['textColor'] as num?)?.toInt(),
        highlightColorValue: (block['highlightColor'] as num?)?.toInt(),
        fontFamily: block['fontFamily'] as String?,
        fontSizeStep: (block['fontSizeStep'] as num?)?.toInt() ?? 1,
        lineHeightStep: (block['lineHeightStep'] as num?)?.toInt() ?? 1,
      );
      return Padding(
        padding: readingMode
            ? const EdgeInsets.fromLTRB(20, 20, 20, 8)
            : const EdgeInsets.fromLTRB(16, 16, 16, 8),
        child: inlineLatexText(content, headingStyle),
      );

    case 'code':
      // 数据集块（Notebook 导入数据发布而来）不展示那一大段 base64 代码，
      // 折叠成一张小卡片——阅读页进页时已静默注入内核（见
      // tutorial_detail_screen._preloadDatasets）
      if (block['isDataset'] == true) {
        return _buildDatasetCard(context, content);
      }
      final codeWidget = TutorialCodeBlock(
        content: content,
        language: block['language'] as String? ?? 'python',
        isSelfPreview: isSelfPreview,
      );
      // 阅读页给代码块上下 20 留白，跟正文拉开呼吸感
      return readingMode
          ? Padding(
              padding: const EdgeInsets.symmetric(vertical: 20),
              child: codeWidget,
            )
          : codeWidget;

    case 'latex':
      // Math.tex 不会自动换行/收缩——公式比屏幕宽（长积分式/多项连乘）会顶穿
      // 右边界溢出。套一层横向滚动，宽公式改成左右滑动。传统论文样式：公式
      // 居中、右侧 (n) 编号垂直居中；不编号时保持左对齐
      final formula = Center(
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Math.tex(
            preprocessLatex(content.replaceAll(r'$$', '').trim()),
            textStyle: const TextStyle(fontSize: 16),
            onErrorFallback: (err) => Text(
              content,
              style: const TextStyle(color: Colors.red, fontSize: 12),
            ),
          ),
        ),
      );
      return Padding(
        padding: EdgeInsets.symmetric(
          horizontal: readingMode ? 20 : 16,
          vertical: 8,
        ),
        child: equationNumber == null
            // 未编号的独立公式也居中（传统论文样式），只是不带 (n)
            ? formula
            : Row(
                children: [
                  Expanded(child: formula),
                  const SizedBox(width: 8),
                  Text(
                    '($equationNumber)',
                    style: TextStyle(
                      fontSize: 14,
                      color: Theme.of(
                        context,
                      ).textTheme.bodyMedium?.color?.withValues(alpha: 0.7),
                    ),
                  ),
                ],
              ),
      );

    case 'image':
      final imageUrl = block['imageUrl'] as String? ?? '';
      if (imageUrl.isEmpty) return const SizedBox.shrink();
      return Padding(
        // 阅读页图片上下留白 36（全出血、无水平 padding），杂志式呼吸感
        padding: EdgeInsets.symmetric(vertical: readingMode ? 36 : 8),
        child: CachedNetworkImage(
          imageUrl: imageUrl,
          fit: BoxFit.cover,
          errorWidget: (context, url, error) => const SizedBox.shrink(),
        ),
      );

    case 'file':
      final fileName = block['fileName'] as String? ?? content;
      final fileSize = (block['fileSize'] as num?)?.toInt();
      return _tappableCard(
        context,
        url: content,
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        color: const Color(0xFFEFF6FF),
        borderColor: const Color(0xFFBFDBFE),
        leadingIcon: Icons.insert_drive_file,
        leadingColor: const Color(0xFF2563EB),
        title: fileName,
        titleColor: const Color(0xFF1D4ED8),
        subtitle: fileSize != null ? _formatBytes(fileSize) : null,
        subtitleColor: const Color(0xFF60A5FA),
        trailingIcon: Icons.download_outlined,
        trailingColor: const Color(0xFF2563EB),
      );

    case 'audio':
      final fileName = block['fileName'] as String? ?? content;
      return _tappableCard(
        context,
        url: content,
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        color: const Color(0xFFFDF4FF),
        borderColor: const Color(0xFFE9D5FF),
        leadingIcon: Icons.play_arrow,
        leadingIconIsCircle: true,
        leadingColor: const Color(0xFFA855F7),
        title: fileName,
        titleColor: const Color(0xFF6B21A8),
        subtitle: l10n.tapToPlayExternalLabel,
        subtitleColor: const Color(0xFFA855F7),
      );

    case 'video':
      final fileName = block['fileName'] as String? ?? content;
      return GestureDetector(
        onTap: content.isEmpty ? null : () => _openExternally(content),
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          height: 160,
          decoration: BoxDecoration(
            color: const Color(0xFF1C1C1E),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Stack(
            alignment: Alignment.center,
            children: [
              const Icon(
                Icons.play_circle_outline,
                color: Colors.white,
                size: 48,
              ),
              Positioned(
                bottom: 10,
                left: 12,
                right: 12,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      fileName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12,
                        color: Colors.white70,
                      ),
                    ),
                    Text(
                      l10n.tapToPlayExternalLabel,
                      style: const TextStyle(
                        fontSize: 10.5,
                        color: Colors.white54,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );

    case 'link':
      final linkTitle = block['linkTitle'] as String?;
      final linkUrl = block['linkUrl'] as String? ?? content;
      return _tappableCard(
        context,
        url: linkUrl,
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        borderColor: const Color(0xFFE5E5EA),
        leadingIcon: Icons.link,
        leadingColor: _primary,
        leadingBg: AppColors.primaryLight,
        title: (linkTitle?.isNotEmpty ?? false) ? linkTitle! : linkUrl,
        titleColor: Theme.of(context).textTheme.bodyLarge?.color,
        subtitle: (linkTitle?.isNotEmpty ?? false) ? linkUrl : null,
        subtitleColor: Colors.grey,
      );

    case 'quote':
      // 目前发布页的 BlockType 枚举里还没有独立的 quote 类型（引用靠
      // callout 顶），这个分支是给将来可能出现的 quote block 提前接好的
      // 兼容渲染——现在的发布流程不会产出这个 type，但读取到了也不会
      // 被吃掉当纯文本处理
      final source = block['source'] as String?;
      return Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFFFAFAF8),
          borderRadius: BorderRadius.circular(8),
          border: const Border(left: BorderSide(color: _primary, width: 3)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              content,
              style: const TextStyle(
                fontSize: 14,
                fontStyle: FontStyle.italic,
                color: Color(0xFF555555),
                height: 1.6,
              ),
            ),
            if (source != null && source.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                '— $source',
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ],
          ],
        ),
      );

    case 'callout':
      final variant = block['variant'] as String? ?? 'info';
      final isDark = Theme.of(context).brightness == Brightness.dark;
      // 背景色深色下改成对应色相的极深底，不再是浅色块贴在暗色页上
      final bgColors = isDark
          ? const {
              'tip': Color(0xFF0F1F18),
              'warning': Color(0xFF1F1A0F),
              'info': Color(0xFF1A1829),
            }
          : const {
              'tip': Color(0xFFE8F8F0),
              'warning': Color(0xFFFFF7E6),
              'info': AppColors.primaryLight,
            };
      // 文字 + 左侧竖条共用这套强调色，深色下用调淡的色，浅色下保持原样
      final accentColors = isDark
          ? const {
              'tip': Color(0xFF5BC48A),
              'warning': Color(0xFFD4A842),
              'info': Color(0xFF9B9EF8),
            }
          : const {
              'tip': AppColors.success,
              'warning': Color(0xFFD97706),
              'info': _primary,
            };
      final bg = bgColors[variant] ?? bgColors['info']!;
      final accent = accentColors[variant] ?? accentColors['info']!;
      return Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(10),
          border: Border(left: BorderSide(color: accent, width: 3)),
        ),
        child: readingMode
            ? Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.lightbulb_outline, size: 16, color: accent),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      content,
                      style: TextStyle(
                        fontSize: 13,
                        color: accent,
                        height: 1.6,
                      ),
                    ),
                  ),
                ],
              )
            : Text(
                content,
                style: TextStyle(fontSize: 14, color: accent, height: 1.5),
              ),
      );

    case 'markdown':
      // 原始 Markdown 块——用 flutter_markdown 渲染加粗/列表/小节标题等，
      // 跟发布页编辑器 _buildMarkdownBlock 是同一份渲染，两端观感一致
      return Padding(
        padding: EdgeInsets.symmetric(
          horizontal: 16,
          vertical: readingMode ? 8 : 6,
        ),
        child: MarkdownBody(
          data: content,
          selectable: false,
          styleSheet: MarkdownStyleSheet.fromTheme(Theme.of(context)).copyWith(
            p: TextStyle(
              fontSize: readingMode ? 16 : 15,
              height: readingMode ? 1.85 : 1.7,
              color: readingMode
                  ? (Theme.of(context).brightness == Brightness.dark
                        ? const Color(0xFFC8CAD8)
                        : const Color(0xFF2A2A2A))
                  : Theme.of(context).textTheme.bodyLarge?.color,
            ),
          ),
        ),
      );

    case 'reference':
      return _buildReferenceList(context, content, readingMode);

    default: // text
      final textStyle = applyBlockTextFormat(
        TextStyle(
          // 数字杂志阅读体验：18px、行高 1.72、轻微负字距，正文用比纯白/纯黑
          // 更柔和的颜色（深色 #E6E6E6 / 浅色 #1A1A1A）
          fontSize: readingMode ? 18 : 15,
          height: readingMode ? 1.72 : 1.7,
          letterSpacing: readingMode ? -0.1 : null,
          color: readingMode
              ? (Theme.of(context).brightness == Brightness.dark
                    ? const Color(0xFFE6E6E6)
                    : const Color(0xFF1A1A1A))
              : Theme.of(context).textTheme.bodyLarge?.color,
        ),
        isBold: block['bold'] == true,
        isItalic: block['italic'] == true,
        isUnderline: block['underline'] == true,
        isStrike: block['strike'] == true,
        textColorValue: (block['textColor'] as num?)?.toInt(),
        highlightColorValue: (block['highlightColor'] as num?)?.toInt(),
        fontFamily: block['fontFamily'] as String?,
        fontSizeStep: (block['fontSizeStep'] as num?)?.toInt() ?? 1,
        lineHeightStep: (block['lineHeightStep'] as num?)?.toInt() ?? 1,
      );
      // 含 markdown 的正文段（帮我写常见：一段里既有 $公式$ 又有 **粗体**/
      // 列表）走 AiContentRenderer 组合渲染；否则走 inlineLatexText 保留块级
      // 格式/阅读排版。跟编辑器 text 块预览用同一判断，保证所见即所得
      final isDark = Theme.of(context).brightness == Brightness.dark;
      return Padding(
        // 阅读页水平 20、段落底部 16；编辑器保持 h16/v6
        padding: readingMode
            ? const EdgeInsets.fromLTRB(20, 0, 20, 16)
            : const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        child: hasMarkdownSyntax(content)
            ? AiContentRenderer(content: content, isDark: isDark)
            : inlineLatexText(content, textStyle),
      );
  }
}

// 段落是否含 Markdown 语法（**加粗**/## 标题/- 列表/> 引用/[链接]/*斜体*）。
// text 块（编辑器预览 + 阅读端）据此决定：含 markdown 走 AiContentRenderer
// （markdown + 行内公式组合渲染，解决"一段里公式 + 粗体只能二选一"的问题）；
// 不含 markdown 走 inlineLatexText（纯公式/纯文字，保留块级格式/阅读排版）。
// 逻辑跟 xmeng_write_sheet._hasMarkdown 对齐
bool hasMarkdownSyntax(String text) {
  if (text.contains('**') ||
      text.contains('__') ||
      text.contains('##') ||
      text.contains('> ')) {
    return true;
  }
  for (final line in text.split('\n')) {
    final l = line.trimLeft();
    if (RegExp(r'^([-*+])\s').hasMatch(l)) return true; // 无序列表
    if (RegExp(r'^\d+\.\s').hasMatch(l)) return true; // 有序列表
    if (RegExp(r'^#{1,6}\s').hasMatch(l)) return true; // 小节标题
  }
  if (RegExp(r'\[[^\]]+\]\([^)]+\)').hasMatch(text)) return true; // 链接
  if (RegExp(r'(?<!\*)\*[^*\s][^*\n]*\*(?!\*)').hasMatch(text)) {
    return true; // *斜体*
  }
  return false;
}

// text/heading block 支持行内 $...$ LaTeX——纯文字用 Text 走原来的路径，
// 含公式的才切到 Text.rich + WidgetSpan（跟 AiContentRenderer 里行内
// 公式一个思路，text/heading 两处共用，不用各写一份）。baseStyle 已经
// 套了 applyBlockTextFormat（加粗/颜色/高亮等），公式片段字号跟着缩小
// 一档，视觉上不会比正文字还抢眼
Widget inlineLatexText(
  String content,
  TextStyle baseStyle, {
  int? maxLines,
  TextOverflow? overflow,
}) {
  // 支持三种行内定界符：$...$、\(...\)、\[...\]。$...$ 里不跨行（避免把
  // 两段正文之间的 $ 误配成一大段公式），\(...\)/\[...\] 用非贪婪可跨行
  final pattern = RegExp(
    r'\$([^$\n]+)\$' // $...$
    r'|\\\((.+?)\\\)' // \(...\)
    r'|\\\[(.+?)\\\]', // \[...\]
    dotAll: true,
  );
  final matches = pattern.allMatches(content).toList();
  if (matches.isEmpty) {
    return Text(
      content,
      style: baseStyle,
      maxLines: maxLines,
      overflow: overflow,
    );
  }

  final mathFontSize = (baseStyle.fontSize ?? 15) * 0.9;
  final spans = <InlineSpan>[];
  var last = 0;
  for (final m in matches) {
    if (m.start > last) {
      spans.add(TextSpan(text: content.substring(last, m.start)));
    }
    final latex = m.group(1) ?? m.group(2) ?? m.group(3) ?? '';
    spans.add(
      WidgetSpan(
        alignment: PlaceholderAlignment.middle,
        child: Math.tex(
          preprocessLatex(latex),
          textStyle: TextStyle(fontSize: mathFontSize, color: baseStyle.color),
          onErrorFallback: (_) => Text(
            latex,
            style: TextStyle(
              fontSize: mathFontSize * 0.9,
              fontFamily: 'monospace',
              color: baseStyle.color,
            ),
          ),
        ),
      ),
    );
    last = m.end;
  }
  if (last < content.length) {
    spans.add(TextSpan(text: content.substring(last)));
  }
  return Text.rich(
    TextSpan(style: baseStyle, children: spans),
    maxLines: maxLines,
    overflow: overflow,
  );
}

// 从数据集块代码里抽出文件名 + 行数用于卡片展示。数据集 cell 的代码头固定
// 是「# <文件名> · 自动注入 · <N> 行」（xlsx/json 无行数），从注释抽最稳；
// 抽不到再退回 pd.* 赋值的变量名
(String name, String? rows) _extractDatasetInfo(String content) {
  final head = RegExp(r'^#\s*(.+?)\s*·\s*自动注入').firstMatch(content);
  final name = head?.group(1)?.trim();
  final rowM = RegExp(r'·\s*(\d+)\s*行').firstMatch(content);
  final rows = rowM != null ? '${rowM.group(1)} 行' : null;
  if (name != null && name.isNotEmpty) return (name, rows);
  final varM = RegExp(
    r'^(\w+)\s*=\s*pd\.',
    multiLine: true,
  ).firstMatch(content);
  return (varM?.group(1) ?? '数据集', rows);
}

// 数据集块折叠卡片——琥珀色（跟 Notebook 里数据集 cell 的橙色主题一致），
// 右侧绿色「自动注入」标：说明这块数据在阅读时会自动加载进内核。用"自动
// 注入"而非"已注入内核"是因为这个 renderer 也被发布页预览抽屉复用，那里
// 并不会真的注入，描述机制比断言运行态更诚实
Widget _buildDatasetCard(BuildContext context, String content) {
  final isDark = Theme.of(context).brightness == Brightness.dark;
  final (name, rows) = _extractDatasetInfo(content);
  const amber = Color(0xFFD97706);
  const green = AppColors.success;
  return Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: isDark ? amber.withValues(alpha: 0.10) : const Color(0xFFFEF3C7),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: amber.withValues(alpha: isDark ? 0.5 : 1),
          width: 0.5,
        ),
      ),
      child: Row(
        children: [
          const Icon(Icons.dataset_outlined, size: 16, color: amber),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('数据集', style: TextStyle(fontSize: 10, color: amber)),
                const SizedBox(height: 1),
                Text(
                  rows == null ? name : '$name · $rows',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: isDark
                        ? const Color(0xFFFCD9A6)
                        : const Color(0xFF92400E),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
            decoration: BoxDecoration(
              color: isDark
                  ? green.withValues(alpha: 0.16)
                  : const Color(0xFFF0FFF5),
              borderRadius: BorderRadius.circular(99),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.check_circle_outline, size: 9, color: green),
                SizedBox(width: 3),
                Text(
                  '自动注入',
                  style: TextStyle(
                    fontSize: 9,
                    color: green,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

// 教程详情页（阅读视角）里可运行的代码块——只有 python/javascript/sql
// 才显示"运行"按钮，跟发布页/Notebook 共用同一个 App 级单例
// PyodideEngine（compiler.js + 全局唯一的隐藏 WebView，挂在 main.dart）。
// 2026-07-15 前这里每个代码块自己 new 一份 PyodideEngine——一篇文章有
// 3 个可运行代码块，就是 3 个各自独立的隐藏 WebView 各自重新拉一遍
// compiler.js/Pyodide，既浪费又慢。改成全局单例后不用再在这里自己
// 挂一份 buildHiddenWebView()
class TutorialCodeBlock extends ConsumerStatefulWidget {
  final String content;
  final String language;
  // 作者本人的场景（发布页预览自己的草稿、看自己已发布的文章、小梦 AI 回答
  // 里的代码）不拦截；只有"读者阅读他人文章"时运行代码才是 Pro 权益。
  // true=自己的内容，不校验；false（默认）=读者态，非 Pro 弹会员 Sheet
  final bool isSelfPreview;
  // true 时头部多一个「在 Notebook 运行」按钮——把这段代码按检测到的语言
  // 建成一个新 Notebook 打开（极索 CoT 回答用，其它场景默认不显示）
  final bool allowOpenInNotebook;

  const TutorialCodeBlock({
    super.key,
    required this.content,
    required this.language,
    this.isSelfPreview = false,
    this.allowOpenInNotebook = false,
  });

  @override
  ConsumerState<TutorialCodeBlock> createState() => _TutorialCodeBlockState();
}

class _TutorialCodeBlockState extends ConsumerState<TutorialCodeBlock> {
  // 可内联运行的语言——python/js/sql 走 Pyodide，r 走 webR（引擎都已在同一个
  // 隐藏 WebView 里预热）。julia 等暂无内核，只能「在 Notebook 运行」
  static const _runnableLanguages = ['python', 'javascript', 'sql', 'r'];

  late final String _blockId;
  bool _running = false;
  String? _outputContent;
  String? _outputType;

  // 阅读页代码块可编辑（方案②：点「编辑」才进编辑态，默认只读、不误触键盘）。
  // controller 持有"可能被读者改过"的代码——只读态也读它（改完点完成后仍生效），
  // 运行/复制都跑这份。编辑不落库，纯读者本地 playground
  bool _editing = false;
  late final HighlightingCodeController _codeCtrl;
  final FocusNode _codeFocus = FocusNode();

  bool get _canRun =>
      _runnableLanguages.contains(widget.language.toLowerCase());

  bool get _isModified => _codeCtrl.text != widget.content;

  @override
  void initState() {
    super.initState();
    _blockId = UniqueKey().toString();
    _codeCtrl = HighlightingCodeController(
      text: widget.content,
      language: widget.language.toLowerCase(),
    );
  }

  @override
  void dispose() {
    _codeCtrl.dispose();
    _codeFocus.dispose();
    super.dispose();
  }

  // 编辑/完成切换——编辑不需要 Pro（运行才需要）
  void _toggleEdit() {
    setState(() => _editing = !_editing);
    if (_editing) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _codeFocus.requestFocus();
      });
    } else {
      _codeFocus.unfocus();
    }
  }

  // 重置回原始代码（轻量操作，直接重置不二次确认）
  void _reset() {
    setState(() => _codeCtrl.text = widget.content);
    showAppToast(context, '已重置为原始代码');
  }

  void _copyCode() {
    Clipboard.setData(ClipboardData(text: _codeCtrl.text));
    showAppToast(context, '已复制代码', ok: true);
  }

  Future<void> _run() async {
    // 读者阅读他人文章时运行代码是 Pro 权益——非 Pro 弹会员 Sheet 引导升级；
    // 作者预览自己的内容（isSelfPreview）不拦截
    if (!widget.isSelfPreview && !requirePro(context, ref, feature: '运行代码')) {
      return;
    }
    final l10n = AppLocalizations.of(context)!;
    setState(() => _running = true);
    final lang = widget.language.toLowerCase();
    final engine = ref.read(pyodideEngineProvider);
    List<Map<String, dynamic>> outputs;
    try {
      // R 走 webR（runR），其余 python/js/sql 走 Pyodide（run）——跑当前
      // controller 的内容，读者改过就跑改过的版本
      outputs = lang == 'r'
          ? await engine.runR(_blockId, _codeCtrl.text, l10n)
          : await engine.run(_blockId, _codeCtrl.text, lang, l10n);
    } finally {
      if (mounted) setState(() => _running = false);
    }
    if (!mounted) return;

    String? foundContent;
    String? foundType;
    for (final out in outputs) {
      final type = out['type'] as String? ?? 'text';
      final oc = out['content'] as String? ?? '';
      if (['viz-suggestion', 'missing-package', 'debug'].contains(type)) {
        continue;
      }
      if (type == 'text' && oc.trim().isEmpty) continue;
      foundContent = oc;
      foundType = type;
      break;
    }
    setState(() {
      _outputContent = foundContent ?? l10n.runCompleteNoOutputMessage;
      _outputType = foundType ?? 'text';
    });
  }

  Widget _renderOutput(String content, String? type) {
    switch (type) {
      case 'image':
        try {
          final raw = content.contains(',') ? content.split(',').last : content;
          // matplotlib 生成的图自带一圈很细的黑色描边（savefig 默认的
          // figure 边框），这一层出自远程加载的 compiler.js（不在这个
          // 仓库里，改不了生成逻辑）——用轻微放大+裁切把这圈边框裁掉，
          // 属于视觉层面的规避，不是从根上解决
          return ClipRect(
            child: Transform.scale(
              scale: 1.03,
              child: Image.memory(base64Decode(raw)),
            ),
          );
        } catch (_) {
          return Text(
            content,
            style: const TextStyle(color: Colors.white70, fontSize: 12),
          );
        }
      case 'html':
        return InAppWebView(
          initialData: InAppWebViewInitialData(
            data:
                '''
<html><head><style>
body{background:#0A0F1A;color:#E2E8F0;font-family:monospace;font-size:12px;margin:8px;}
table{border-collapse:collapse;width:100%;}
td,th{border:1px solid #334155;padding:4px 8px;}
</style></head><body>$content</body></html>
''',
          ),
        );
      case 'error':
        return Text(
          content,
          style: const TextStyle(
            color: Color(0xFFFCA5A5),
            fontFamily: 'monospace',
            fontSize: 12,
            height: 1.5,
          ),
        );
      case 'info':
        return Text(
          content,
          style: const TextStyle(
            color: Color(0xFF94A3B8),
            fontFamily: 'monospace',
            fontSize: 12,
            height: 1.5,
          ),
        );
      default:
        return Text(
          content,
          style: const TextStyle(
            color: Color(0xFF4ADE80),
            fontFamily: 'monospace',
            fontSize: 12,
            height: 1.5,
          ),
        );
    }
  }

  // 头部小图标钮（复制/重置/编辑/完成）——描边方钮；active（完成态）用紫色底+紫描边
  Widget _headerIconBtn({
    required IconData icon,
    required VoidCallback onTap,
    required Color border,
    required Color iconColor,
    bool active = false,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: active ? _primary.withValues(alpha: 0.10) : null,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: active ? _primary.withValues(alpha: 0.35) : border,
            width: active ? 0.8 : 0.5,
          ),
        ),
        child: Icon(icon, size: 15, color: active ? _primary : iconColor),
      ),
    );
  }

  // 语言标签（头部彩色 pill 显示用）——跟 Notebook 语言 pill 同一套命名
  String get _langLabel => switch (widget.language.toLowerCase()) {
    'python' => 'Python',
    'sql' => 'SQL',
    'javascript' || 'js' => 'JavaScript',
    'r' => 'R',
    'julia' => 'Julia',
    'html' => 'HTML',
    'bash' || 'shell' || 'sh' => 'Shell',
    'json' => 'JSON',
    final l => l.isEmpty ? 'Code' : l.toUpperCase(),
  };

  // 语言主色——跟 Notebook cell 徽标一致：Python 紫 / SQL 蓝 / R 橙 / JS 琥珀
  Color get _langColor => switch (widget.language.toLowerCase()) {
    'sql' => const Color(0xFF0EA5E9),
    'r' => const Color(0xFFD97706),
    'javascript' || 'js' => const Color(0xFFD97706),
    'julia' => const Color(0xFF9333EA),
    _ => AppColors.primary,
  };

  // 「在 Notebook 运行」——把这段代码按检测到的语言建成一个新 Notebook 打开。
  // cell 类型带上正确语言（不再写死 python），julia/r/sql 都保留原类型
  Future<void> _openInNotebook() async {
    final lang = widget.language.toLowerCase();
    const known = {
      'python',
      'sql',
      'javascript',
      'r',
      'julia',
      'latex',
      'markdown',
      'html',
    };
    final cellType = known.contains(lang) ? lang : 'python';
    final user = ref.read(currentUserProvider);
    final svc = NotebookService(user?.id ?? 'guest');
    final ms = DateTime.now().millisecondsSinceEpoch;
    final now = ms ~/ 1000;
    final id = 'nb_$ms';
    final nb = Notebook(
      id: id,
      name: '极索代码 · $_langLabel',
      lang: cellType,
      cells: [
        NotebookCell(id: 'cell_$ms', type: cellType, code: _codeCtrl.text),
      ],
      createdAt: now,
      updatedAt: now,
    );
    await svc.save(nb);
    if (!mounted) return;
    context.push('/notebook/$id');
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    // 去掉原来那块深色 pill（macOS三色点+语言标签+满底#1C1C1E），跟公式块
    // 一样统一成"中性圆框"：透明底+一圈中性描边，融进文章背景。头部只留
    // 运行键（浅紫底+描边，跟发布页编辑态代码块同一套样式）+ 复制键，
    // 减少同屏视觉噪音
    final border = Theme.of(context).dividerColor;
    final iconColor = isDark ? Colors.white38 : const Color(0xFF9AA0AB);
    final codeTextColor = isDark
        ? const Color(0xFFE0E2F0)
        : const Color(0xFF1E293B);
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: border, width: 0.8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
            child: Row(
              children: [
                // 语言彩色 pill——检测到的语言（Python/R/SQL/JS/Julia…）用对应
                // 图标色直接表意，跟 Notebook cell 徽标同一套配色
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: _langColor.withValues(alpha: isDark ? 0.20 : 0.10),
                    borderRadius: BorderRadius.circular(7),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.code_rounded, size: 12, color: _langColor),
                      const SizedBox(width: 4),
                      Text(
                        _langLabel,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: _langColor,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                // 「已修改」标识——读者改过原始代码时显示（改完点完成后仍在）
                if (_isModified)
                  const Padding(
                    padding: EdgeInsets.only(left: 2),
                    child: Text(
                      '已修改',
                      style: TextStyle(
                        fontSize: 10.5,
                        color: _primary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                const Spacer(),
                // 只读态：复制；编辑态：重置
                _headerIconBtn(
                  icon: _editing ? Icons.restart_alt : Icons.copy_outlined,
                  onTap: _editing ? _reset : _copyCode,
                  border: border,
                  iconColor: iconColor,
                ),
                const SizedBox(width: 6),
                // 编辑 ↔ 完成
                _headerIconBtn(
                  icon: _editing ? Icons.check_rounded : Icons.edit_outlined,
                  onTap: _toggleEdit,
                  active: _editing,
                  border: border,
                  iconColor: iconColor,
                ),
                if (_canRun) ...[
                  const SizedBox(width: 6),
                  GestureDetector(
                    onTap: _running ? null : _run,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: _primary.withValues(alpha: isDark ? 0.16 : 0.08),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: _primary.withValues(alpha: 0.22),
                          width: 0.5,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (_running)
                            const SizedBox(
                              width: 12,
                              height: 12,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: _primary,
                              ),
                            )
                          else
                            const Icon(
                              Icons.play_arrow_outlined,
                              size: 15,
                              color: _primary,
                            ),
                          const SizedBox(width: 4),
                          Text(
                            _running ? l10n.runningLabel : l10n.runAction,
                            style: const TextStyle(
                              fontSize: 11,
                              color: _primary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: _editing
                // 编辑态：受控 TextField，HighlightingCodeController 自带实时
                // 语法高亮；关掉智能标点/纠错，避免直引号被替换破坏代码
                ? TextField(
                    controller: _codeCtrl,
                    focusNode: _codeFocus,
                    maxLines: null,
                    keyboardType: TextInputType.multiline,
                    autocorrect: false,
                    enableSuggestions: false,
                    smartDashesType: SmartDashesType.disabled,
                    smartQuotesType: SmartQuotesType.disabled,
                    // 刷新头部「已修改」标识
                    onChanged: (_) => setState(() {}),
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 13,
                      color: codeTextColor,
                      height: 1.6,
                    ),
                    decoration: const InputDecoration(
                      filled: false,
                      isDense: true,
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.zero,
                    ),
                  )
                // 只读态：语法高亮的横向可滚文本（读 controller，改完点完成仍生效）
                : SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Text.rich(
                      TextSpan(
                        children: highlightCode(
                          _codeCtrl.text,
                          widget.language.toLowerCase(),
                          TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 13,
                            color: codeTextColor,
                            height: 1.6,
                          ),
                        ),
                      ),
                    ),
                  ),
          ),
          // 「在 Notebook 运行」——极索 CoT 回答里的代码可一键建成 Notebook 打开
          // （cell 类型带正确语言）。julia 等没有内联内核的语言，这是唯一运行途径
          if (widget.allowOpenInNotebook)
            InkWell(
              onTap: _openInNotebook,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 9),
                decoration: BoxDecoration(
                  border: Border(top: BorderSide(color: border, width: 0.8)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.auto_stories_outlined,
                      size: 14,
                      color: _langColor,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '在 Notebook 运行',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: _langColor,
                      ),
                    ),
                    const SizedBox(width: 3),
                    Icon(Icons.chevron_right, size: 15, color: _langColor),
                  ],
                ),
              ),
            ),
          if (_outputContent != null)
            Container(
              width: double.infinity,
              constraints: const BoxConstraints(maxHeight: 300),
              decoration: const BoxDecoration(
                color: Color(0xFF0A0F1A),
                borderRadius: BorderRadius.only(
                  bottomLeft: Radius.circular(12),
                  bottomRight: Radius.circular(12),
                ),
              ),
              child: _outputType == 'html'
                  ? SizedBox(
                      height: 200,
                      child: _renderOutput(_outputContent!, _outputType),
                    )
                  : Padding(
                      padding: const EdgeInsets.all(10),
                      child: SingleChildScrollView(
                        child: _renderOutput(_outputContent!, _outputType),
                      ),
                    ),
            ),
        ],
      ),
    );
  }
}

Future<void> _openExternally(String url) async {
  final uri = Uri.tryParse(url);
  if (uri == null) return;
  if (await canLaunchUrl(uri)) {
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}

// 参考文献列表（阅读端）：文末「参考文献」小标题 + GB/T 样式编号列表，
// doi/url 显示为紫色可点链接
Widget _buildReferenceList(
  BuildContext context,
  String content,
  bool readingMode,
) {
  final refs = parseReferences(content);
  if (refs.isEmpty) return const SizedBox.shrink();
  final isDark = Theme.of(context).brightness == Brightness.dark;
  final ink = isDark ? const Color(0xFFE6E6E6) : const Color(0xFF1A1A1A);
  final muted = isDark ? Colors.white54 : const Color(0xFF666666);
  final hPad = readingMode ? 20.0 : 16.0;
  return Padding(
    padding: EdgeInsets.fromLTRB(hPad, 20, hPad, 12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '参考文献',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: ink,
          ),
        ),
        const SizedBox(height: 4),
        Container(width: 28, height: 2, color: _primary.withValues(alpha: 0.5)),
        const SizedBox(height: 12),
        for (var i = 0; i < refs.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _referenceItem(i + 1, refs[i], ink, muted),
          ),
      ],
    ),
  );
}

Widget _referenceItem(int n, Map<String, String> r, Color ink, Color muted) {
  final text = formatReference(r);
  final doi = (r['doi'] ?? '').trim();
  final url = (r['url'] ?? '').trim();
  // doi 优先——拼成 https://doi.org/{doi} 可点链接；没 doi 就用 url
  final link = doi.isNotEmpty
      ? (doi.startsWith('http') ? doi : 'https://doi.org/$doi')
      : url;
  return Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      SizedBox(
        width: 30,
        child: Text(
          '[$n]',
          style: TextStyle(fontSize: 13.5, height: 1.6, color: muted),
        ),
      ),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (text.isNotEmpty)
              Text(
                text,
                style: TextStyle(fontSize: 13.5, height: 1.6, color: ink),
              ),
            if (link.isNotEmpty)
              GestureDetector(
                onTap: () => _openExternally(link),
                child: Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    link,
                    style: const TextStyle(
                      fontSize: 12.5,
                      height: 1.5,
                      color: _primary,
                      decoration: TextDecoration.underline,
                      decorationColor: _primary,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    ],
  );
}

String _formatBytes(int bytes) {
  if (bytes < 1024) return '${bytes}B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)}KB';
  return '${(bytes / 1024 / 1024).toStringAsFixed(1)}MB';
}

// file/audio/link 三种 block 阅读视角长得很像（图标+标题+副标题的卡片），
// 抽成一个小 helper，不用三份几乎一样的 Container+Row
Widget _tappableCard(
  BuildContext context, {
  required String url,
  required EdgeInsets margin,
  Color? color,
  required Color borderColor,
  required IconData leadingIcon,
  bool leadingIconIsCircle = false,
  required Color leadingColor,
  Color? leadingBg,
  required String title,
  Color? titleColor,
  String? subtitle,
  Color? subtitleColor,
  IconData? trailingIcon,
  Color? trailingColor,
}) {
  return GestureDetector(
    onTap: url.isEmpty ? null : () => _openExternally(url),
    child: Container(
      margin: margin,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color ?? Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: borderColor),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: leadingBg ?? leadingColor,
              shape: leadingIconIsCircle ? BoxShape.circle : BoxShape.rectangle,
              borderRadius: leadingIconIsCircle
                  ? null
                  : BorderRadius.circular(8),
            ),
            child: Icon(
              leadingIcon,
              color: leadingBg != null ? leadingColor : Colors.white,
              size: 20,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: titleColor,
                  ),
                ),
                if (subtitle != null)
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 11, color: subtitleColor),
                  ),
              ],
            ),
          ),
          if (trailingIcon != null)
            Icon(trailingIcon, color: trailingColor, size: 18),
        ],
      ),
    ),
  );
}
