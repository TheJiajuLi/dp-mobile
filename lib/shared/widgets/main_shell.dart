import 'dart:convert';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/utils/responsive.dart';
import '../../core/widgets/founding_badge.dart';
import '../../features/auth/auth_service.dart';
import '../../features/messages/providers/messages_provider.dart';
import '../../l10n/generated/app_localizations.dart';
import '../models/user_model.dart';

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
          // 直接读 scaffoldBackgroundColor（会被 AnimatedTheme 平滑插值），
          // 跟页面主体用同一个源、同一条动画曲线，切主题时底部栏边缘不再
          // "慢半拍"snap。稳态值跟原来完全一致：浅色 #F7F7FB / 深色 #1C1C1E
          color: Theme.of(context).scaffoldBackgroundColor,
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
                  // 首页跟发现合并成一个页面（发现的板块搬到首页顶部），
                  // 这个tab的图标/文案换成原来发现tab的，不再单独占一个tab
                  _NavItem(
                    icon: Icons.explore_outlined,
                    activeIcon: Icons.explore,
                    label: l10n.navCommunity,
                    selected: navigationShell.currentIndex == 0,
                    onTap: () => _onTap(0),
                  ),
                  // 极索——替代原来发现tab的位置，小梦AI入口+应用宫格+
                  // 社区精选
                  _NavItem(
                    iconBuilder: (selected) =>
                        _JisuoIcon(selected: selected),
                    label: '极索',
                    selected: navigationShell.currentIndex == 1,
                    onTap: () => _onTap(1),
                  ),
                  _PublishButton(
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
                        onTap: () => _onTap(2),
                      );
                    },
                  ),
                  _NavItem(
                    icon: Icons.person_outline,
                    activeIcon: Icons.person,
                    label: l10n.navProfile,
                    selected: navigationShell.currentIndex == 3,
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

  // 只带图标的窄栏——发现/消息 用 goBranch，Notebook/发布/设置是真实
  // push 路由，收藏还没有真实页面（跟 settings_screen.dart 里的处理一样，
  // 先占位跳个人主页，等 /saved 真的做出来了改这一个 onTap 就行）
  Widget _buildRail(
    BuildContext context,
    WidgetRef ref,
    AppLocalizations l10n,
    bool isDark,
  ) {
    final unread = ref.watch(unreadCountProvider);
    final user = ref.watch(currentUserProvider);
    final currentPath = GoRouterState.of(context).uri.path;

    return Container(
      width: 76,
      color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
      child: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 14),
            GestureDetector(
              onTap: () => _onTap(0),
              child: Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: const Color(0xFF6366F1).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
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
            ),
            const SizedBox(height: 14),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                children: [
                  // 首页/发现合并了，顶部"极"logo按钮点了就是_onTap(0)，
                  // 这里不需要再单独放一个发现图标
                  _railIcon(
                    tooltip: '极索',
                    icon: Icons.travel_explore_outlined,
                    activeIcon: Icons.travel_explore,
                    isActive: navigationShell.currentIndex == 1,
                    isDark: isDark,
                    onTap: () => _onTap(1),
                  ),
                  const SizedBox(height: 6),
                  _railIcon(
                    tooltip: 'Notebook',
                    icon: Icons.menu_book_outlined,
                    activeIcon: Icons.menu_book,
                    isActive: currentPath.startsWith('/notebook'),
                    isDark: isDark,
                    onTap: () => context.push('/notebook'),
                  ),
                  const SizedBox(height: 6),
                  _railIcon(
                    tooltip: l10n.messagesTitle,
                    icon: Icons.chat_bubble_outline,
                    activeIcon: Icons.chat_bubble,
                    isActive: navigationShell.currentIndex == 2,
                    isDark: isDark,
                    showDot: unread > 0,
                    onTap: () => _onTap(2),
                  ),
                  const SizedBox(height: 10),
                  Divider(
                    height: 0.5,
                    thickness: 0.5,
                    color: Theme.of(context).dividerColor,
                  ),
                  const SizedBox(height: 10),
                  _railIcon(
                    tooltip: l10n.publish,
                    icon: Icons.edit_outlined,
                    activeIcon: Icons.edit,
                    isActive: false,
                    isDark: isDark,
                    onTap: () => context.push('/publish'),
                  ),
                  const SizedBox(height: 6),
                  _railIcon(
                    tooltip: l10n.tabBookmarksLabel,
                    icon: Icons.bookmark_border,
                    activeIcon: Icons.bookmark,
                    isActive: false,
                    isDark: isDark,
                    onTap: () => context.push('/profile'),
                  ),
                  const SizedBox(height: 6),
                  _railIcon(
                    tooltip: l10n.settingsTitle,
                    icon: Icons.settings_outlined,
                    activeIcon: Icons.settings,
                    isActive: currentPath.startsWith('/settings'),
                    isDark: isDark,
                    onTap: () => context.push('/settings'),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: Tooltip(
                message: user?.username ?? '',
                child: GestureDetector(
                  onTap: () => _onTap(3),
                  child: _railAvatar(user),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _railIcon({
    required String tooltip,
    required IconData icon,
    required IconData activeIcon,
    required bool isActive,
    required bool isDark,
    required VoidCallback onTap,
    bool showDot = false,
  }) {
    final inactiveColor = isDark ? Colors.white38 : const Color(0xFF999999);
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: isActive
                ? (isDark ? Colors.white.withValues(alpha: 0.1) : Colors.white)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
            border: isActive
                ? Border.all(color: const Color(0xFFE5E5EA), width: 0.5)
                : null,
          ),
          child: Stack(
            alignment: Alignment.center,
            children: [
              Icon(
                isActive ? activeIcon : icon,
                size: 20,
                color: isActive
                    ? (isDark ? Colors.white : const Color(0xFF1A1A1A))
                    : inactiveColor,
              ),
              if (showDot)
                Positioned(
                  top: 9,
                  right: 10,
                  child: Container(
                    width: 7,
                    height: 7,
                    decoration: const BoxDecoration(
                      color: Color(0xFF3B82F6),
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  // 头像格式跟全项目其它渲染头像的地方保持一致：data:image 是旧的
  // base64 头像，否则是 COS 图片 URL——元老创作者外面套一圈已有的
  // FoundingAvatarRing
  Widget _railAvatar(UserModel? user) {
    final avatar = user?.avatar;
    Widget circle;
    if (avatar != null && avatar.isNotEmpty) {
      if (avatar.startsWith('data:image')) {
        try {
          circle = CircleAvatar(
            radius: 15,
            backgroundImage: MemoryImage(base64Decode(avatar.split(',').last)),
          );
        } catch (_) {
          circle = _railAvatarFallback(user);
        }
      } else {
        circle = CircleAvatar(
          radius: 15,
          backgroundColor: const Color(0xFF6366F1),
          backgroundImage: CachedNetworkImageProvider(avatar),
        );
      }
    } else {
      circle = _railAvatarFallback(user);
    }
    return FoundingAvatarRing(
      isFoundingCreator: user?.isFoundingCreator == true,
      size: 30,
      child: circle,
    );
  }

  Widget _railAvatarFallback(UserModel? user) => CircleAvatar(
    radius: 15,
    backgroundColor: const Color(0xFF6366F1),
    child: Text(
      (user?.username.isNotEmpty ?? false)
          ? user!.username.substring(0, 1).toUpperCase()
          : '?',
      style: const TextStyle(fontSize: 12, color: Colors.white),
    ),
  );
}

class _NavItem extends StatelessWidget {
  final IconData? icon;
  final IconData? activeIcon;
  // 极索tab用CustomPainter画的极光+放大镜图标，不是IconData——给个可选
  // 的widget构造器覆盖默认的Icon()，其它tab不传就还是走IconData那条路
  final Widget Function(bool selected)? iconBuilder;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final int badgeCount;

  const _NavItem({
    this.icon,
    this.activeIcon,
    this.iconBuilder,
    required this.label,
    required this.selected,
    required this.onTap,
    this.badgeCount = 0,
  });

  @override
  Widget build(BuildContext context) {
    // 从 ColorScheme 取色而不是用 isDark 二选一硬编码——onSurface 会被
    // AnimatedTheme 平滑插值（浅色≈近黑 / 深色≈近白），切主题时图标文字
    // 跟着一起渐变，不再在动画中点突然翻转
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final color = selected ? onSurface : onSurface.withValues(alpha: 0.45);
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
              child: iconBuilder != null
                  ? iconBuilder!(selected)
                  : Icon(
                      selected ? activeIcon : icon,
                      color: color,
                      size: 24,
                    ),
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
  const _PublishButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    // 之前用 ColorScheme.primary——M3 的 fromSeed 在深色模式下会把
    // primary 自动调成一个更浅/更淡的色调（为了跟深色背景保持对比度），
    // 不是品牌那个饱和的靛蓝，深色模式下这个按钮会变成一块发白的淡紫，
    // 跟全项目其它地方（都是直接写死 #6366F1）不一致，切到深色主题时
    // 显得像个 bug。改成跟全项目统一的写死品牌色，不再依赖 M3 自动生成
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: const Color(0xFF6366F1),
          borderRadius: BorderRadius.circular(14),
        ),
        child: const Icon(Icons.add, color: Colors.white, size: 24),
      ),
    );
  }
}

// 极索tab的图标——极光弧线+放大镜，跟JimengLogo的弧线画法是同一套
// 配色语义，CustomPainter画，不用图片资源
class _JisuoIcon extends StatelessWidget {
  final bool selected;
  const _JisuoIcon({required this.selected});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: const Size(24, 22),
      painter: _JisuoIconPainter(selected: selected),
    );
  }
}

class _JisuoIconPainter extends CustomPainter {
  final bool selected;
  const _JisuoIconPainter({required this.selected});

  @override
  void paint(Canvas canvas, Size size) {
    final colors = selected
        ? [
            const Color(0xFF6366F1).withValues(alpha: 0.5),
            const Color(0xFF818CF8).withValues(alpha: 0.8),
            const Color(0xFF4ADE80),
          ]
        : [
            Colors.grey.withValues(alpha: 0.4),
            Colors.grey.withValues(alpha: 0.6),
            Colors.grey.withValues(alpha: 0.8),
          ];

    final offsets = [0.0, 0.08, 0.16];
    for (var i = 0; i < 3; i++) {
      final paint = Paint()
        ..color = colors[i]
        ..strokeWidth = 2.2
        ..strokeCap = StrokeCap.round
        ..style = PaintingStyle.stroke;
      final path = Path();
      final y = size.height * (0.65 + offsets[i]);
      path.moveTo(0, y);
      path.quadraticBezierTo(
        size.width * 0.5,
        size.height * (0.05 + offsets[i] * 0.5),
        size.width,
        y,
      );
      canvas.drawPath(path, paint);
    }

    final mgPaint = Paint()
      ..color = selected ? const Color(0xFF6366F1) : Colors.grey
      ..strokeWidth = 1.8
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    canvas.drawCircle(
      Offset(size.width * 0.65, size.height * 0.38),
      size.width * 0.18,
      mgPaint,
    );
    canvas.drawLine(
      Offset(size.width * 0.78, size.height * 0.5),
      Offset(size.width * 0.92, size.height * 0.64),
      mgPaint,
    );

    if (selected) {
      canvas.drawCircle(
        Offset(size.width * 0.65, size.height * 0.38),
        size.width * 0.07,
        Paint()..color = const Color(0xFF4ADE80),
      );
    }
  }

  @override
  bool shouldRepaint(_JisuoIconPainter oldDelegate) =>
      oldDelegate.selected != selected;
}
