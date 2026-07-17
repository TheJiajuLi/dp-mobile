import 'dart:async';
import 'dart:ui' show PlatformDispatcher;

import 'package:cookie_jar/cookie_jar.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import 'network/api_client.dart';

// 两端（Runner=iPhone / RunnerHD=iPad）共用的启动编排：诊断错误 handler +
// Crashlytics + 落盘 cookie + apiClient override + runApp。各自入口只需给一个
// rootBuilder（手机传 MyApp、HD 传 HdApp），其余启动步骤完全一致，别再各写一遍
Future<void> bootstrapAndRun(Widget Function() rootBuilder) async {
  WidgetsFlutterBinding.ensureInitialized();
  _installDiagnosticErrorHandler();
  await _initCrashlytics();

  // /auth/refresh 认的是登录时后端下发的 dp_refresh HttpOnly cookie，必须落盘
  // （PersistCookieJar）才能在 App 被系统整个杀掉重启后依然有效。
  // getApplicationDocumentsDirectory() 是平台 channel 调用，冷启动时 await 它
  // 会卡住 runApp()、拖慢首帧——用 _DeferredCookieJar 包一层同步喂给 Dio，
  // 真正的 PersistCookieJar 在后台异步建好后再生效，不阻塞首帧
  final cookieJar = _DeferredCookieJar(_buildPersistentCookieJar());

  runApp(
    ProviderScope(
      overrides: [
        apiClientProvider.overrideWith(
          (ref) => ApiClient(ref, cookieJar: cookieJar),
        ),
      ],
      child: rootBuilder(),
    ),
  );
}

// 临时诊断用：捕获完整 FlutterError（含 stack），排查 semantics.parentDataDirty
// 断言崩溃时定位真正的调用链。_initCrashlytics 成功时会覆盖成 Crashlytics 上报
void _installDiagnosticErrorHandler() {
  FlutterError.onError = (FlutterErrorDetails details) {
    FlutterError.presentError(details);
    debugPrint('═══ FLUTTER ERROR ═══');
    debugPrint(details.toString());
    debugPrint(details.stack.toString());
    debugPrint('═══════════════════');
  };
}

// Firebase Crashlytics 初始化。只有当项目里补齐了 Firebase 配置文件时
// initializeApp() 才会成功、崩溃上报才真正启用。没配置时 initializeApp() 抛
// 异常，这里 catch 掉——保留上面的诊断 handler，不影响 App 启动
Future<void> _initCrashlytics() async {
  try {
    await Firebase.initializeApp();
    final crashlytics = FirebaseCrashlytics.instance;

    // Flutter 框架层未捕获错误（build/layout/paint 等）
    FlutterError.onError = (FlutterErrorDetails details) {
      FlutterError.presentError(details);
      crashlytics.recordFlutterFatalError(details);
    };

    // 框架之外的异步未捕获错误（isolate 顶层）
    PlatformDispatcher.instance.onError = (error, stack) {
      crashlytics.recordError(error, stack, fatal: true);
      return true;
    };
  } catch (_) {
    // Firebase 未配置——崩溃上报暂不启用，保留诊断 handler，静默跳过
  }
}

Future<PersistCookieJar> _buildPersistentCookieJar() async {
  final docsDir = await getApplicationDocumentsDirectory();
  return PersistCookieJar(
    ignoreExpires: false,
    storage: FileStorage('${docsDir.path}/.cookies/'),
  );
}

// 同步壳：真正的 PersistCookieJar 建好前先同步喂给 Dio，建好后转发到它
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
