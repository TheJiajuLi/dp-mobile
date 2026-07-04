import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

class AppColors {
  static const primary = Color(0xFF6366F1);
  static const bg = Color(0xFFF7F7FB);
  static const surface = Colors.white;
  static const border = Color(0xFFE5E5EA);
  static const textPrimary = Color(0xFF1C1C1E);
  static const textMuted = Color(0xFF8E8E93);
  static const danger = Color(0xFFFF3B30);
}

class AppRadius {
  static const sm = 8.0;
  static const md = 12.0;
  static const lg = 16.0;
}

class AppSpacing {
  static const xs = 4.0;
  static const sm = 8.0;
  static const md = 16.0;
  static const lg = 24.0;
  static const xl = 32.0;
}

class AppTheme {
  static ThemeData get light => ThemeData(
    useMaterial3: true,
    scaffoldBackgroundColor: AppColors.bg,
    colorScheme: ColorScheme.fromSeed(seedColor: AppColors.primary),
    cardColor: Colors.white,
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.surface,
      foregroundColor: AppColors.textPrimary,
      elevation: 0,
      surfaceTintColor: Colors.transparent,
      centerTitle: true,
    ),
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: {
        TargetPlatform.android: CupertinoPageTransitionsBuilder(),
        TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
      },
    ),
  );

  // 这一套只覆盖到了"主背景/卡片背景/正文文字"这三类最影响观感的颜色——
  // 各页面里 Colors.grey/边框/图标强调色等次要颜色还是写死的，暗色下不会
  // 完全跟系统默认灰阶一致。要做到像素级完整的暗色适配，还需要把这些
  // 次要颜色也逐一换成读 Theme，这次先把最显眼的白底黑字问题解决掉
  static ThemeData get dark => ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    scaffoldBackgroundColor: const Color(0xFF1C1C1E),
    colorScheme: ColorScheme.fromSeed(
      seedColor: AppColors.primary,
      brightness: Brightness.dark,
    ),
    cardColor: const Color(0xFF2C2C2E),
    appBarTheme: const AppBarTheme(
      backgroundColor: Color(0xFF2C2C2E),
      foregroundColor: Colors.white,
      elevation: 0,
      surfaceTintColor: Colors.transparent,
      centerTitle: true,
    ),
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: {
        TargetPlatform.android: CupertinoPageTransitionsBuilder(),
        TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
      },
    ),
  );
}
