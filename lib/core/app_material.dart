import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'font_size_provider.dart';
import 'locale_provider.dart';
import 'theme/app_theme.dart';
import 'theme_provider.dart';
import '../l10n/generated/app_localizations.dart';
import '../shared/services/pyodide_engine.dart';

// 两端（Runner / RunnerHD）共用的 MaterialApp.router 装配：主题/深色/字号缩放/
// l10n + 全局隐藏 Pyodide WebView。唯一不同的是 routerConfig（手机 appRouter /
// HD hdRouter），参数化出去，其余一律共用，避免两端 MaterialApp 慢慢跑偏
Widget buildDreamingApp({
  required WidgetRef ref,
  required RouterConfig<Object> routerConfig,
}) {
  final themePref = ref.watch(themeProvider);
  final fontSize = ref.watch(fontSizeProvider);
  final localePref = ref.watch(localeProvider);

  return MaterialApp.router(
    title: '',
    theme: AppTheme.light,
    darkTheme: AppTheme.dark,
    // 主题切换动画设 0：代码块/聊天气泡等大量写死深色的区域不参与渐变、瞬间
    // 就是最终色，而跟主题走的区域要 200ms 过渡，两类区域在动画过程中对不上
    // 会闪。设 Duration.zero 瞬间切换，从根上消除不同步
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
    routerConfig: routerConfig,
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(
        context,
      ).copyWith(textScaler: TextScaler.linear(fontSize)),
      child: Stack(
        children: [
          child!,
          // 全局共享的隐藏 Pyodide WebView——App 启动就预热 compiler.js/Pyodide，
          // Notebook/发布页/教程详情页运行代码块时不用再各自等冷启动。挂在
          // builder 里跟路由无关，整个 App 生命周期只建一次
          Positioned(
            left: -9999,
            top: -9999,
            width: 1,
            height: 1,
            child: ref.read(pyodideEngineProvider).buildHiddenWebView(),
          ),
        ],
      ),
    ),
  );
}
