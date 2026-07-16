import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

// 极梦品牌 logo——极光叠弧（金→绿→紫→蓝四道渐变弧线），透明底，直接铺在
// 页面/卡片背景上。全站统一从这里取，别在各页各写一份 SVG 字符串
const String _kBrandLogoSvg = '''
<svg width="200" height="150" viewBox="0 0 200 150" fill="none" xmlns="http://www.w3.org/2000/svg">
  <path d="M8 130 Q100 18 192 130" stroke="url(#t1)" stroke-width="11" stroke-linecap="round" fill="none"/>
  <path d="M26 130 Q100 38 174 130" stroke="url(#t2)" stroke-width="11" stroke-linecap="round" fill="none"/>
  <path d="M44 130 Q100 57 156 130" stroke="url(#t3)" stroke-width="11" stroke-linecap="round" fill="none"/>
  <path d="M62 130 Q100 76 138 130" stroke="url(#t4)" stroke-width="11" stroke-linecap="round" fill="none"/>
  <defs>
    <linearGradient id="t1" x1="8" y1="130" x2="192" y2="130" gradientUnits="userSpaceOnUse">
      <stop offset="0%" stop-color="#C9A840"/>
      <stop offset="100%" stop-color="#8BC34A"/>
    </linearGradient>
    <linearGradient id="t2" x1="26" y1="130" x2="174" y2="130" gradientUnits="userSpaceOnUse">
      <stop offset="0%" stop-color="#6B7FD4"/>
      <stop offset="100%" stop-color="#5B8FE0"/>
    </linearGradient>
    <linearGradient id="t3" x1="44" y1="130" x2="156" y2="130" gradientUnits="userSpaceOnUse">
      <stop offset="0%" stop-color="#5B5DA8"/>
      <stop offset="100%" stop-color="#7B6FC4"/>
    </linearGradient>
    <linearGradient id="t4" x1="62" y1="130" x2="138" y2="130" gradientUnits="userSpaceOnUse">
      <stop offset="0%" stop-color="#4CAF60"/>
      <stop offset="100%" stop-color="#66BB6A"/>
    </linearGradient>
  </defs>
</svg>
''';

class BrandLogo extends StatelessWidget {
  final double width;
  final double height;
  // 默认按 logo 原始 4:3 比例给一组大尺寸（关于页用），小尺寸场景显式传
  const BrandLogo({super.key, this.width = 116, this.height = 87});

  @override
  Widget build(BuildContext context) {
    return SvgPicture.string(_kBrandLogoSvg, width: width, height: height);
  }
}
