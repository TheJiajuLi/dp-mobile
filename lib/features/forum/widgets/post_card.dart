import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';

import '../models/forum_post_model.dart';

const _primary = AppColors.primary;

// 论坛统一的相对时间格式。后端 created_at 是秒级时间戳
String forumTimeAgo(int ts) {
  final diff = DateTime.now().difference(
    DateTime.fromMillisecondsSinceEpoch(ts * 1000),
  );
  if (diff.inMinutes < 1) return '刚刚';
  if (diff.inMinutes < 60) return '${diff.inMinutes}分钟前';
  if (diff.inHours < 24) return '${diff.inHours}小时前';
  return '${diff.inDays}天前';
}

// 帖子列表里的单条卡片
class PostCard extends StatelessWidget {
  final ForumPost post;
  final VoidCallback onTap;

  const PostCard({super.key, required this.post, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: isDark
                  ? Colors.white.withValues(alpha: 0.06)
                  : const Color(0xFFEBEBEB),
              width: 0.5,
            ),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 精华标识
            if (post.isFeatured)
              Container(
                margin: const EdgeInsets.only(bottom: 6),
                padding: const EdgeInsets.symmetric(
                  horizontal: 7,
                  vertical: 2,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFFFEF3C7),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.star, size: 10, color: Color(0xFFD97706)),
                    SizedBox(width: 3),
                    Text(
                      '精华',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w500,
                        color: Color(0xFFD97706),
                      ),
                    ),
                  ],
                ),
              ),

            // 作者行
            Row(
              children: [
                CircleAvatar(
                  radius: 13,
                  backgroundColor: _primary,
                  child: Text(
                    post.authorName.isNotEmpty ? post.authorName[0] : 'U',
                    style: const TextStyle(
                      fontSize: 10,
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(width: 7),
                Flexible(
                  child: Text(
                    post.authorName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      color: isDark
                          ? Colors.white.withValues(alpha: 0.5)
                          : Colors.grey[500],
                    ),
                  ),
                ),
                if (post.isAuroraCreator)
                  Container(
                    margin: const EdgeInsets.only(left: 4),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 5,
                      vertical: 1,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1A0E2E),
                      borderRadius: BorderRadius.circular(3),
                    ),
                    child: const Text(
                      '★ 极光',
                      style: TextStyle(
                        fontSize: 9,
                        color: Color(0xFFF59E0B),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                const Spacer(),
                Text(
                  forumTimeAgo(post.createdAt),
                  style: TextStyle(
                    fontSize: 10,
                    color: isDark
                        ? Colors.white.withValues(alpha: 0.3)
                        : Colors.grey[400],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 7),

            // 标题
            Text(
              post.title,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w500,
                color: isDark
                    ? Colors.white.withValues(alpha: 0.9)
                    : const Color(0xFF1A1A1A),
                height: 1.4,
              ),
            ),
            const SizedBox(height: 5),

            // 预览（最多2行）
            if (post.content.isNotEmpty)
              Text(
                post.content,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13,
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.4)
                      : Colors.grey[500],
                  height: 1.6,
                ),
              ),

            const SizedBox(height: 8),

            // 底部统计
            Row(
              children: [
                _Stat(Icons.remove_red_eye_outlined, post.viewCount),
                const SizedBox(width: 12),
                _Stat(Icons.chat_bubble_outline, post.replyCount),
                const SizedBox(width: 12),
                _Stat(Icons.favorite_border, post.likeCount),
                const Spacer(),
                if (post.tags.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 7,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEEF0FF),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      post.tags.first,
                      style: const TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w500,
                        color: _primary,
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  final IconData icon;
  final int count;
  const _Stat(this.icon, this.count);

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Icon(icon, size: 13, color: Colors.grey[400]),
      const SizedBox(width: 3),
      Text(
        count > 999 ? '${(count / 1000).toStringAsFixed(1)}k' : '$count',
        style: TextStyle(fontSize: 12, color: Colors.grey[400]),
      ),
    ],
  );
}
