import 'package:flutter/material.dart';

import 'hd_shell.dart';

// 跟参考模板对齐——Notebook/创作中心/作品管理/收藏/快捷键这几项目前没有
// 对应的 HdPage，先只做视觉布局（onTap 空着），跟"发布"是同一个处理
// 方式。用户信息也改成跟 hd_profile_page.dart 一致的固定占位数据，不再
// 接 currentUserProvider——沙盒没有真实登录态，接了也只会显示空
class HdRail extends StatelessWidget {
  final HdPage currentPage;
  final void Function(HdPage) onNavTap;

  const HdRail({super.key, required this.currentPage, required this.onNavTap});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 232,
      color: const Color(0xFFF7F7F7),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Logo区
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 16, 10, 12),
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
                const Expanded(
                  child: Text(
                    '极梦',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF1A1A1A),
                    ),
                  ),
                ),
                const Icon(
                  Icons.view_sidebar_outlined,
                  size: 18,
                  color: Color(0xFF999999),
                ),
              ],
            ),
          ),

          const Divider(height: 0.5, thickness: 0.5, color: Color(0xFFE5E5EA)),

          // 导航项
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              children: [
                _navItem(
                  page: HdPage.discover,
                  icon: Icons.explore_outlined,
                  activeIcon: Icons.explore,
                  label: '发现',
                ),
                _navItem(
                  icon: Icons.menu_book_outlined,
                  activeIcon: Icons.menu_book,
                  label: 'Notebook',
                  onTap: () {},
                ),
                _navItem(
                  page: HdPage.messages,
                  icon: Icons.chat_bubble_outline,
                  activeIcon: Icons.chat_bubble,
                  label: '消息',
                  badge: '3',
                ),
                _sectionLabel('创作'),
                _navItem(
                  icon: Icons.edit_outlined,
                  activeIcon: Icons.edit,
                  label: '发布',
                  onTap: () {},
                ),
                _navItem(
                  icon: Icons.bar_chart_outlined,
                  activeIcon: Icons.bar_chart,
                  label: '创作中心',
                  onTap: () {},
                ),
                _navItem(
                  icon: Icons.list_alt_outlined,
                  activeIcon: Icons.list_alt,
                  label: '作品管理',
                  onTap: () {},
                ),
                _sectionLabel('其他'),
                _navItem(
                  icon: Icons.bookmark_border,
                  activeIcon: Icons.bookmark,
                  label: '收藏',
                  onTap: () {},
                ),
                _navItem(
                  icon: Icons.keyboard_outlined,
                  activeIcon: Icons.keyboard,
                  label: '快捷键',
                  onTap: () {},
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

          // 用户信息——固定占位数据，跟 hd_profile_page.dart 保持一致
          const Divider(height: 0.5, thickness: 0.5, color: Color(0xFFE5E5EA)),
          GestureDetector(
            onTap: () => onNavTap(HdPage.profile),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Container(
                    width: 30,
                    height: 30,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(
                        colors: [
                          Color(0xFFF59E0B),
                          Color(0xFF818CF8),
                          Color(0xFF4ADE80),
                        ],
                      ),
                    ),
                    padding: const EdgeInsets.all(2),
                    child: Container(
                      decoration: const BoxDecoration(
                        color: Color(0xFF6366F1),
                        shape: BoxShape.circle,
                      ),
                      child: const Center(
                        child: Text(
                          '兔',
                          style: TextStyle(fontSize: 12, color: Colors.white),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '大兔兔',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: Color(0xFF1A1A1A),
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
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

  Widget _sectionLabel(String label) => Padding(
    padding: const EdgeInsets.fromLTRB(10, 12, 10, 4),
    child: Text(
      label,
      style: const TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w600,
        color: Color(0xFF9A9A9A),
        letterSpacing: 0.4,
      ),
    ),
  );

  // page 传了就是真实的 goBranch 式导航项，选中态跟 currentPage 联动；
  // 不传 page（Notebook/发布/创作中心/作品管理/收藏/快捷键，暂时没有对应
  // 的 HdPage）就必须传 onTap 自己接管点击行为，永远不显示选中态
  Widget _navItem({
    HdPage? page,
    required IconData icon,
    required IconData activeIcon,
    required String label,
    VoidCallback? onTap,
    String? badge,
  }) {
    assert(page != null || onTap != null);
    final isActive = page != null && currentPage == page;
    return GestureDetector(
      onTap: onTap ?? () => onNavTap(page!),
      child: Container(
        margin: const EdgeInsets.only(bottom: 2),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
        decoration: BoxDecoration(
          color: isActive
              ? const Color(0xFF6366F1).withValues(alpha: 0.1)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
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
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
                  color: isActive
                      ? const Color(0xFF1A1A1A)
                      : const Color(0xFF888888),
                ),
              ),
            ),
            if (badge != null)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFF6366F1),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  badge,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
