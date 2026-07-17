import 'package:flutter/material.dart';

import '../../../features/jisuo/screens/jisuo_screen.dart';

// 极索——阶段3 直接嵌手机 JisuoScreen（自带 Scaffold + 流式直答 + 示例问题），
// 功能立即可用。HD 宽屏布局适配（左对话/右结果之类）留后续
class HdJisuoPage extends StatelessWidget {
  const HdJisuoPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const JisuoScreen();
  }
}
