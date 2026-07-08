import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../../l10n/generated/app_localizations.dart';
import '../../../shared/models/tutorial_model.dart';
import '../../../shared/utils/topic_badge.dart';
import '../../messages/utils/message_avatar.dart' show messageTimeAgo;

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
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1E1E22) : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isDark ? Colors.white12 : const Color(0xFFF0F0F0),
            width: 0.5,
          ),
          boxShadow: isDark
              ? null
              : [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.03),
                    blurRadius: 12,
                    offset: const Offset(0, 3),
                  ),
                ],
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: SizedBox(
                width: 92,
                height: 76,
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
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      if (category != null && badgeStyle != null)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: badgeStyle.$1,
                            borderRadius: BorderRadius.circular(99),
                          ),
                          child: Text(
                            category,
                            style: TextStyle(
                              fontSize: 10.5,
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
                  const SizedBox(height: 6),
                  Text(
                    tutorial.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 15.5,
                      fontWeight: FontWeight.w700,
                      height: 1.3,
                      color: isDark ? Colors.white : const Color(0xFF1A1A1A),
                    ),
                  ),
                  if (tutorial.summary?.isNotEmpty == true) ...[
                    const SizedBox(height: 4),
                    Text(
                      tutorial.summary!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12.5,
                        height: 1.4,
                        color: isDark ? Colors.white54 : Colors.grey[600],
                      ),
                    ),
                  ],
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Text(
                        messageTimeAgo(l10n, tutorial.createdAt),
                        style: TextStyle(
                          fontSize: 11.5,
                          color: isDark ? Colors.white38 : Colors.grey[500],
                        ),
                      ),
                      _statDot(isDark),
                      Icon(
                        Icons.remove_red_eye_outlined,
                        size: 13,
                        color: isDark ? Colors.white38 : Colors.grey[500],
                      ),
                      const SizedBox(width: 3),
                      Text(
                        '${tutorial.views}',
                        style: TextStyle(
                          fontSize: 11.5,
                          color: isDark ? Colors.white38 : Colors.grey[500],
                        ),
                      ),
                      _statDot(isDark),
                      Icon(
                        Icons.favorite_outline,
                        size: 13,
                        color: isDark ? Colors.white38 : Colors.grey[500],
                      ),
                      const SizedBox(width: 3),
                      Text(
                        '${tutorial.likes}',
                        style: TextStyle(
                          fontSize: 11.5,
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

  Widget _statDot(bool isDark) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 8),
    child: Container(
      width: 2.5,
      height: 2.5,
      decoration: BoxDecoration(
        color: isDark ? Colors.white24 : Colors.grey[400],
        shape: BoxShape.circle,
      ),
    ),
  );
}
