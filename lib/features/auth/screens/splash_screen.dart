import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../auth_service.dart';

class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

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
    return const Scaffold(
      backgroundColor: AppColors.bg,
      body: Center(child: CircularProgressIndicator(color: AppColors.primary)),
    );
  }
}
