import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../../shared/models/tutorial_model.dart';

// 教程九宫格卡片没有封面图时的兜底渐变——深色主题用深色两色渐变，跟深色
// 底色连成一体；浅色主题保留原来那套浅色纯色块+图标，不强行套深色
const _coverPaletteDark = [
  (gradient: [Color(0xFF3B2F63), Color(0xFF1F1B3A)]),
  (gradient: [Color(0xFF6D28D9), Color(0xFF3B0764)]),
  (gradient: [Color(0xFF115E59), Color(0xFF0F2027)]),
  (gradient: [Color(0xFF9A3412), Color(0xFF27140D)]),
  (gradient: [Color(0xFF1E3A8A), Color(0xFF0B1120)]),
];
const _coverPaletteLight = [
  (bg: Color(0xFFEEF2FF), icon: Icons.bar_chart, fg: Color(0xFF6366F1)),
  (bg: Color(0xFFECFDF5), icon: Icons.functions, fg: Color(0xFF16A34A)),
  (bg: Color(0xFFFFF7ED), icon: Icons.psychology, fg: Color(0xFFD97706)),
  (bg: Color(0xFFFDF2F8), icon: Icons.code, fg: Color(0xFFDB2777)),
  (bg: Color(0xFFEFF6FF), icon: Icons.table_chart, fg: Color(0xFF2563EB)),
];

// 教程九宫格 item
class TutorialGridItem extends StatelessWidget {
  final TutorialModel tutorial;
  final VoidCallback onTap;

  const TutorialGridItem({
    super.key,
    required this.tutorial,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final idx = tutorial.title.isNotEmpty
        ? tutorial.title.codeUnitAt(0) %
              (isDark ? _coverPaletteDark.length : _coverPaletteLight.length)
        : 0;
    final fallbackBg = isDark
        ? DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: _coverPaletteDark[idx].gradient,
              ),
            ),
          )
        : Container(
            color: _coverPaletteLight[idx].bg,
            child: Icon(
              _coverPaletteLight[idx].icon,
              size: 32,
              color: _coverPaletteLight[idx].fg,
            ),
          );

    return GestureDetector(
      onTap: onTap,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // 缩略图纯装饰，标题/点赞/浏览量在下面 Positioned 里另有文字承载，
          // 排除出语义树——跟头图/头像同一个坑，图片异步加载完成的 relayout
          // 可能跟tab切换/滚动同一帧抢语义树更新
          ExcludeSemantics(
            child: tutorial.coverImage?.isNotEmpty == true
                ? CachedNetworkImage(
                    imageUrl: tutorial.coverImage!,
                    fit: BoxFit.cover,
                    placeholder: (context, url) => fallbackBg,
                    errorWidget: (context, url, error) => fallbackBg,
                  )
                : fallbackBg,
          ),

          // 底部渐变信息
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              padding: const EdgeInsets.all(6),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: [Colors.black54, Colors.transparent],
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    tutorial.title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      const Icon(
                        Icons.favorite,
                        size: 10,
                        color: Colors.white70,
                      ),
                      const SizedBox(width: 2),
                      Text(
                        '${tutorial.likes}',
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 10,
                        ),
                      ),
                      const SizedBox(width: 6),
                      const Icon(
                        Icons.visibility,
                        size: 10,
                        color: Colors.white70,
                      ),
                      const SizedBox(width: 2),
                      Text(
                        '${tutorial.views}',
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 10,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
