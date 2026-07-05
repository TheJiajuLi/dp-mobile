import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../../l10n/generated/app_localizations.dart';
import '../../../shared/widgets/tutorial_block_renderer.dart';
import '../models/block_model.dart';

const _primary = Color(0xFF6366F1);

class PreviewDrawer extends StatelessWidget {
  final String title;
  final String summary;
  final List<String> tags;
  final List<EditorBlock> blocks;
  final String? coverImageUrl;

  const PreviewDrawer({
    super.key,
    required this.title,
    required this.summary,
    required this.tags,
    required this.blocks,
    this.coverImageUrl,
  });

  // 纯预览用的粗略估算，不追求精确：正文类 block 按字符数算字数，
  // 图片/代码/文件/音频/视频这些"要花时间看"的 block 每个再加 0.5 分钟
  (int words, int minutes) _stats() {
    var chars = 0;
    var heavyBlocks = 0;
    for (final b in blocks) {
      switch (b.type) {
        case BlockType.text:
        case BlockType.heading:
        case BlockType.code:
        case BlockType.latex:
        case BlockType.callout:
          chars += b.content.length;
          if (b.type == BlockType.code || b.type == BlockType.latex) {
            heavyBlocks++;
          }
          break;
        case BlockType.image:
        case BlockType.file:
        case BlockType.audio:
        case BlockType.video:
        case BlockType.link:
          heavyBlocks++;
          break;
      }
    }
    final minutes = ((chars / 200) + heavyBlocks * 0.5).ceil().clamp(1, 999);
    return (chars, minutes);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final (words, minutes) = _stats();

    return Drawer(
      width: MediaQuery.of(context).size.width * 0.86,
      shape: const RoundedRectangleBorder(),
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: const BoxDecoration(
                      color: Color(0xFF16A34A),
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    l10n.livePreviewLabel,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Theme.of(context).textTheme.bodyLarge?.color,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    l10n.readerViewLabel,
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).textTheme.bodySmall?.color,
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: blocks.every((b) => b.content.isEmpty) && title.isEmpty
                  ? Center(
                      child: Text(
                        l10n.previewEmptyContent,
                        style: const TextStyle(color: Colors.grey),
                        textAlign: TextAlign.center,
                      ),
                    )
                  : ListView(
                      padding: const EdgeInsets.only(bottom: 24),
                      children: [
                        if (coverImageUrl != null)
                          CachedNetworkImage(
                            imageUrl: coverImageUrl!,
                            height: 160,
                            width: double.infinity,
                            fit: BoxFit.cover,
                            errorWidget: (context, url, error) =>
                                const SizedBox.shrink(),
                          )
                        else
                          Container(
                            height: 120,
                            width: double.infinity,
                            color: const Color(0xFFEEF0FF),
                            child: const Icon(
                              Icons.show_chart,
                              color: _primary,
                              size: 40,
                            ),
                          ),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                title.isEmpty
                                    ? l10n.notePlaceholderTitle
                                    : title,
                                style: TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.w700,
                                  color: title.isEmpty
                                      ? Colors.grey
                                      : Theme.of(
                                          context,
                                        ).textTheme.bodyLarge?.color,
                                ),
                              ),
                              if (summary.isNotEmpty) ...[
                                const SizedBox(height: 8),
                                Text(
                                  summary,
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: Theme.of(
                                      context,
                                    ).textTheme.bodySmall?.color,
                                  ),
                                ),
                              ],
                              if (tags.isNotEmpty) ...[
                                const SizedBox(height: 10),
                                Wrap(
                                  spacing: 6,
                                  runSpacing: 6,
                                  children: tags
                                      .map(
                                        (tag) => Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 10,
                                            vertical: 4,
                                          ),
                                          decoration: BoxDecoration(
                                            color: const Color(0xFFEEF0FF),
                                            borderRadius: BorderRadius.circular(
                                              99,
                                            ),
                                          ),
                                          child: Text(
                                            tag,
                                            style: const TextStyle(
                                              fontSize: 12,
                                              color: Color(0xFF4F46E5),
                                              fontWeight: FontWeight.w500,
                                            ),
                                          ),
                                        ),
                                      )
                                      .toList(),
                                ),
                              ],
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),
                        const Divider(height: 1),
                        ...blocks.map(
                          (b) => buildTutorialBlockWidget(
                            context,
                            l10n,
                            b.toJson(),
                          ),
                        ),
                      ],
                    ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    l10n.wordsCountLabel(words),
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).textTheme.bodySmall?.color,
                    ),
                  ),
                  Text(
                    l10n.blocksCountLabel(blocks.length),
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).textTheme.bodySmall?.color,
                    ),
                  ),
                  Text(
                    l10n.estimatedReadTime(minutes),
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).textTheme.bodySmall?.color,
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
}
