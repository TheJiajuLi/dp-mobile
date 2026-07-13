import 'dart:convert';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../l10n/generated/app_localizations.dart';
import '../services/pyodide_engine.dart';
import '../utils/block_text_style.dart';
import '../utils/code_highlight.dart';

const _primary = Color(0xFF6366F1);

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
}) {
  final type = block['type'] as String? ?? 'text';
  final content = block['content'] as String? ?? '';

  switch (type) {
    case 'heading':
      final level = block['level'] as int? ?? 2;
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
        child: Text(
          content,
          style: applyBlockTextFormat(
            TextStyle(
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
          ),
        ),
      );

    case 'code':
      return TutorialCodeBlock(
        content: content,
        language: block['language'] as String? ?? 'python',
      );

    case 'latex':
      // Math.tex 不会自动换行/收缩——公式比屏幕宽（长积分式/多项连乘）
      // 会顶穿右边界溢出。套一层横向滚动，宽公式改成左右滑动
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Math.tex(
            content.replaceAll(r'$$', '').trim(),
            textStyle: const TextStyle(fontSize: 16),
            onErrorFallback: (err) => Text(
              content,
              style: const TextStyle(color: Colors.red, fontSize: 12),
            ),
          ),
        ),
      );

    case 'image':
      final imageUrl = block['imageUrl'] as String? ?? '';
      if (imageUrl.isEmpty) return const SizedBox.shrink();
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
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
                      style: const TextStyle(fontSize: 12, color: Colors.white70),
                    ),
                    Text(
                      l10n.tapToPlayExternalLabel,
                      style: const TextStyle(fontSize: 10.5, color: Colors.white54),
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
        leadingBg: const Color(0xFFEEF0FF),
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
              'info': Color(0xFFEEF0FF),
            };
      // 文字 + 左侧竖条共用这套强调色，深色下用调淡的色，浅色下保持原样
      final accentColors = isDark
          ? const {
              'tip': Color(0xFF5BC48A),
              'warning': Color(0xFFD4A842),
              'info': Color(0xFF9B9EF8),
            }
          : const {
              'tip': Color(0xFF16A34A),
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
          border: Border(
            left: BorderSide(color: accent, width: 3),
          ),
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

    default: // text
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        child: Text(
          content,
          style: applyBlockTextFormat(
            TextStyle(
              // 阅读页对标 Apple Books 的舒适度：16px、行高 1.85、正文用比
              // 纯黑/纯白更柔和的颜色
              fontSize: readingMode ? 16 : 15,
              height: readingMode ? 1.85 : 1.7,
              letterSpacing: readingMode ? 0.01 : null,
              color: readingMode
                  ? (Theme.of(context).brightness == Brightness.dark
                        ? const Color(0xFFC8CAD8)
                        : const Color(0xFF2A2A2A))
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
          ),
        ),
      );
  }
}

// 教程详情页（阅读视角）里可运行的代码块——只有 python/javascript/sql
// 才显示"运行"按钮，跟发布页共用同一套 PyodideEngine（compiler.js +
// 隐藏 WebView），但各自拥有自己的引擎实例：详情页每次进来都是独立的
// 页面生命周期，没必要也不应该跟发布页共享同一个 WebView
class TutorialCodeBlock extends StatefulWidget {
  final String content;
  final String language;

  const TutorialCodeBlock({
    super.key,
    required this.content,
    required this.language,
  });

  @override
  State<TutorialCodeBlock> createState() => _TutorialCodeBlockState();
}

class _TutorialCodeBlockState extends State<TutorialCodeBlock> {
  static const _runnableLanguages = ['python', 'javascript', 'sql'];

  late final PyodideEngine _engine;
  late final String _blockId;
  bool _running = false;
  String? _outputContent;
  String? _outputType;

  bool get _canRun =>
      _runnableLanguages.contains(widget.language.toLowerCase());

  @override
  void initState() {
    super.initState();
    _blockId = UniqueKey().toString();
    _engine = PyodideEngine();
  }

  Future<void> _run() async {
    final l10n = AppLocalizations.of(context)!;
    setState(() => _running = true);
    List<Map<String, dynamic>> outputs;
    try {
      outputs = await _engine.run(
        _blockId,
        widget.content,
        widget.language.toLowerCase(),
        l10n,
      );
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

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF1C1C1E),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
            child: Row(
              children: [
                // macOS 窗口三色点，跟发布页编辑态的代码块保持一致的
                // 视觉语言（读者预览/正式阅读页共用这一份渲染逻辑）
                const _ReaderMacDot(color: Color(0xFFFF5F56)),
                const SizedBox(width: 6),
                const _ReaderMacDot(color: Color(0xFFFFBD2E)),
                const SizedBox(width: 6),
                const _ReaderMacDot(color: Color(0xFF27C93F)),
                const SizedBox(width: 10),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: _primary.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    widget.language,
                    style: const TextStyle(
                      fontSize: 11,
                      color: Colors.white70,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const Spacer(),
                if (_canRun)
                  GestureDetector(
                    onTap: _running ? null : _run,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: _primary,
                        borderRadius: BorderRadius.circular(6),
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
                                color: Colors.white,
                              ),
                            )
                          else
                            const Icon(
                              Icons.play_arrow,
                              size: 14,
                              color: Colors.white,
                            ),
                          const SizedBox(width: 4),
                          Text(
                            _running ? l10n.runningLabel : l10n.runAction,
                            style: const TextStyle(
                              fontSize: 11,
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Text.rich(
                TextSpan(
                  children: highlightCode(
                    widget.content,
                    widget.language.toLowerCase(),
                    const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 13,
                      color: Colors.white,
                      height: 1.6,
                    ),
                  ),
                ),
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
          if (_canRun) _engine.buildHiddenWebView(),
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

class _ReaderMacDot extends StatelessWidget {
  final Color color;
  const _ReaderMacDot({required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 10,
      height: 10,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }
}
