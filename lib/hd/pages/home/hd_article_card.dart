import 'package:flutter/material.dart';

import '../../../shared/models/tutorial_model.dart';

const _primary = Color(0xFF6366F1);

// HD 列表文章卡——首页/发现列表面板共用。标题(2行) + 领域标签 + 作者 + 浏览/
// 点赞。选中态紫色左竖条 + 背景高亮
class HdArticleCard extends StatelessWidget {
  final TutorialModel t;
  final bool selected;
  final VoidCallback onTap;
  const HdArticleCard({
    super.key,
    required this.t,
    required this.selected,
    required this.onTap,
  });

  static String fmt(int n) =>
      n >= 1000 ? '${(n / 1000).toStringAsFixed(1)}k' : '$n';

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final ink = isDark ? const Color(0xFFE6E6E6) : const Color(0xFF1A1A1A);
    final muted = isDark ? const Color(0xFF888C9E) : const Color(0xFF999999);
    final divider = isDark
        ? Colors.white.withValues(alpha: 0.06)
        : const Color(0xFFEDEDED);
    final tag = t.tags.isNotEmpty ? t.tags.first : null;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: selected
              ? _primary.withValues(alpha: isDark ? 0.14 : 0.06)
              : Colors.transparent,
          border: Border(
            left: BorderSide(
              color: selected ? _primary : Colors.transparent,
              width: 3,
            ),
            bottom: BorderSide(color: divider, width: 0.5),
          ),
        ),
        padding: const EdgeInsets.fromLTRB(13, 12, 14, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              t.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                height: 1.35,
                color: ink,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                if (tag != null) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 7,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: isDark
                          ? _primary.withValues(alpha: 0.16)
                          : const Color(0xFFEEF0FF),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      tag,
                      style: const TextStyle(fontSize: 10, color: _primary),
                    ),
                  ),
                  const SizedBox(width: 6),
                ],
                Expanded(
                  child: Text(
                    t.username,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 11, color: muted),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Icon(Icons.remove_red_eye_outlined, size: 12, color: muted),
                const SizedBox(width: 3),
                Text(
                  fmt(t.views),
                  style: TextStyle(fontSize: 11, color: muted),
                ),
                const SizedBox(width: 10),
                Icon(Icons.favorite_border, size: 12, color: muted),
                const SizedBox(width: 3),
                Text(
                  fmt(t.likes),
                  style: TextStyle(fontSize: 11, color: muted),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
