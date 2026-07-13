import 'package:flutter/material.dart';

// 设置页公用的分组标题/卡片/行组件——settings_screen.dart 和
// help_feedback_screen.dart 共用同一套视觉语言（圆角卡片浮在页面背景上，
// 组内相邻行之间才画分割线），抽出来避免两处各写一份容易走样
class SettingsSectionTitle extends StatelessWidget {
  final String title;
  const SettingsSectionTitle(this.title, {super.key});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
    child: Text(
      title.toUpperCase(),
      style: const TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w600,
        color: Colors.grey,
        letterSpacing: 0.5,
      ),
    ),
  );
}

class SettingsGroup extends StatelessWidget {
  final List<Widget> children;
  // 组内行之间分割线的左缩进——带图标方块的行（SettingsRow）用 62 对齐
  // 图标右侧的文字起始位置；纯文字行（比如隐私设置里的开关，没有图标
  // 方块）用更小的缩进（跟内容左padding对齐），不然分割线会显得凭空
  // 从空白处开始，不是真的"更克制"而是错位
  final double dividerIndent;
  const SettingsGroup(this.children, {super.key, this.dividerIndent = 62});
  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final rows = <Widget>[];
    for (var i = 0; i < children.length; i++) {
      if (i > 0) {
        rows.add(
          Divider(
            height: 0.5,
            thickness: 0.5,
            indent: dividerIndent,
            color: Theme.of(context).dividerColor,
          ),
        );
      }
      rows.add(children[i]);
    }
    // Container 自己的 decoration（border+borderRadius）配 clipBehavior
    // 会有个经典的 Flutter 渲染坑：内部负责裁切的 ClipPath 跟负责画描边
    // 的 BoxDecoration.paint() 用的不是同一份圆角几何，在圆角最尖的那个
    // 点上偶尔会漏出一丁点没被裁掉的直角像素（肉眼要凑近才看得出来）。
    // 拆成外层 Container（只管 margin+阴影，不裁切——阴影本来就要溢出
    // 边界才有效果，裁了阴影就没了）+ 中间 ClipRRect（唯一的裁切来源，
    // 保证圆角边界只有一份权威几何）+ 内层 Container（背景色+描边，被
    // ClipRRect 干净地裁掉多余的角）
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        boxShadow: isDark
            ? null
            : [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.03),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Container(
          decoration: BoxDecoration(
            color: Theme.of(context).cardColor,
            // 加一圈细描边，让"圆框"在深浅色下都清晰可见——深色下本来
            // 没有阴影，卡片容易糊进背景；浅色下描边+淡阴影一起更有
            // 一线产品的边界感
            border: Border.all(
              color: Theme.of(context).dividerColor,
              width: 0.5,
            ),
          ),
          child: Column(children: rows),
        ),
      ),
    );
  }
}

class SettingsRow extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final Color iconBg;
  final String title;
  final String? subtitle;
  final String? trailing;
  final VoidCallback onTap;

  const SettingsRow({
    super.key,
    required this.icon,
    required this.iconColor,
    required this.iconBg,
    required this.title,
    this.subtitle,
    this.trailing,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: iconBg,
                borderRadius: BorderRadius.circular(9),
              ),
              child: Icon(icon, color: iconColor, size: 17),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 15,
                      color: Theme.of(context).textTheme.bodyLarge?.color,
                    ),
                  ),
                  if (subtitle != null)
                    Text(
                      subtitle!,
                      style: const TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                ],
              ),
            ),
            if (trailing != null)
              Text(
                trailing!,
                style: const TextStyle(fontSize: 14, color: Colors.grey),
              ),
            const SizedBox(width: 4),
            const Icon(Icons.chevron_right, color: Colors.grey, size: 18),
          ],
        ),
      ),
    );
  }
}
