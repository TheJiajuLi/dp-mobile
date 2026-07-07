import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/auth/auth_service.dart';
import 'hd_shell.dart';

class HdRail extends ConsumerWidget {
  final HdPage currentPage;
  final void Function(HdPage) onNavTap;

  const HdRail({super.key, required this.currentPage, required this.onNavTap});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);

    return Container(
      width: 220,
      color: const Color(0xFFF0F0F0),
      child: Column(
        children: [
          // Logo区
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 16, 14, 12),
            child: Row(
              children: [
                Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    color: const Color(0xFFEEF0FF),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Center(
                    child: Text(
                      '极',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF6366F1),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                const Text(
                  '极梦',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF1A1A1A),
                  ),
                ),
              ],
            ),
          ),

          const Divider(height: 0.5, thickness: 0.5, color: Color(0xFFE5E5EA)),

          // 导航项
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              children: [
                _navItem(
                  page: HdPage.discover,
                  icon: Icons.explore_outlined,
                  activeIcon: Icons.explore,
                  label: '发现',
                ),
                _navItem(
                  page: HdPage.messages,
                  icon: Icons.message_outlined,
                  activeIcon: Icons.message,
                  label: '消息',
                ),
                const SizedBox(height: 4),
                const Divider(
                  height: 0.5,
                  thickness: 0.5,
                  color: Color(0xFFE5E5EA),
                ),
                const SizedBox(height: 4),
                // 发布——暂时没有对应的 HdPage，先空着 onTap，接真实发布流程
                // 时再补
                _navItem(
                  icon: Icons.add_circle_outline,
                  activeIcon: Icons.add_circle,
                  label: '发布',
                  onTap: () {},
                ),
                const SizedBox(height: 4),
                const Divider(
                  height: 0.5,
                  thickness: 0.5,
                  color: Color(0xFFE5E5EA),
                ),
                const SizedBox(height: 4),
                _navItem(
                  page: HdPage.profile,
                  icon: Icons.person_outline,
                  activeIcon: Icons.person,
                  label: '我的',
                ),
                _navItem(
                  page: HdPage.settings,
                  icon: Icons.settings_outlined,
                  activeIcon: Icons.settings,
                  label: '设置',
                ),
              ],
            ),
          ),

          // 用户信息
          const Divider(height: 0.5, thickness: 0.5, color: Color(0xFFE5E5EA)),
          GestureDetector(
            onTap: () => onNavTap(HdPage.profile),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 15,
                    backgroundColor: const Color(0xFF6366F1),
                    child: Text(
                      (user?.username.isNotEmpty ?? false)
                          ? user!.username.substring(0, 1).toUpperCase()
                          : 'U',
                      style: const TextStyle(fontSize: 11, color: Colors.white),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          user?.username ?? '',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: Color(0xFF1A1A1A),
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (user?.isFoundingCreator == true)
                          const Text(
                            '★ 元老创作者',
                            style: TextStyle(
                              fontSize: 9,
                              color: Color(0xFFF59E0B),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // page 传了就是真实的 goBranch 式导航项，选中态跟 currentPage 联动；
  // 不传 page（比如发布，暂时没有对应的 HdPage）就必须传 onTap 自己接管
  // 点击行为，永远不显示选中态
  Widget _navItem({
    HdPage? page,
    required IconData icon,
    required IconData activeIcon,
    required String label,
    VoidCallback? onTap,
  }) {
    assert(page != null || onTap != null);
    final isActive = page != null && currentPage == page;
    return GestureDetector(
      onTap: onTap ?? () => onNavTap(page!),
      child: Container(
        margin: const EdgeInsets.only(bottom: 2),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: isActive ? Colors.white : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: isActive
              ? Border.all(color: const Color(0xFFE5E5EA), width: 0.5)
              : null,
        ),
        child: Row(
          children: [
            Icon(
              isActive ? activeIcon : icon,
              size: 18,
              color: isActive
                  ? const Color(0xFF1A1A1A)
                  : const Color(0xFF888888),
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: isActive ? FontWeight.w500 : FontWeight.w400,
                color: isActive
                    ? const Color(0xFF1A1A1A)
                    : const Color(0xFF888888),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
