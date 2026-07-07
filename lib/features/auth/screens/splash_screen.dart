import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../auth_service.dart';

class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animCtrl;
  late final Animation<double> _fade;
  late final Animation<double> _scale;
  // 随机选一条 slogan，选完缓存住——用可空字段 + ??= 才安全：late
  // 非空字段在赋值前是"未初始化"状态，直接读取会抛
  // LateInitializationError，??= 得先读一次当前值才能判断要不要赋值，
  // 两者搭配必炸。didChangeDependencies 在主题/语言切换时会被再次调用，
  // 不加这层缓存每次都会重新随机，两条 slogan 来回跳
  String? _slogan;

  @override
  void initState() {
    super.initState();
    // Logo 一次性淡入+轻微放大的入场动画，不是循环动画——启动页停留时间
    // 通常很短（tryAutoLogin 一般几百毫秒就有结果），循环动画反而容易让
    // 这一闪而过的页面显得拖沓
    _animCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _fade = CurvedAnimation(parent: _animCtrl, curve: Curves.easeOut);
    _scale = Tween<double>(
      begin: 0.85,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _animCtrl, curve: Curves.easeOutBack));
    _animCtrl.forward();
    WidgetsBinding.instance.addPostFrameCallback((_) => _restore());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final l10n = AppLocalizations.of(context)!;
    _slogan ??= Random().nextBool() ? l10n.appSlogan : l10n.slogan2;
  }

  @override
  void dispose() {
    _animCtrl.dispose();
    super.dispose();
  }

  Future<void> _restore() async {
    final authService = ref.read(authServiceProvider);

    final loggedIn = await authService.tryAutoLogin();
    if (!mounted) return;
    if (loggedIn) {
      // 静默刷新 token，不阻塞跳转
      unawaited(authService.silentRefresh());
      context.go('/home');
      return;
    }

    // tryAutoLogin 失败——大概率是 access token 过期。ApiClient 的拦截器
    // 已经会在 /auth/me 收到 403 时自动用 refresh token 换新 token 重试，
    // 所以正常情况下走不到这里；这里是兜底，防的是拦截器那层万一没生效的
    // 边界情况。刷新成功后必须再跑一次 tryAutoLogin——silentRefresh 只换
    // token，不会自己去查 /auth/me 把 currentUserProvider 填上
    final refreshed = await authService.silentRefresh();
    if (!mounted) return;
    if (refreshed) {
      final loggedInAfterRefresh = await authService.tryAutoLogin();
      if (!mounted) return;
      if (loggedInAfterRefresh) {
        context.go('/home');
        return;
      }
    }

    context.go('/login');
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: Align(
        alignment: const Alignment(0, -0.12),
        child: FadeTransition(
          opacity: _fade,
          child: ScaleTransition(
            scale: _scale,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  l10n.appName,
                  style: const TextStyle(
                    fontSize: 36,
                    fontWeight: FontWeight.w900,
                    color: AppColors.primary,
                    letterSpacing: -1,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  _slogan ?? l10n.appSlogan,
                  style: const TextStyle(
                    fontSize: 14,
                    color: Color(0xFF8B8FD4),
                    letterSpacing: 6,
                  ),
                ),
                const SizedBox(height: 40),
                const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.4,
                    color: AppColors.primary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
