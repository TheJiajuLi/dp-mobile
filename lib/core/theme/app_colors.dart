import 'package:flutter/material.dart';

/// 统一颜色 token。
///
/// 值一律取「代码里出现次数最多的事实值」，不引入新值。浅色 5 个历史 token
/// （bg/border/textPrimary/textMuted/danger）本次校准到事实值——注释里标了原值。
/// 深色那套当初就是照事实值写的，保持不变。
///
/// 从 app_theme.dart 移过来集中管理；app_theme.dart 仍 re-export 本类，
/// 老的 `import '.../app_theme.dart'` 引用 AppColors 不受影响。
class AppColors {
  // ── 品牌 ────────────────────────────────────────────────
  static const primary = Color(0xFF6366F1); // 211×
  static const primaryLight = Color(0xFFEEF0FF); // 104× 选中态/浅底

  // ── 浅色 · 背景/表面/边框 ─────────────────────────────────
  static const bg = Color(0xFFFAFAF8); // 74×（原 F7F7FB，已校准）
  static const surface = Colors.white; // 卡片
  static const surfaceAlt = Color(0xFFF5F5F5); // 46× 输入底/表面2
  static const border = Color(0xFFEBEBEB); // 75×（原 E5E5EA，已校准）
  static const divider = Color(0xFFF0F0F0); // 36×

  // ── 浅色 · 文字（深 → 浅）─────────────────────────────────
  static const textPrimary = Color(0xFF1A1A1A); // 186×（原 1C1C1E，已校准）
  static const textSecondary = Color(0xFF555555); // 48×
  static const textMuted = Color(0xFF999999); // 57×（原 8E8E93，已校准）
  static const textFaint = Color(0xFF888888); // 54×
  static const textDisabled = Color(0xFFBBBBBB); // 25×

  // ── 语义色 + 浅底 ────────────────────────────────────────
  static const success = Color(0xFF16A34A); // 99×
  static const successLight = Color(0xFFE8F8F0); // 18×
  static const warning = Color(0xFFD97706); // 67×
  static const amber = Color(0xFFF59E0B); // 33×
  static const warningLight = Color(0xFFFEF3C7); // 18×
  static const danger = Color(0xFFEF4444); // 61×（原 FF3B30，已校准）
  static const dangerStrong = Color(0xFFDC2626); // 44×
  static const info = Color(0xFF2563EB); // 28×
  static const accentPurple = Color(0xFF8B5CF6); // 26×

  // ── 深色（跟事实值一致，保留）─────────────────────────────
  static const darkBg = Color(0xFF0A0A0F);
  static const darkCard = Color(0xFF111118);
  static const darkCardHero = Color(0xFF141427);
  static const darkCardList = Color(0xFF101017);
  static const darkSurface = Color(0xFF17171F); // 36×
  static const darkBorder = Color(0x0FFFFFFF); // rgba(255,255,255,.06)
  static const darkDivider = Color(0xFF1A1A28);
  static const darkTextPrimary = Color(0xFFF0F2F8); // 39×
  static const darkTextSecondary = Color(0xFF7A80A0); // 36×
  static const darkTextMuted = Color(0xFF4A4A6A);
}
