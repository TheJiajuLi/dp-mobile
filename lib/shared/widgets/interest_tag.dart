import 'dart:ui';

import 'package:flutter/material.dart';

import '../../core/constants/tag_colors.dart';

class InterestTag extends StatelessWidget {
  final String label;
  final bool selected;
  final bool removable;
  final VoidCallback? onTap;
  final VoidCallback? onRemove;

  const InterestTag({
    super.key,
    required this.label,
    this.selected = true,
    this.removable = false,
    this.onTap,
    this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
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
}
