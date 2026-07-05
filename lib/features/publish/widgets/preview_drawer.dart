import 'dart:convert';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/generated/app_localizations.dart';
import '../../../shared/widgets/tutorial_block_renderer.dart';
import '../../auth/auth_service.dart';
import '../models/block_model.dart';

const _primary = Color(0xFF6366F1);
const _ink = Color(0xFF1A1A1A);
const _bg = Color(0xFFFAFAF8);

class PreviewDrawer extends ConsumerWidget {
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

  Widget _authorAvatar(String? avatar, String username) {
    if (avatar != null && avatar.isNotEmpty) {
      if (avatar.startsWith('data:image')) {
        try {
          return CircleAvatar(
            radius: 14,
            backgroundImage: MemoryImage(base64Decode(avatar.split(',').last)),
          );
        } catch (_) {
          // 解码失败落到下面的首字母占位
        }
      } else {
        return CircleAvatar(
          radius: 14,
          backgroundImage: CachedNetworkImageProvider(avatar),
        );
      }
    }
    return CircleAvatar(
      radius: 14,
      backgroundColor: _primary,
      child: Text(
        username.isNotEmpty ? username.substring(0, 1).toUpperCase() : '?',
        style: const TextStyle(
          color: Colors.white,
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final user = ref.watch(currentUserProvider);
    final (words, minutes) = computeBlockStats(blocks);
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;

    return Drawer(
      width: MediaQuery.of(context).size.width * 0.86,
      shape: const RoundedRectangleBorder(),
      // "读者预览"跟首页 Feed 用同一套米白底视觉语言，不再跟着全局主题的
      // #F7F7FB 走——深色模式还是继续用主题自己的背景色
      backgroundColor: isDarkMode
          ? Theme.of(context).scaffoldBackgroundColor
          : _bg,
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
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
                          child: Row(
                            children: [
                              _authorAvatar(user?.avatar, user?.username ?? ''),
                              const SizedBox(width: 8),
                              Text(
                                user?.username ?? '',
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: _ink,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                '${l10n.timeJustNow} · ${l10n.estimatedReadTime(minutes)}',
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: Color(0xFF999999),
                                ),
                              ),
                              const Spacer(),
                              // 跟最终发布页读者看到的一致——收藏/分享目前
                              // 都还没有真正的后端接口，点了给个"即将上线"
                              // 占位，不是纯装饰
                              GestureDetector(
                                onTap: () =>
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text(l10n.comingSoonStayTuned),
                                      ),
                                    ),
                                child: const Icon(
                                  Icons.bookmark_border,
                                  size: 19,
                                  color: Color(0xFF999999),
                                ),
                              ),
                              const SizedBox(width: 14),
                              GestureDetector(
                                onTap: () =>
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text(l10n.comingSoonStayTuned),
                                      ),
                                    ),
                                child: const Icon(
                                  Icons.share_outlined,
                                  size: 19,
                                  color: Color(0xFF999999),
                                ),
                              ),
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
