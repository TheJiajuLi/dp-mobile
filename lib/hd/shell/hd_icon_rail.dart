import 'dart:convert';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/auth_service.dart';

const _primary = Color(0xFF6366F1);

// HD 全局 64px 图标侧栏——顶部 5 个内容分支（首页/发现/极索/Notebook/小梦），
// 底部 3 个（通知/设置/头像）。全部对应 StatefulShellRoute 的 branch，点击走
// navigationShell.goBranch(index)，选中态跟 currentIndex 联动。头像接
// currentUserProvider 显示真实登录用户。branch 顺序必须跟 hd_router 里一致：
// 0 首页 1 发现 2 极索 3 Notebook 4 小梦 5 通知 6 设置 7 头像
class HdIconRail extends ConsumerWidget {
  final StatefulNavigationShell navigationShell;
  const HdIconRail({super.key, required this.navigationShell});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final railBg = isDark
        ? Theme.of(context).cardColor
        : const Color(0xFFFAFAF8);
    final user = ref.watch(currentUserProvider);
    final current = navigationShell.currentIndex;

    return Container(
      width: 64,
      color: railBg,
      child: Column(
        children: [
          const SizedBox(height: 12),
          // Logo
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: const Color(0xFFEEF0FF),
              borderRadius: BorderRadius.circular(9),
            ),
            child: const Center(
              child: Text(
                '极',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: _primary,
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),

          // 顶部 5 个内容分支
          _railBtn(current, 0, Icons.home_outlined, Icons.home, '首页', isDark),
          _railBtn(
            current,
            1,
            Icons.explore_outlined,
            Icons.explore,
            '发现',
            isDark,
          ),
          _railBtn(
            current,
            2,
            Icons.travel_explore_outlined,
            Icons.travel_explore,
            '极索',
            isDark,
          ),
          _railBtn(
            current,
            3,
            Icons.menu_book_outlined,
            Icons.menu_book,
            'Notebook',
            isDark,
          ),
          _railBtn(
            current,
            4,
            Icons.auto_awesome_outlined,
            Icons.auto_awesome,
            '小梦',
            isDark,
          ),

          const Spacer(),

          // 底部 3 个：通知 / 设置 / 头像
          _railBtn(
            current,
            5,
            Icons.notifications_outlined,
            Icons.notifications,
            '通知',
            isDark,
          ),
          _railBtn(
            current,
            6,
            Icons.settings_outlined,
            Icons.settings,
            '设置',
            isDark,
          ),
          _avatarBtn(current, 7, user, isDark),
          const SizedBox(height: 12),
        ],
      ),
    );
  }

  Widget _railBtn(
    int current,
    int index,
    IconData icon,
    IconData activeIcon,
    String label,
    bool isDark,
  ) {
    final active = current == index;
    final activeInk = isDark
        ? const Color(0xFFF0F2F8)
        : const Color(0xFF1A1A1A);
    final idleInk = isDark ? const Color(0xFF888C9E) : const Color(0xFF888888);
    return Tooltip(
      message: label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => navigationShell.goBranch(
          index,
          // 再点当前分支时回到该分支的初始路由（跟 MainShell 一致的语义）
          initialLocation: index == current,
        ),
        child: Container(
          width: 44,
          height: 44,
          margin: const EdgeInsets.symmetric(vertical: 4),
          decoration: BoxDecoration(
            color: active
                ? _primary.withValues(alpha: isDark ? 0.20 : 0.10)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(
            active ? activeIcon : icon,
            size: 21,
            color: active ? activeInk : idleInk,
          ),
        ),
      ),
    );
  }

  // 头像按钮——真实登录用户头像（data:image / 网络图 / 首字母兜底）
  Widget _avatarBtn(int current, int index, dynamic user, bool isDark) {
    final active = current == index;
    return Tooltip(
      message: '我的主页',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () =>
            navigationShell.goBranch(index, initialLocation: index == current),
        child: Container(
          width: 44,
          height: 44,
          margin: const EdgeInsets.symmetric(vertical: 4),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: active
                ? Border.all(color: _primary, width: 2)
                : Border.all(color: Colors.transparent, width: 2),
          ),
          child: Center(child: _avatar(user)),
        ),
      ),
    );
  }

  Widget _avatar(dynamic user) {
    final avatar = user?.avatar as String?;
    final username = (user?.username as String?) ?? '';
    const radius = 15.0;
    if (avatar != null && avatar.isNotEmpty) {
      if (avatar.startsWith('data:image')) {
        try {
          final raw = avatar.split(',').last;
          return CircleAvatar(
            radius: radius,
            backgroundImage: MemoryImage(base64Decode(raw)),
          );
        } catch (_) {
          // 落到首字母
        }
      } else {
        return CircleAvatar(
          radius: radius,
          backgroundColor: _primary,
          backgroundImage: CachedNetworkImageProvider(avatar),
        );
      }
    }
    return CircleAvatar(
      radius: radius,
      backgroundColor: _primary,
      child: Text(
        username.isEmpty ? '?' : username.substring(0, 1).toUpperCase(),
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w700,
          fontSize: 12,
        ),
      ),
    );
  }
}
