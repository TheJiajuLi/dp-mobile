import 'package:flutter/material.dart';

// text/heading block 的整块格式（粗体/斜体/下划线/删除线/文字色/高亮色/
// 字体/字号/行距）——发布页编辑器（block_card.dart）和阅读端渲染
// （tutorial_block_renderer.dart）必须用同一份换算逻辑，不然编辑时看到
// 的和读者实际看到的会不一样。字段本身存在 block 的 JSON 里（见
// block_model.dart 的 toJson/fromJson），这里只是"数值 -> TextStyle"
// 的纯函数，不涉及具体某个 block 对象

double resolveBlockFontSize(int fontSizeStep, {required double base}) {
  switch (fontSizeStep) {
    case 0:
      return base - 2;
    case 2:
      return base + 2;
    case 3:
      return base + 5;
    default:
      return base;
  }
}

double resolveBlockLineHeight(int lineHeightStep, {required double base}) {
  switch (lineHeightStep) {
    case 0:
      return base - 0.3;
    case 2:
      return base + 0.3;
    default:
      return base;
  }
}

// 'serif'/'monospace' 是 Skia 认得的通用字体族名，交给各平台系统字体
// fallback 解析——App 没有打包任何自定义字体文件，不需要在 pubspec.yaml
// 里额外声明
String? resolveBlockFontFamily(String? key) {
  if (key == null || key.isEmpty) return null;
  return key;
}

TextStyle applyBlockTextFormat(
  TextStyle base, {
  required bool isBold,
  required bool isItalic,
  required bool isUnderline,
  required bool isStrike,
  int? textColorValue,
  int? highlightColorValue,
  String? fontFamily,
  required int fontSizeStep,
  required int lineHeightStep,
}) {
  final decorations = <TextDecoration>[
    if (isUnderline) TextDecoration.underline,
    if (isStrike) TextDecoration.lineThrough,
  ];
  return base.copyWith(
    fontSize: resolveBlockFontSize(fontSizeStep, base: base.fontSize ?? 15),
    height: resolveBlockLineHeight(lineHeightStep, base: base.height ?? 1.7),
    fontFamily: resolveBlockFontFamily(fontFamily),
    fontWeight: isBold ? FontWeight.w700 : base.fontWeight,
    fontStyle: isItalic ? FontStyle.italic : base.fontStyle,
    color: textColorValue != null ? Color(textColorValue) : base.color,
    backgroundColor: highlightColorValue != null
        ? Color(highlightColorValue)
        : base.backgroundColor,
    decoration: decorations.isEmpty
        ? TextDecoration.none
        : TextDecoration.combine(decorations),
  );
}
