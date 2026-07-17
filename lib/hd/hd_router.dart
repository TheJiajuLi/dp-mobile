import 'package:go_router/go_router.dart';

import '../features/auth/screens/forgot_password_screen.dart';
import '../features/auth/screens/login_screen.dart';
import '../features/auth/screens/register_screen.dart';
import '../features/auth/screens/reset_password_screen.dart';
import '../features/auth/screens/splash_screen.dart';
import '../features/settings/screens/privacy_policy_screen.dart';
import '../features/settings/screens/terms_of_service_screen.dart';
import 'pages/discover/hd_discover_page.dart';
import 'pages/home/hd_home_page.dart';
import 'pages/jisuo/hd_jisuo_page.dart';
import 'pages/notebook/hd_notebook_page.dart';
import 'pages/notifications/hd_notifications_page.dart';
import 'pages/profile/hd_profile_page.dart';
import 'pages/settings/hd_settings_page.dart';
import 'pages/xmeng/hd_xmeng_page.dart';
import 'shell/hd_shell.dart';

// HD 版路由。复用主 App 同一批 auth 屏（splash/login/register/忘记密码/重置/
// 条款/隐私），登录态/跳转逻辑跟手机端完全一致——auth 屏用的是 context.go /
// GoRouter.of(context)，在 HD 里会解析到本 router，不用改一行。
//
// 登录成功后 auth 屏统一 go('/home')，但 HD 没有 /home（那是手机 shell 的
// 分支），所以顶层 redirect 把 /home 改投 /hd/home。
//
// 5 个内容分支 + 底部 3 个（通知/设置/头像）都进 StatefulShellRoute.indexedStack
// ——图标栏常驻、每个分支切走再回来状态保活。branch 顺序必须跟 hd_icon_rail
// 里的 index 一致：0 首页 1 发现 2 极索 3 Notebook 4 小梦 5 通知 6 设置 7 头像
final hdRouter = GoRouter(
  initialLocation: '/splash',
  redirect: (context, state) {
    // 手机 auth 屏落地到 /home，HD 改投 /hd/home
    if (state.uri.path == '/home') return '/hd/home';
    return null;
  },
  routes: [
    GoRoute(path: '/splash', builder: (context, state) => const SplashScreen()),
    GoRoute(path: '/login', builder: (context, state) => const LoginScreen()),
    GoRoute(
      path: '/register',
      builder: (context, state) => const RegisterScreen(),
    ),
    GoRoute(
      path: '/forgot-password',
      builder: (context, state) => const ForgotPasswordScreen(),
    ),
    GoRoute(
      path: '/reset-password',
      builder: (context, state) =>
          ResetPasswordScreen(token: state.uri.queryParameters['token'] ?? ''),
    ),
    GoRoute(
      path: '/settings/terms',
      builder: (context, state) => const TermsOfServiceScreen(),
    ),
    GoRoute(
      path: '/settings/privacy-policy',
      builder: (context, state) => const PrivacyPolicyScreen(),
    ),
    StatefulShellRoute.indexedStack(
      builder: (context, state, navigationShell) =>
          HdShell(navigationShell: navigationShell),
      branches: [
        // ── 图标栏顶部 5 ──
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/hd/home',
              builder: (context, state) => const HdHomePage(),
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/hd/discover',
              builder: (context, state) => const HdDiscoverPage(),
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/hd/jisuo',
              builder: (context, state) => const HdJisuoPage(),
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/hd/notebook',
              builder: (context, state) => const HdNotebookPage(),
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/hd/xmeng',
              builder: (context, state) => const HdXmengPage(),
            ),
          ],
        ),
        // ── 图标栏底部 3 ──
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/hd/notifications',
              builder: (context, state) => const HdNotificationsPage(),
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/hd/settings',
              builder: (context, state) => const HdSettingsPage(),
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/hd/profile',
              builder: (context, state) => const HdProfilePage(),
            ),
          ],
        ),
      ],
    ),
  ],
);
