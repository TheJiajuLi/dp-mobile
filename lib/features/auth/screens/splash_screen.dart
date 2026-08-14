import 'dart:async';
import '../../../core/theme/app_colors.dart';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../l10n/generated/app_localizations.dart';
import '../../../shared/widgets/jimeng_logo.dart';
import '../auth_service.dart';

class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen>
    with SingleTickerProviderStateMixin {
  static const _entranceDuration = Duration(milliseconds: 1100);
  // 停留时长比动画本身长——真实的登录态校验（tryAutoLogin/silentRefresh）
  // 走网络，可能比动画快很多，卡这个最短时长才能保证入场动画/slogan
  // 轮播能完整播完，不会一闪而过
  static const _minVisibleDuration = Duration(milliseconds: 2800);

  late final AnimationController _entranceCtrl;
  late final Animation<double> _logoScale;
  late final Animation<double> _logoFade;
  late final Animation<double> _textFade;
  late final Animation<Offset> _textSlide;

  // 每次加载只随机选一条，不轮播——用可空字段 + didChangeDependencies
  // 里 ??= 赋值，保证语言/主题切换重建时不会重新随机
  String? _slogan;

  @override
  void initState() {
    super.initState();
    _entranceCtrl = AnimationController(
      vsync: this,
      duration: _entranceDuration,
    );
    _logoScale = Tween<double>(begin: 0.5, end: 1.0).animate(
      CurvedAnimation(
        parent: _entranceCtrl,
        curve: const Interval(0.09, 0.91, curve: Curves.elasticOut),
      ),
    );
    _logoFade = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(
        parent: _entranceCtrl,
        curve: const Interval(0.09, 0.91, curve: Curves.easeOut),
      ),
    );
    _textFade = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(
        parent: _entranceCtrl,
        curve: const Interval(0.23, 0.96, curve: Curves.easeOut),
      ),
    );
    _textSlide = Tween<Offset>(
      begin: const Offset(0, 0.3),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(
        parent: _entranceCtrl,
        curve: const Interval(0.23, 0.96, curve: Curves.easeOut),
      ),
    );
    _entranceCtrl.forward();

    _navigateAfterReady();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final l10n = AppLocalizations.of(context)!;
    _slogan ??=
        [l10n.appSlogan, l10n.slogan2, l10n.slogan3][Random().nextInt(3)];
  }

  Future<void> _navigateAfterReady() async {
    final authService = ref.read(authServiceProvider);
    final authFuture = _checkAuth(authService);
    await Future.delayed(_minVisibleDuration);
    final loggedIn = await authFuture;
    if (!mounted) return;
    context.go(loggedIn ? '/home' : '/login');
  }

  // 跟原来 SplashScreen 的恢复登录逻辑完全一样：先用本地 token 试
  // tryAutoLogin，失败大概率是 access token 过期（15分钟有效期），用
  // refresh token 换新的再试一次——这里只是套了层最短可见时长，登录态
  // 校验本身的逻辑一点没变
  Future<bool> _checkAuth(AuthService authService) async {
    final loggedIn = await authService.tryAutoLogin();
    if (!mounted) return loggedIn;
    if (loggedIn) {
      unawaited(authService.silentRefresh());
      return true;
    }
    final refreshed = await authService.silentRefresh();
    if (!mounted) return false;
    if (refreshed) {
      return authService.tryAutoLogin();
    }
    return false;
  }

  @override
  void dispose() {
    _entranceCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? const Color(0xFF0D0B1A) : const Color(0xFFFAFAF8);
    final textColor = isDark ? Colors.white : const Color(0xFF1A1A1A);
    final sloganColor = isDark
        ? const Color(0x73FFFFFF)
        : const Color(0xFF888888);
    final dotColor = isDark ? const Color(0x33FFFFFF) : AppColors.primary;
    final versionColor = isDark
        ? const Color(0x33FFFFFF)
        : const Color(0xFFCCCCCC);

    return Scaffold(
      backgroundColor: bg,
      body: Stack(
        children: [
          Positioned.fill(
            child: IgnorePointer(child: _SplashGlowLayer(isDark: isDark)),
          ),
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ScaleTransition(
                  scale: _logoScale,
                  child: FadeTransition(
                    opacity: _logoFade,
                    child: const JimengLogo(size: 90),
                  ),
                ),
                const SizedBox(height: 20),
                FadeTransition(
                  opacity: _textFade,
                  child: SlideTransition(
                    position: _textSlide,
                    child: Column(
                      children: [
                        Text(
                          l10n.appName,
                          style: TextStyle(
                            fontSize: 38,
                            fontWeight: FontWeight.w800,
                            color: textColor,
                            letterSpacing: 3,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Dreaming Polar',
                          style: TextStyle(
                            fontSize: 13,
                            color: isDark
                                ? const Color(0x59FFFFFF)
                                : const Color(0xFFAAAAAA),
                            letterSpacing: 2.5,
                          ),
                        ),
                        const SizedBox(height: 14),
                        Text(
                          _slogan ?? l10n.appSlogan,
                          style: TextStyle(fontSize: 13, color: sloganColor),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 56,
            child: Column(
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: List.generate(
                    3,
                    (i) => Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 3),
                      child: _PulsingDot(
                        color: dotColor,
                        delay: Duration(milliseconds: i * 180),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'v1.0.0',
                  style: TextStyle(
                    fontSize: 11,
                    color: versionColor,
                    letterSpacing: 0.5,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SplashGlowLayer extends StatelessWidget {
  final bool isDark;

  const _SplashGlowLayer({required this.isDark});

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned(
          top: -80,
          left: -60,
          child: _blob(const Color(0xFF4A48B4), isDark ? 0.32 : 0.07),
        ),
        Positioned(
          top: -60,
          right: -80,
          child: _blob(AppColors.primary, isDark ? 0.18 : 0.05),
        ),
        if (isDark)
          Positioned(
            bottom: -120,
            left: 0,
            right: 0,
            child: Center(child: _blob(const Color(0xFF3B3680), 0.20)),
          ),
      ],
    );
  }

  Widget _blob(Color color, double opacity) => Container(
    width: 340,
    height: 340,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      gradient: RadialGradient(
        colors: [color.withValues(alpha: opacity), Colors.transparent],
      ),
    ),
  );
}

class _PulsingDot extends StatefulWidget {
  final Color color;
  final Duration delay;

  const _PulsingDot({required this.color, required this.delay});

  @override
  State<_PulsingDot> createState() => _PulsingDotState();
}

class _PulsingDotState extends State<_PulsingDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _opacity;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _opacity = Tween<double>(
      begin: 0.2,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));
    Future.delayed(widget.delay, () {
      if (mounted) _ctrl.repeat(reverse: true);
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _opacity,
      child: Container(
        width: 7,
        height: 7,
        decoration: BoxDecoration(color: widget.color, shape: BoxShape.circle),
      ),
    );
  }
}
