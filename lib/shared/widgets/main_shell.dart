import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/responsive.dart';
import '../../features/messages/providers/messages_provider.dart';
import '../../l10n/generated/app_localizations.dart';

class MainShell extends ConsumerWidget {
  final StatefulNavigationShell navigationShell;

  const MainShell({super.key, required this.navigationShell});

  void _onTap(int index) {
    navigationShell.goBranch(
      index,
      initialLocation: index == navigationShell.currentIndex,
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    // 底部导航条之前固定白底——大部分页面本来就是浅色主题，看不出问题，
    // 但深色主题的页面（比如个人主页下半部）滚到底就会露出这一整条刺眼的
    // 白色，2026-07-06 起跟着 Theme.of(context).brightness 走。浅色底同一天
    // 又从纯白 #FFFFFF 改成 AppColors.bg（#F7F7FB，主题默认
    // scaffoldBackgroundColor）——纯白跟首页/发现页/消息页/个人主页实际的
    // 浅灰白背景不是同一个值，两者拼在一起会露出一条很淡但看得出来的接缝
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // iPad（宽度>=600）改成左侧竖排导航栏——iPhone 底部导航完全不动。这是
    // 重新搭的精简版：4个真实目的地 + 发布，跟手机底部 Tab 完全对应，
    // 不是之前那套被 git reset 弄丢的、后来越叠越复杂的版本；后续要加
    // 分组/Notebook 入口等，等真的有对应页面了再加，避免又堆出一堆点了
    // 没反应的占位项
    if (Responsive.isTablet(context)) {
      return Scaffold(
        backgroundColor: isDark
            ? Theme.of(context).scaffoldBackgroundColor
            : const Color(0xFFF5F5F7),
        body: Row(
          children: [
            _buildRail(context, ref, l10n, isDark),
            VerticalDivider(
              width: 0.5,
              thickness: 0.5,
              color: Theme.of(context).dividerColor,
            ),
            Expanded(child: navigationShell),
          ],
        ),
      );
    }

    return Scaffold(
      body: navigationShell,
      bottomNavigationBar: DecoratedBox(
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1C1C1E) : AppColors.bg,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          // 深色模式底部bar跟页面内容看起来是"一体的"（没有阴影），浅色
          // 模式之前留了一圈阴影，页面内容和底部bar之间露出一条看得出来的
          // 接缝，两种模式观感不一致——去掉阴影，浅色模式也跟深色模式一样
          // 融为一体
        ),
        child: ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          child: SafeArea(
            top: false,
            child: SizedBox(
              height: 60,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _NavItem(
                    icon: Icons.home_outlined,
                    activeIcon: Icons.home,
                    label: l10n.navHome,
                    selected: navigationShell.currentIndex == 0,
                    isDark: isDark,
                    onTap: () => _onTap(0),
                  ),
                  _NavItem(
                    icon: Icons.explore_outlined,
                    activeIcon: Icons.explore,
                    label: l10n.navCommunity,
                    selected: navigationShell.currentIndex == 1,
                    isDark: isDark,
                    onTap: () => _onTap(1),
                  ),
                  _PublishButton(
                    isDark: isDark,
                    onTap: () => context.push('/publish'),
                  ),
                  Consumer(
                    builder: (context, ref, _) {
                      final unread = ref.watch(unreadCountProvider);
                      return _NavItem(
                        icon: Icons.chat_bubble_outline,
                        activeIcon: Icons.chat_bubble,
                        label: l10n.messagesTitle,
                        selected: navigationShell.currentIndex == 2,
                        badgeCount: unread,
                        isDark: isDark,
                        onTap: () => _onTap(2),
                      );
                    },
                  ),
                  _NavItem(
                    icon: Icons.person_outline,
                    activeIcon: Icons.person,
                    label: l10n.navProfile,
                    selected: navigationShell.currentIndex == 3,
                    isDark: isDark,
                    onTap: () => _onTap(3),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildRail(
    BuildContext context,
    WidgetRef ref,
    AppLocalizations l10n,
    bool isDark,
  ) {
    final unread = ref.watch(unreadCountProvider);
    return Container(
      width: 220,
      color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 12, 12),
            child: Row(
              children: [
                Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    color: const Color(0xFF6366F1).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Center(
                    child: Text(
                      '极',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF6366F1),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  l10n.appName,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: isDark ? Colors.white : const Color(0xFF1A1A1A),
                  ),
                ),
              ],
            ),
          ),
          Divider(
            height: 0.5,
            thickness: 0.5,
            color: Theme.of(context).dividerColor,
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              children: [
                _railItem(
                  context,
                  icon: Icons.home_outlined,
                  activeIcon: Icons.home,
                  label: l10n.navHome,
                  isActive: navigationShell.currentIndex == 0,
                  isDark: isDark,
                  onTap: () => _onTap(0),
                ),
                _railItem(
                  context,
                  icon: Icons.explore_outlined,
                  activeIcon: Icons.explore,
                  label: l10n.navCommunity,
                  isActive: navigationShell.currentIndex == 1,
                  isDark: isDark,
                  onTap: () => _onTap(1),
                ),
                _railItem(
                  context,
                  icon: Icons.chat_bubble_outline,
                  activeIcon: Icons.chat_bubble,
                  label: l10n.messagesTitle,
                  isActive: navigationShell.currentIndex == 2,
                  isDark: isDark,
                  badgeCount: unread,
                  onTap: () => _onTap(2),
                ),
                _railItem(
                  context,
                  icon: Icons.person_outline,
                  activeIcon: Icons.person,
                  label: l10n.navProfile,
                  isActive: navigationShell.currentIndex == 3,
                  isDark: isDark,
                  onTap: () => _onTap(3),
                ),
                const SizedBox(height: 8),
                Divider(
                  height: 0.5,
                  thickness: 0.5,
                  color: Theme.of(context).dividerColor,
                ),
                const SizedBox(height: 8),
                GestureDetector(
                  onTap: () => context.push('/publish'),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    decoration: BoxDecoration(
                      color: isDark
                          ? const Color(0xFF6366F1)
                          : const Color(0xFF1A1A1A),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.add, color: Colors.white, size: 16),
                        const SizedBox(width: 5),
                        Text(
                          l10n.publish,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _railItem(
    BuildContext context, {
    required IconData icon,
    required IconData activeIcon,
    required String label,
    required bool isActive,
    required bool isDark,
    required VoidCallback onTap,
    int badgeCount = 0,
  }) {
    final activeColor = isDark ? Colors.white : const Color(0xFF1A1A1A);
    final inactiveColor = isDark ? Colors.white38 : const Color(0xFF999999);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 2),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
        decoration: BoxDecoration(
          color: isActive
              ? const Color(0xFF6366F1).withValues(alpha: isDark ? 0.2 : 0.1)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            Badge(
              isLabelVisible: badgeCount > 0,
              label: Text(badgeCount > 99 ? '99+' : '$badgeCount'),
              backgroundColor: Colors.red,
              child: Icon(
                isActive ? activeIcon : icon,
                size: 19,
                color: isActive ? activeColor : inactiveColor,
              ),
            ),
            const SizedBox(width: 10),
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
                color: isActive ? activeColor : inactiveColor,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  final IconData icon;
  final IconData activeIcon;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final int badgeCount;
  final bool isDark;

  const _NavItem({
    required this.icon,
    required this.activeIcon,
    required this.label,
    required this.selected,
    required this.onTap,
    required this.isDark,
    this.badgeCount = 0,
  });

  @override
  Widget build(BuildContext context) {
    final color = isDark
        ? (selected ? Colors.white : Colors.white38)
        : (selected ? AppColors.textPrimary : AppColors.textMuted);
    return InkWell(
      onTap: onTap,
      customBorder: const CircleBorder(),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Badge(
              isLabelVisible: badgeCount > 0,
              label: Text(badgeCount > 99 ? '99+' : '$badgeCount'),
              backgroundColor: Colors.red,
              child: Icon(selected ? activeIcon : icon, color: color, size: 24),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 10,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PublishButton extends StatelessWidget {
  final VoidCallback onTap;
  final bool isDark;
  const _PublishButton({required this.onTap, required this.isDark});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          // 深色主题下导航条本身已经很暗，继续用近黑色块对比度太低，
          // 换成品牌紫；浅色主题维持原来的近黑色不变
          color: isDark ? const Color(0xFF6366F1) : AppColors.textPrimary,
          borderRadius: BorderRadius.circular(14),
        ),
        child: const Icon(Icons.add, color: Colors.white, size: 24),
      ),
    );
  }
}
