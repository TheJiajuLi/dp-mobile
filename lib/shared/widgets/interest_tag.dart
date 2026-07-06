import 'dart:ui';

import 'package:flutter/material.dart';

import '../../core/constants/tag_colors.dart';
import '../utils/topic_badge.dart';

class InterestTag extends StatelessWidget {
  final String label;
  final bool selected;
  final bool removable;
  final VoidCallback? onTap;
  final VoidCallback? onRemove;
  // tag_colors.dart 那套毛玻璃配色（半透明底+浅色字）是专门给个人主页
  // 深色头图区设计的——那里背景永远是深色照片/渐变，BackdropFilter 模糊
  // 之后浅色字才有对比度。编辑资料页的兴趣标签选择器是普通的浅色卡片/
  // 页面背景，同一套浅色字糊在浅色底上完全看不清（2026-07-06 实测发现），
  // 这种场景改用 glass:false，走 topic_badge.dart 那套"白卡浅底实色字"
  // 配色——不是新写一套，是复用已经验证过在浅色背景上可读的现成方案
  final bool glass;

  const InterestTag({
    super.key,
    required this.label,
    this.selected = true,
    this.removable = false,
    this.onTap,
    this.onRemove,
    this.glass = true,
  });

  @override
  Widget build(BuildContext context) {
    if (!glass) return _buildSolid();

    final cat = inferCategory(label);
    // 未选中（推荐栏里还没被加进已选列表的）比选中的更淡一档，靠降低同一份
    // 底色/描边色本来就带的透明度实现，不是原地叠加一个固定的 0.5——不然
    // 未选中反而会比选中的更"实"（原色本来就是低透明度的玻璃感）
    final bg = selected
        ? cat.bgColor
        : cat.bgColor.withValues(alpha: cat.bgColor.a * 0.5);
    final border = selected
        ? cat.borderColor
        : cat.borderColor.withValues(alpha: cat.borderColor.a * 0.5);

    return GestureDetector(
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(99),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(99),
              border: Border.all(color: border, width: selected ? 1.2 : 0.8),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: cat.textColor,
                  ),
                ),
                if (removable) ...[
                  const SizedBox(width: 4),
                  GestureDetector(
                    onTap: onRemove,
                    child: Icon(
                      Icons.close,
                      size: 13,
                      color: cat.textColor.withValues(alpha: 0.7),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSolid() {
    final (bg, fg) = topicBadgeStyleFor(label);
    // 未选中态不需要靠透明度做区分（没有玻璃底透明度可以借），改成不描边
    // vs 描边——选中实色块，未选中只留一圈同色细边+更淡的字，一样能分清
    // 两种状态，且在白色背景上足够清楚
    final effectiveBg = selected ? bg : Colors.transparent;
    final effectiveFg = selected ? fg : fg.withValues(alpha: 0.7);

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: effectiveBg,
          borderRadius: BorderRadius.circular(99),
          border: selected
              ? null
              : Border.all(color: fg.withValues(alpha: 0.4)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: effectiveFg,
              ),
            ),
            if (removable) ...[
              const SizedBox(width: 4),
              GestureDetector(
                onTap: onRemove,
                child: Icon(
                  Icons.close,
                  size: 13,
                  color: effectiveFg.withValues(alpha: 0.7),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
