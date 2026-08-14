import 'package:flutter/material.dart';

/// 统一文字 token。
///
/// 字号/字重取「代码事实主力值」（正文 12/13/14、字重 w500/w600/w700），
/// 不引入新值。**不带 height**——行高交给个别页面按需覆盖（阅读页等少数
/// 场景会显式设 height，绝大多数 UI 文字不设，跟现状一致）。
///
/// 用法：`AppTextStyles.body` 或 `AppTextStyles.body.copyWith(color: ...)`。
class AppTextStyles {
  // 标题层级
  static const h1 = TextStyle(fontSize: 22, fontWeight: FontWeight.w700);
  static const h2 = TextStyle(fontSize: 20, fontWeight: FontWeight.w700);
  static const h3 = TextStyle(fontSize: 17, fontWeight: FontWeight.w600);
  static const title = TextStyle(fontSize: 16, fontWeight: FontWeight.w600);

  // 正文（三档）
  static const body = TextStyle(fontSize: 14, fontWeight: FontWeight.w400);
  static const bodyStrong = TextStyle(fontSize: 14, fontWeight: FontWeight.w600);
  static const bodySmall = TextStyle(fontSize: 13, fontWeight: FontWeight.w400);

  // 次级信息
  static const caption = TextStyle(fontSize: 12, fontWeight: FontWeight.w400);
  static const label = TextStyle(fontSize: 11, fontWeight: FontWeight.w500);

  // 按钮
  static const button = TextStyle(fontSize: 15, fontWeight: FontWeight.w600);
  static const buttonSmall = TextStyle(fontSize: 12, fontWeight: FontWeight.w600);
}
