import 'dart:convert';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../core/widgets/founding_badge.dart';
import '../models/tutorial_model.dart';
import 'tutorial_block_renderer.dart' show inlineLatexText;

const _primary = Color(0xFF6366F1);

// 主页「文章流」列表项——头图/来源行 + 标题 + 作者 + 摘要+小缩略图 +
// 一排操作按钮，条目之间用整行分割线隔开（不是浮起来的圆角卡片）。
// 首页发现流和「我的」页文章/收藏/点赞共用这一套，保证视觉完全一致。
// onHide 传了才显示右下角的「×」（首页的不感兴趣），主页个人页不传就不显示。
class ArticleFlowItem extends StatelessWidget {
  final TutorialModel tutorial;
  final VoidCallback onTap;
  final VoidCallback? onHide;
  const ArticleFlowItem({
    super.key,
    required this.tutorial,
    required this.onTap,
    this.onHide,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textPrimary = isDark
        ? AppColors.darkTextPrimary
        : const Color(0xFF1A1A1A);
    final textSecondary = isDark
        ? AppColors.darkTextSecondary
        : const Color(0xFF888888);
    final divider = isDark ? AppColors.darkDivider : const Color(0xFFF0F0F0);

    return GestureDetector(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 14, 12, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  tutorial.title,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: textPrimary,
                    height: 1.45,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    _AuthorAvatar(
                      avatar: tutorial.avatar,
                      username: tutorial.username,
                      isFoundingCreator: tutorial.isFoundingCreator,
                      radius: 11,
                    ),
                    const SizedBox(width: 7),
                    Text(
                      tutorial.username,
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFF888888),
                      ),
                    ),
                  ],
                ),
                if ((tutorial.preview?.isNotEmpty ?? false) ||
                    tutorial.coverImage?.isNotEmpty == true) ...[
                  const SizedBox(height: 8),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (tutorial.preview?.isNotEmpty ?? false)
                        Expanded(
                          child: inlineLatexText(
                            tutorial.preview!,
                            TextStyle(
                              fontSize: 13,
                              color: textSecondary,
                              height: 1.7,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        )
                      else
                        const Spacer(),
                      // 封面只做成小卡片缩略图，不再铺满一整行——没有封面
                      // 就完全不占位，不留空白。缩略图之前是76，没有摘要
                      // 文字的文章（preview为空）这一行就只有一个空
                      // Spacer+这么高的图，整张卡片被撑得很高，操作栏被
                      // 顶到很下面——缩小到44，摘要文字环绕在左边，图小了
                      // 整行高度也跟着降下来，操作栏自然就上移了
                      if (tutorial.coverImage?.isNotEmpty == true) ...[
                        const SizedBox(width: 10),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: CachedNetworkImage(
                            imageUrl: tutorial.coverImage!,
                            width: 44,
                            height: 44,
                            fit: BoxFit.cover,
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Row(
                    children: [
                      _ActionBtn(
                        icon: Icons.thumb_up_outlined,
                        label: '${tutorial.likes}',
                        isDark: isDark,
                        onTap: onTap,
                      ),
                      _ActionBtn(
                        icon: Icons.bookmark_outline,
                        label: '收藏',
                        isDark: isDark,
                        onTap: onTap,
                      ),
                      _ActionBtn(
                        icon: Icons.chat_bubble_outline,
                        label: '评论',
                        isDark: isDark,
                        onTap: onTap,
                      ),
                      const Spacer(),
                      if (onHide != null)
                        GestureDetector(
                          onTap: onHide,
                          child: Icon(
                            Icons.close,
                            size: 16,
                            color: isDark
                                ? const Color(0xFF444444)
                                : const Color(0xFFCCCCCC),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Container(height: 0.5, color: divider),
        ],
      ),
    );
  }
}

class _ActionBtn extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isDark;
  final VoidCallback onTap;
  const _ActionBtn({
    required this.icon,
    required this.label,
    required this.isDark,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = isDark ? const Color(0xFF666666) : const Color(0xFF888888);
    return GestureDetector(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.only(right: 20),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(width: 4),
            Text(label, style: TextStyle(fontSize: 12, color: color)),
          ],
        ),
      ),
    );
  }
}

class _AuthorAvatar extends StatelessWidget {
  final String? avatar;
  final String username;
  final double radius;
  final bool isFoundingCreator;
  const _AuthorAvatar({
    required this.avatar,
    required this.username,
    this.radius = 9,
    this.isFoundingCreator = false,
  });

  Widget _letter() => CircleAvatar(
    radius: radius,
    backgroundColor: _primary.withValues(alpha: 0.15),
    child: Text(
      username.isNotEmpty ? username.substring(0, 1) : '?',
      style: TextStyle(
        fontSize: radius,
        fontWeight: FontWeight.w700,
        color: _primary,
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    return FoundingAvatarRing(
      isFoundingCreator: isFoundingCreator,
      size: radius * 2,
      child: _content(context),
    );
  }

  Widget _content(BuildContext context) {
    if (avatar == null || avatar!.isEmpty) return _letter();

    if (avatar!.startsWith('data:image')) {
      try {
        final raw = avatar!.split(',').last;
        return CircleAvatar(
          radius: radius,
          backgroundImage: MemoryImage(base64Decode(raw)),
        );
      } catch (_) {
        return _letter();
      }
    }

    return ClipOval(
      child: SizedBox(
        width: radius * 2,
        height: radius * 2,
        child: CachedNetworkImage(
          imageUrl: avatar!,
          fit: BoxFit.cover,
          placeholder: (context, url) =>
              Container(color: Theme.of(context).dividerColor),
          errorWidget: (context, url, error) => _letter(),
        ),
      ),
    );
  }
}
