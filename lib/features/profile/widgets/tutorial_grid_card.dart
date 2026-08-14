import 'package:cached_network_image/cached_network_image.dart';
import '../../../core/theme/app_colors.dart';
import 'package:flutter/material.dart';

import '../../../shared/models/tutorial_model.dart';

const _primary = AppColors.primary;

// 收藏/点赞 tab 用的小红书风格网格卡片——封面图+标题+作者+点赞数，跟
// 文章 tab 的横向列表卡片（tutorial_list_card.dart）是两种不同场景各自
// 合适的呈现：文章 tab 是"我发布的内容"，条目少、信息密度要高；收藏/
// 点赞是"别人的内容合集"，条目可能很多，网格更适合快速浏览。注意这是
// 固定宽高比的两列网格，不是真正逐条不同高度的瀑布流——项目里没有
// flutter_staggered_grid_view 这类依赖，做真瀑布流需要先加这个包
class TutorialGridCard extends StatelessWidget {
  final TutorialModel tutorial;
  final VoidCallback onTap;

  const TutorialGridCard({
    super.key,
    required this.tutorial,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1A1A2E) : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isDark ? const Color(0xFF2A2A4A) : const Color(0xFFEBEBEB),
            width: 0.5,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            ClipRRect(
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(12),
              ),
              child: AspectRatio(
                aspectRatio: 16 / 9,
                child: tutorial.coverImage?.isNotEmpty == true
                    ? CachedNetworkImage(
                        imageUrl: tutorial.coverImage!,
                        fit: BoxFit.cover,
                        errorWidget: (_, _, _) => _defaultCover(isDark),
                      )
                    : _defaultCover(isDark),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    tutorial.title,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: isDark ? Colors.white : const Color(0xFF1A1A1A),
                      height: 1.4,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      ClipOval(
                        child: SizedBox(
                          width: 18,
                          height: 18,
                          child: tutorial.avatar?.isNotEmpty == true
                              ? CachedNetworkImage(
                                  imageUrl: tutorial.avatar!,
                                  fit: BoxFit.cover,
                                  errorWidget: (_, _, _) => _avatarFallback(),
                                )
                              : _avatarFallback(),
                        ),
                      ),
                      const SizedBox(width: 5),
                      Expanded(
                        child: Text(
                          tutorial.username,
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.grey[500],
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Icon(Icons.favorite, size: 11, color: Colors.grey[400]),
                      const SizedBox(width: 2),
                      Text(
                        '${tutorial.likes}',
                        style: TextStyle(fontSize: 11, color: Colors.grey[400]),
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

  Widget _avatarFallback() => Container(
    color: _primary,
    child: const Center(
      child: Text(
        '梦',
        style: TextStyle(fontSize: 8, color: Colors.white),
      ),
    ),
  );

  Widget _defaultCover(bool isDark) => Container(
    color: isDark ? const Color(0xFF252540) : AppColors.primaryLight,
    child: const Center(
      child: Icon(Icons.auto_stories, color: _primary, size: 28),
    ),
  );
}
