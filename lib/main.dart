import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:cookie_jar/cookie_jar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import 'core/font_size_provider.dart';
import 'core/locale_provider.dart';
import 'core/network/api_client.dart';
import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';
import 'core/theme_provider.dart';
import 'features/auth/auth_service.dart';
import 'l10n/generated/app_localizations.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 临时诊断用：捕获完整 FlutterError（含 stack），排查
  // semantics.parentDataDirty 断言崩溃时定位真正的调用链。排查完记得删掉
  FlutterError.onError = (FlutterErrorDetails details) {
    FlutterError.presentError(details);
    debugPrint('═══ FLUTTER ERROR ═══');
    debugPrint(details.toString());
    debugPrint(details.stack.toString());
    debugPrint('═══════════════════');
  };

  // /auth/refresh 认的是登录时后端下发的 dp_refresh HttpOnly cookie，必须
  // 落盘（PersistCookieJar）才能在 App 被系统整个杀掉重启后依然有效——
  // 只是"划走切到后台但进程没被杀"的话，内存态的 cookie 本来就不会丢。
  // getApplicationDocumentsDirectory() 是个平台 channel 调用，冷启动时
  // await 它会直接卡住 runApp()、拖慢启动页出现的时间——用
  // _DeferredCookieJar 包一层同步喂给 Dio，真正的 PersistCookieJar 在
  // 后台异步建好后再生效，不阻塞首帧
  final cookieJar = _DeferredCookieJar(_buildPersistentCookieJar());

  // Runner 这个 target 只跑 iPhone 版——iPad 版是完全独立的 RunnerHD
  // target（入口是 lib/hd/main_hd.dart），两边互不相关，main.dart 不需要
  // 做任何设备检测/分支
  runApp(
    ProviderScope(
      overrides: [
        apiClientProvider.overrideWith(
          (ref) => ApiClient(ref, cookieJar: cookieJar),
        ),
      ],
      child: const MyApp(),
    ),
  );
}

Future<PersistCookieJar> _buildPersistentCookieJar() async {
  final docsDir = await getApplicationDocumentsDirectory();
  return PersistCookieJar(
    ignoreExpires: false,
    storage: FileStorage('${docsDir.path}/.cookies/'),
  );
}

class _DeferredCookieJar implements CookieJar {
  _DeferredCookieJar(this._ready);

  final Future<CookieJar> _ready;

  @override
  bool get ignoreExpires => false;

  @override
  Future<void> saveFromResponse(Uri uri, List<Cookie> cookies) async =>
      (await _ready).saveFromResponse(uri, cookies);

  @override
  Future<List<Cookie>> loadForRequest(Uri uri) async =>
      (await _ready).loadForRequest(uri);

  @override
  Future<void> deleteAll() async => (await _ready).deleteAll();

  @override
  Future<void> delete(Uri uri, [bool withDomainSharedCookie = false]) async =>
      (await _ready).delete(uri, withDomainSharedCookie);
}

class MyApp extends ConsumerStatefulWidget {
  const MyApp({super.key});

  @override
  ConsumerState<MyApp> createState() => _MyAppState();
}

class _MyAppState extends ConsumerState<MyApp> with WidgetsBindingObserver {
  final _appLinks = AppLinks();
  StreamSubscription<Uri>? _linkSub;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _linkSub = _appLinks.uriLinkStream.listen(_handleDeepLink);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _linkSub?.cancel();
    super.dispose();
  }

  // 后端 Google/GitHub OAuth 回调统一走 jimeng://auth/callback 这个
  // scheme（见 dreamingpolar_user_auth_backend 的 oauth.ts），成功带
  // accessToken，失败带 error——跟密码登录一样，userId/username 不直接
  // 信回调参数，交给 AuthService.completeOAuthLogin 重新拉一次 /auth/me
  //
  // 忘记密码邮件里的重置链接走 jimeng://reset-password?token=xxx——跟
  // OAuth 回调是同一个自定义 scheme 下的不同 host，各自独立处理
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
    final ok = await ref.read(authServiceProvider).completeOAuthLogin(accessToken);
    if (ok) {
      appRouter.go('/home');
    } else {
      appRouter.go('/login?oauth_error=server_error');
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // App 从后台回来时顺手静默换新 token。真正兜底的其实是 ApiClient
    // 拦截器里 403 自动刷新重试那套——即使这里没跑或跑失败，下一次真实
    // 请求撞到过期 token 时也会自动补救，这里只是提前续一下，减少那次
    // "刚好赶上过期"的请求被迫多绕一次刷新+重试
    if (state == AppLifecycleState.resumed &&
        ref.read(currentUserProvider) != null) {
      unawaited(ref.read(authServiceProvider).silentRefresh());
    }
  }

  @override
  Widget build(BuildContext context) {
    final themePref = ref.watch(themeProvider);
    final fontSize = ref.watch(fontSizeProvider);
    final localePref = ref.watch(localeProvider);

    return MaterialApp.router(
      title: '',
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      // MaterialApp 默认会把主题切换做成 200ms 的渐变过渡（哪怕没有显式
      // 用 AnimatedTheme，这个动画也是内置的）。问题是代码块、聊天气泡
      // 这些地方大量用的是写死的深色（不跟主题走，任何时候都是深色），
      // 这些区域不参与这段渐变、瞬间就是最终颜色；而真正跟主题走的区域
      // （比如底部导航栏读 scaffoldBackgroundColor）却要用 200ms 慢慢
      // 过渡过去——这两类区域在动画过程中颜色对不上，就是用户看到的
      // "底部tab跟上方不一致的闪烁延迟"。改成 Duration.zero 让切换瞬间
      // 完成，不再有过渡窗口，从根上消除这类不同步问题，而不是继续在
      // 每一处写死深色的地方逐个找补
      themeAnimationDuration: Duration.zero,
      themeMode: switch (themePref) {
        ThemePreference.light => ThemeMode.light,
        ThemePreference.dark => ThemeMode.dark,
        ThemePreference.system => ThemeMode.system,
      },
      locale: localeFor(localePref),
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      routerConfig: appRouter,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(fontSize)),
        child: child!,
      ),
    );
  }
}
