import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/auth/auth_service.dart';
import '../features/subscription/purchase_service.dart';

// 两端共用的会话侧宿主：内购初始化 + App 回前台静默续 token。纯逻辑，build
// 直接返回 child，包在 MaterialApp 外层即可。深链（OAuth 回调/重置密码）是
// 端相关的（手机硬绑 appRouter），不放这里——留在各自的 App widget 处理
class AppSessionHost extends ConsumerStatefulWidget {
  final Widget child;
  const AppSessionHost({super.key, required this.child});

  @override
  ConsumerState<AppSessionHost> createState() => _AppSessionHostState();
}

class _AppSessionHostState extends ConsumerState<AppSessionHost>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // 尽早初始化内购：监听 purchaseStream 才能接住上次被中断/挂起的交易，并
    // 预加载商品信息。幂等，失败不影响 App 启动
    unawaited(ref.read(purchaseServiceProvider).init());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // App 从后台回来时顺手静默换新 token。真正兜底的是 ApiClient 拦截器里
    // 403 自动刷新重试那套；这里只是提前续一下，减少"刚好赶上过期"的请求
    // 被迫多绕一次刷新+重试
    if (state == AppLifecycleState.resumed &&
        ref.read(currentUserProvider) != null) {
      unawaited(ref.read(authServiceProvider).silentRefresh());
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
