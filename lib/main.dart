import 'dart:async';

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
import 'hd/hd_app.dart';
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
  // 只是"划走切到后台但进程没被杀"的话，内存态的 cookie 本来就不会丢
  final docsDir = await getApplicationDocumentsDirectory();
  final cookieJar = PersistCookieJar(
    ignoreExpires: false,
    storage: FileStorage('${docsDir.path}/.cookies/'),
  );

  // iPad 和 iPhone 是两个完全不同的 App（UI 层零共用），但账号体系/网络层
  // 得是同一套——同一个 ProviderScope + 同一份 apiClientProvider
  // override，HdApp 目前还没接真实数据，但这份共享已经就绪，以后接的时候
  // 不用再动 main.dart
  runApp(
    ProviderScope(
      overrides: [
        apiClientProvider.overrideWith(
          (ref) => ApiClient(ref, cookieJar: cookieJar),
        ),
      ],
      child: const _RootApp(),
    ),
  );
}

// 设备判定挪到 build() 里用 View.of(context) 读，而不是在 main() 里用
// PlatformDispatcher.instance.views.first 提前读——runApp 之前引擎不一定
// 已经把真实的视图尺寸送达，main() 时机读到的可能是过期/占位值，尤其是
// 通过 Xcode 直接跑（不是走 flutter run）的时候更容易踩到。放进 build()
// 里保证是在真实 frame 构建时读，此时引擎早就把正确的 metrics 传过来了
class _RootApp extends StatelessWidget {
  const _RootApp();

  @override
  Widget build(BuildContext context) {
    final view = View.of(context);
    final shortestSide = view.physicalSize.shortestSide / view.devicePixelRatio;
    return shortestSide >= 600 ? const HdApp() : const MyApp();
  }
}

class MyApp extends ConsumerStatefulWidget {
  const MyApp({super.key});

  @override
  ConsumerState<MyApp> createState() => _MyAppState();
}

class _MyAppState extends ConsumerState<MyApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
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
