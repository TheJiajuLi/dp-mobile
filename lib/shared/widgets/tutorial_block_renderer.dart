import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../l10n/generated/app_localizations.dart';

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
  Map<String, dynamic> block,
) {
  final type = block['type'] as String? ?? 'text';
  final content = block['content'] as String? ?? '';

  switch (type) {
    case 'heading':
      final level = block['level'] as int? ?? 2;
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
        child: Text(
          content,
          style: TextStyle(
            fontSize: level == 2
                ? 20
                : level == 3
                ? 17
                : 15,
            fontWeight: FontWeight.w700,
            color: Theme.of(context).textTheme.bodyLarge?.color,
          ),
        ),
      );

    case 'code':
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
                      block['language'] as String? ?? 'python',
                      style: const TextStyle(
                        fontSize: 11,
                        color: Colors.white70,
                        fontWeight: FontWeight.w600,
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
                child: Text(
                  content,
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 13,
                    color: Colors.white,
                    height: 1.6,
                  ),
                ),
              ),
            ),
          ],
        ),
      );

    case 'latex':
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Math.tex(
          content.replaceAll(r'$$', '').trim(),
          textStyle: const TextStyle(fontSize: 16),
          onErrorFallback: (err) => Text(
            content,
            style: const TextStyle(color: Colors.red, fontSize: 12),
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
        subtitle: l10n.tapToPlayLabel,
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
                child: Text(
                  fileName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12, color: Colors.white70),
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

    case 'callout':
      final variant = block['variant'] as String? ?? 'info';
      final colors = {
        'tip': const Color(0xFF16A34A),
        'warning': const Color(0xFFD97706),
        'info': _primary,
      };
      final bgColors = {
        'tip': const Color(0xFFE8F8F0),
        'warning': const Color(0xFFFFF7E6),
        'info': const Color(0xFFEEF0FF),
      };
      return Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: bgColors[variant] ?? const Color(0xFFEEF0FF),
          borderRadius: BorderRadius.circular(10),
          border: Border(
            left: BorderSide(color: colors[variant] ?? _primary, width: 3),
          ),
        ),
        child: Text(
          content,
          style: TextStyle(
            fontSize: 14,
            color: colors[variant] ?? _primary,
            height: 1.5,
          ),
        ),
      );

    default: // text
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        child: Text(
          content,
          style: TextStyle(
            fontSize: 15,
            height: 1.7,
            color: Theme.of(context).textTheme.bodyLarge?.color,
          ),
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
