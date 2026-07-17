import 'package:flutter/material.dart';

import '../../../features/ai/screens/xiaomeng_screen.dart';

// 小梦——阶段4 直接嵌手机 XiaomengScreen（自带流式对话入口），整块可用，跟
// 极索一样。HD 宽屏布局适配留后
class HdXmengPage extends StatelessWidget {
  const HdXmengPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const XiaomengScreen();
  }
}
