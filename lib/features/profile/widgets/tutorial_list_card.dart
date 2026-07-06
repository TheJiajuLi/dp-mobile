import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../../l10n/generated/app_localizations.dart';
import '../../../shared/models/tutorial_model.dart';
import '../../../shared/utils/topic_badge.dart';
import '../../messages/screens/messages_screen.dart' show timeAgo;

// 主页"文章"tab 列表卡片——缩略图在左，标题/摘要/时间在右，仿截图参考
// 设计，替代原来的九宫格瀑布流展示
class TutorialListCard extends StatelessWidget {
  final TutorialModel tutorial;
  final VoidCallback onTap;
  final VoidCallback? onMoreTap;

  const TutorialListCard({
    super.key,
    required this.tutorial,
    required this.onTap,
    this.onMoreTap,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final category = tutorial.tags.isNotEmpty ? tutorial.tags.first : null;
    final badgeStyle = category != null ? topicBadgeStyleFor(category) : null;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isDark ? Colors.white.withValues(alpha: 0.06) : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isDark ? Colors.white12 : const Color(0xFFF0F0F0),
            width: 0.5,
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: SizedBox(
                width: 78,
                height: 66,
                child: tutorial.coverImage?.isNotEmpty == true
                    ? ExcludeSemantics(
                        child: CachedNetworkImage(
                          imageUrl: tutorial.coverImage!,
                          fit: BoxFit.cover,
                          errorWidget: (_, _, _) => Container(
                            color: badgeStyle?.$1 ?? Colors.grey[200],
                          ),
                        ),
                      )
                    : Container(color: badgeStyle?.$1 ?? Colors.grey[200]),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      if (category != null && badgeStyle != null)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 7,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: badgeStyle.$1,
                            borderRadius: BorderRadius.circular(5),
                          ),
                          child: Text(
                            category,
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: badgeStyle.$2,
                            ),
                          ),
                        ),
                      const Spacer(),
                      GestureDetector(
                        onTap: onMoreTap,
                        behavior: HitTestBehavior.opaque,
                        child: Icon(
                          Icons.more_horiz,
                          size: 18,
                          color: isDark ? Colors.white38 : Colors.grey[400],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    tutorial.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: isDark ? Colors.white : const Color(0xFF1A1A1A),
                    ),
                  ),
                  if (tutorial.summary?.isNotEmpty == true) ...[
                    const SizedBox(height: 2),
                    Text(
                      tutorial.summary!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        color: isDark ? Colors.white54 : Colors.grey[600],
                      ),
                    ),
                  ],
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Text(
                        timeAgo(l10n, tutorial.createdAt),
                        style: TextStyle(
                          fontSize: 11,
                          color: isDark ? Colors.white38 : Colors.grey[500],
                        ),
                      ),
                      const SizedBox(width: 10),
                      Icon(
                        Icons.remove_red_eye_outlined,
                        size: 12,
                        color: isDark ? Colors.white38 : Colors.grey[500],
                      ),
                      const SizedBox(width: 2),
                      Text(
                        '${tutorial.views}',
                        style: TextStyle(
                          fontSize: 11,
                          color: isDark ? Colors.white38 : Colors.grey[500],
                        ),
                      ),
                      const SizedBox(width: 10),
                      Icon(
                        Icons.favorite_outline,
                        size: 12,
                        color: isDark ? Colors.white38 : Colors.grey[500],
                      ),
                      const SizedBox(width: 2),
                      Text(
                        '${tutorial.likes}',
                        style: TextStyle(
                          fontSize: 11,
                          color: isDark ? Colors.white38 : Colors.grey[500],
                        ),
                      ),
                    ],
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
