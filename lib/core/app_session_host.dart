import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter_apns_only/flutter_apns_only.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/auth/auth_service.dart';
import '../features/subscription/purchase_service.dart';
import 'network/api_client.dart';
import 'router/app_router.dart';

// 两端共用的会话侧宿主：内购初始化 + App 回前台静默续 token + APNs 推送
// （注册 device token 上报后端 / 收到推送跳转）。纯逻辑，build 直接返回 child，
// 包在 MaterialApp 外层即可。深链（OAuth 回调/重置密码）是端相关的（手机硬绑
// appRouter），不放这里——留在各自的 App widget 处理
class AppSessionHost extends ConsumerStatefulWidget {
  final Widget child;
  const AppSessionHost({super.key, required this.child});

  @override
  ConsumerState<AppSessionHost> createState() => _AppSessionHostState();
}

class _AppSessionHostState extends ConsumerState<AppSessionHost>
    with WidgetsBindingObserver {
  ApnsPushConnectorOnly? _apns;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // 尽早初始化内购：监听 purchaseStream 才能接住上次被中断/挂起的交易，并
    // 预加载商品信息。幂等，失败不影响 App 启动
    unawaited(ref.read(purchaseServiceProvider).init());
    _setupApns();
  }

  // APNs 推送——仅 iOS（ApnsPushConnectorOnly 的构造在非 iOS 平台会直接抛）。
  // 请求通知权限 → 拿到 device token 后上报后端 → 收到推送按 type 跳转
  void _setupApns() {
    if (!Platform.isIOS) return;
    final apns = ApnsPushConnectorOnly();
    _apns = apns;
    apns.configureApns(
      onLaunch: _onPushOpen, // 冷启动被推送点开
      onResume: _onPushOpen, // 后台被推送点开
      onMessage: _onPushReceive, // 前台收到（暂不打断用户，保留钩子）
    );
    apns.requestNotificationPermissions(
      const IosNotificationSettings(sound: true, badge: true, alert: true),
    );
    apns.token.addListener(() {
      final token = apns.token.value;
      if (token != null) unawaited(_uploadDeviceToken(token));
    });
  }

  // 上报 device token。未登录时后端会因无认证 cookie 拒掉——忽略即可；回前台
  // 且已登录时会再补传一次（见 didChangeAppLifecycleState），覆盖"token 先到、
  // 登录后到"的情况
  Future<void> _uploadDeviceToken(String token) async {
    try {
      await ref
          .read(apiClientProvider)
          .post('/auth/device/token', data: {'deviceToken': token});
    } catch (_) {}
  }

  // 前台收到推送——保留钩子，暂不跳转/打断（通知页/未读数会自己刷新）
  Future<void> _onPushReceive(ApnsRemoteMessage message) async {}

  // 被推送点开（冷启动/后台）——按 payload 顶层的 type 跳转对应页面
  Future<void> _onPushOpen(ApnsRemoteMessage message) async {
    final data = message.payload;
    switch (data['type']) {
      case 'like':
      case 'comment':
        final id = data['tutorialId'];
        if (id != null) appRouter.push('/tutorial/$id');
      case 'message':
        appRouter.push('/messages');
      case 'follow':
      case 'answer':
        appRouter.push('/notifications');
    }
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
      // 已登录且有 device token → 补传一次（防 token 先于登录到达时漏报）
      final token = _apns?.token.value;
      if (token != null) unawaited(_uploadDeviceToken(token));
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
