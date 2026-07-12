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

  // 深色主题层级——之前深色下背景/卡片/分割线用的都是同一档 Material
  // 默认灰阶（#1C1C1E/#2C2C2E/#3A3A3C），拉不开视觉深度，糊成一块。
  // 这一套改用更深的近黑背景 + 逐级提亮的卡片/表面色，层级差拉开了
  // 才看得出"背景之上浮着卡片"的立体感
  static const darkBg = Color(0xFF0A0A0F);
  static const darkCard = Color(0xFF111118);
  static const darkCardHero = Color(0xFF141427);
  static const darkCardList = Color(0xFF101017);
  static const darkSurface = Color(0xFF17171F);
  static const darkBorder = Color(0x0FFFFFFF); // rgba(255,255,255,.06)
  static const darkDivider = Color(0xFF1A1A28);
  static const darkTextPrimary = Color(0xFFF0F2F8);
  static const darkTextSecondary = Color(0xFF7A80A0);
  static const darkTextMuted = Color(0xFF4A4A6A);
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
    scaffoldBackgroundColor: AppColors.darkBg,
    colorScheme: ColorScheme.fromSeed(
      seedColor: AppColors.primary,
      brightness: Brightness.dark,
    ),
    cardColor: AppColors.darkCard,
    dividerColor: AppColors.darkDivider,
    textTheme: const TextTheme(
      bodyLarge: TextStyle(color: AppColors.darkTextPrimary),
      bodyMedium: TextStyle(color: AppColors.darkTextPrimary),
      bodySmall: TextStyle(color: AppColors.darkTextSecondary),
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.darkCard,
      foregroundColor: AppColors.darkTextPrimary,
      elevation: 0,
      surfaceTintColor: Colors.transparent,
      centerTitle: true,
    ),
    listTileTheme: const ListTileThemeData(tileColor: AppColors.darkCard),
    inputDecorationTheme: InputDecorationTheme(
      fillColor: AppColors.darkSurface,
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
