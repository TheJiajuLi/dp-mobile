import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../auth_service.dart';

class SplashScreen extends ConsumerStatefulWidget {
  // 从"切换账号"跳过来时传 true——这种场景下 silentRefresh() 的兜底分支
  // 不安全（见 _restore 里的说明），要跳过
  final bool fromAccountSwitch;
  const SplashScreen({super.key, this.fromAccountSwitch = false});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _restore());
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

    // 切换账号跳过来的话，到这里说明 switchToAccount() 里验证过的 token
    // 在这一小段时间内又失效了——不能再走下面 silentRefresh() 兜底：
    // refresh token 走的是全局共享的一个 CookieJar，刚切换账号并不会把
    // cookie 也换成新账号的，这里 refresh 出来的会是切换前那个账号的
    // token，却被当成新账号的 token 存下去，越描越黑。这种情况老实认输，
    // 让用户重新登录这个账号，好过静默串号
    if (widget.fromAccountSwitch) {
      context.go('/login');
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
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: const Center(child: CircularProgressIndicator(color: AppColors.primary)),
    );
  }
}
