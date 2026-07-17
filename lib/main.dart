import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/app_bootstrap.dart';
import 'core/app_material.dart';
import 'core/app_session_host.dart';
import 'core/router/app_router.dart';
import 'features/auth/auth_service.dart';

// Runner 这个 target 只跑 iPhone 版——iPad 版是完全独立的 RunnerHD target
// （入口 lib/hd/main_hd.dart），两边互不相关。启动编排、MaterialApp 装配、
// 会话侧都抽到了 core/app_bootstrap|app_material|app_session_host 两端共用，
// 这里只留手机端专属的部分：深链（OAuth 回调/重置密码）
Future<void> main() => bootstrapAndRun(() => const MyApp());

class MyApp extends ConsumerStatefulWidget {
  const MyApp({super.key});

  @override
  ConsumerState<MyApp> createState() => _MyAppState();
}

class _MyAppState extends ConsumerState<MyApp> {
  final _appLinks = AppLinks();
  StreamSubscription<Uri>? _linkSub;

  @override
  void initState() {
    super.initState();
    _linkSub = _appLinks.uriLinkStream.listen(_handleDeepLink);
  }

  @override
  void dispose() {
    _linkSub?.cancel();
    super.dispose();
  }

  // 后端 Google/GitHub OAuth 回调统一走 jimeng://auth/callback（见
  // dreamingpolar_user_auth_backend 的 oauth.ts），成功带 accessToken，失败带
  // error——跟密码登录一样，userId/username 不直接信回调参数，交给
  // AuthService.completeOAuthLogin 重新拉一次 /auth/me。
  //
  // 忘记密码邮件里的重置链接走 jimeng://reset-password?token=xxx——同一个
  // 自定义 scheme 下的不同 host，各自独立处理
  void _handleDeepLink(Uri uri) {
    if (uri.scheme != 'jimeng') return;

    if (uri.host == 'reset-password') {
      final token = uri.queryParameters['token'];
      if (token == null || token.isEmpty) return;
      appRouter.push('/reset-password?token=$token');
      return;
    }

    if (uri.host != 'auth') return;

    final error = uri.queryParameters['error'];
    if (error != null) {
      appRouter.go('/login?oauth_error=$error');
      return;
    }

    final accessToken = uri.queryParameters['accessToken'];
    if (accessToken == null) return;
    unawaited(_completeOAuth(accessToken));
  }

  Future<void> _completeOAuth(String accessToken) async {
    final ok = await ref
        .read(authServiceProvider)
        .completeOAuthLogin(accessToken);
    if (ok) {
      appRouter.go('/home');
    } else {
      appRouter.go('/login?oauth_error=server_error');
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppSessionHost(
      child: buildDreamingApp(ref: ref, routerConfig: appRouter),
    );
  }
}
