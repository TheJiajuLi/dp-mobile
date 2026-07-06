import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme/app_theme.dart';
import '../../features/messages/providers/messages_provider.dart';
import '../../l10n/generated/app_localizations.dart';

class MainShell extends StatelessWidget {
  final StatefulNavigationShell navigationShell;

  const MainShell({super.key, required this.navigationShell});

  void _onTap(int index) {
    navigationShell.goBranch(
      index,
      initialLocation: index == navigationShell.currentIndex,
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    // 底部导航条之前固定白底——大部分页面本来就是浅色主题，看不出问题，
    // 但深色主题的页面（比如个人主页下半部）滚到底就会露出这一整条刺眼的
    // 白色，2026-07-06 起跟着 Theme.of(context).brightness 走。浅色底同一天
    // 又从纯白 #FFFFFF 改成 AppColors.bg（#F7F7FB，主题默认
    // scaffoldBackgroundColor）——纯白跟首页/发现页/消息页/个人主页实际的
    // 浅灰白背景不是同一个值，两者拼在一起会露出一条很淡但看得出来的接缝
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      body: navigationShell,
      bottomNavigationBar: DecoratedBox(
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1C1C1E) : AppColors.bg,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          boxShadow: isDark
              ? null
              : const [
                  BoxShadow(
                    color: Color(0x14000000),
                    blurRadius: 16,
                    offset: Offset(0, -2),
                  ),
                ],
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
