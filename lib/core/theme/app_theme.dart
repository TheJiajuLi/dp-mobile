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
    dividerColor: const Color(0xFFF0F0F0),
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.surface,
      foregroundColor: AppColors.textPrimary,
      elevation: 0,
      surfaceTintColor: Colors.transparent,
      centerTitle: true,
    ),
    listTileTheme: const ListTileThemeData(tileColor: Colors.white),
    inputDecorationTheme: InputDecorationTheme(
      fillColor: const Color(0xFFF5F5F5),
      filled: true,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
    ),
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: {
        TargetPlatform.android: CupertinoPageTransitionsBuilder(),
        TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
      },
    ),
  );

  // 次要装饰色（Colors.grey 图标强调色等）还是写死的，暗色下不会跟系统
  // 默认灰阶完全一致，但主背景/卡片/分割线/输入框/正文文字这些最影响
  // 观感的都已经跟着 Theme 走了
  static ThemeData get dark => ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    scaffoldBackgroundColor: const Color(0xFF1C1C1E),
    colorScheme: ColorScheme.fromSeed(
      seedColor: AppColors.primary,
      brightness: Brightness.dark,
    ),
    cardColor: const Color(0xFF2C2C2E),
    dividerColor: const Color(0xFF3A3A3C),
    appBarTheme: const AppBarTheme(
      backgroundColor: Color(0xFF2C2C2E),
      foregroundColor: Colors.white,
      elevation: 0,
      surfaceTintColor: Colors.transparent,
      centerTitle: true,
    ),
    listTileTheme: const ListTileThemeData(tileColor: Color(0xFF2C2C2E)),
    inputDecorationTheme: InputDecorationTheme(
      fillColor: const Color(0xFF3A3A3C),
      filled: true,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
    ),
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: {
        TargetPlatform.android: CupertinoPageTransitionsBuilder(),
        TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
      },
    ),
  );
}
