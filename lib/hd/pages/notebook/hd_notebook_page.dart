import 'package:flutter/material.dart';

import '../../../features/notebook/screens/notebook_home_screen.dart';

// Notebook——阶段4 直接嵌手机 NotebookHomeScreen（Notebook 列表入口，点进去
// 是编辑器）。整块可用，HD 宽屏布局适配留后
class HdNotebookPage extends StatelessWidget {
  const HdNotebookPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const NotebookHomeScreen();
  }
}
