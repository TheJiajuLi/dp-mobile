import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';

// 设置页开关统一走极梦品牌紫：开启态紫轨道 + 白拨钮，跟创作者设置页
// 那套一致，整体视感更精神（原来的黑白 mono 配色偏冷、偏功能性）。
// 拨钮恒用白色——紫轨道在浅色/深色卡片上都够显眼，不用再像旧版那样
// 按主题给轨道反色；trackOutlineColor 透明去掉 M3 默认的描边圈
({Color thumb, Color track, WidgetStateProperty<Color?> outline})
brandSwitchColors() {
  return (
    thumb: Colors.white,
    track: AppColors.primary,
    outline: const WidgetStatePropertyAll(Colors.transparent),
  );
}

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
          // 组里的行大多是 ListTile（onTap 触发点击反馈）——ListTile 的
          // InkWell 水波纹需要一个 Material 祖先才能正确画/裁切，之前
          // 直接吃外层 Scaffold 的默认 Material，水波纹动画在圆角边界
          // 附近可能不走这一层 ClipRRect 的裁切，最后一行贴着圆角的
          // 那个角就会露出方形边缘。显式包一层透明 Material，水波纹
          // 保证跟着这个 ClipRRect 一起裁
          child: Material(
            color: Colors.transparent,
            child: Column(children: rows),
          ),
        ),
      ),
    );
  }
}

// 带图标方块的开关行——跟 SettingsRow 同一套"圆框设计"（34方块+圆角图标
// +标题/副标题），只是右侧把 chevron 换成开关。隐私设置/通知设置这类
// 纯开关页之前是光秃秃的 SwitchListTile（没有图标方块），跟设置主页/
// 账号安全那套带图标方块的视觉语言对不上，用这个统一起来
class SettingsSwitchRow extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final Color iconBg;
  final String title;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  const SettingsSwitchRow({
    super.key,
    required this.icon,
    required this.iconColor,
    required this.iconBg,
    required this.title,
    this.subtitle,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final colors = brandSwitchColors();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
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
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle!,
                    style: const TextStyle(
                      fontSize: 12,
                      color: Colors.grey,
                      height: 1.4,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          Switch(
            value: value,
            onChanged: onChanged,
            activeThumbColor: colors.thumb,
            activeTrackColor: colors.track,
            trackOutlineColor: colors.outline,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
        ],
      ),
    );
  }
}

class SettingsRow extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final Color iconBg;
  final String title;
  // 标题色——默认跟随主题正文色，危险操作（如注销账号）传红色做强调
  final Color? titleColor;
  final String? subtitle;
  final String? trailing;
  // trailing 文字颜色——默认跟原来一样是灰色（字号/日期这类中性信息），
  // "有新内容"这类需要吸引注意力的 trailing 可以传品牌色
  final Color? trailingColor;
  final VoidCallback onTap;

  const SettingsRow({
    super.key,
    required this.icon,
    required this.iconColor,
    required this.iconBg,
    required this.title,
    this.titleColor,
    this.subtitle,
    this.trailing,
    this.trailingColor,
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
                      color:
                          titleColor ??
                          Theme.of(context).textTheme.bodyLarge?.color,
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
                style: TextStyle(
                  fontSize: 14,
                  color: trailingColor ?? Colors.grey,
                ),
              ),
            const SizedBox(width: 4),
            const Icon(Icons.chevron_right, color: Colors.grey, size: 18),
          ],
        ),
      ),
    );
  }
}
