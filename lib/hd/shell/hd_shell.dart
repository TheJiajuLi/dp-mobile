import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'hd_icon_rail.dart';

// HD 外壳：左侧 64px 图标栏（全局常驻）+ 分割线 + 当前分支内容区。分支切换、
// 状态保活由 go_router 的 StatefulShellRoute.indexedStack 负责（见 hd_router），
// 这里只负责摆布局。每个分支自己的内部布局（首页的 list+reader+toc、小梦的
// 对话整块等）由各分支页决定，不在这里管
class HdShell extends StatelessWidget {
  final StatefulNavigationShell navigationShell;
  const HdShell({super.key, required this.navigationShell});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: isDark
          ? Theme.of(context).scaffoldBackgroundColor
          : const Color(0xFFFAFAF8),
      body: SafeArea(
        child: Row(
          children: [
            HdIconRail(navigationShell: navigationShell),
            VerticalDivider(
              width: 0.5,
              thickness: 0.5,
              color: isDark
                  ? Colors.white.withValues(alpha: 0.08)
                  : const Color(0xFFE5E5EA),
            ),
            Expanded(child: navigationShell),
          ],
        ),
      ),
    );
  }
}
