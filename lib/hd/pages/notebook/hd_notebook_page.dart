import 'package:flutter/material.dart';

import '../../../features/notebook/screens/notebook_editor_screen.dart';
import '../../../features/notebook/screens/notebook_home_screen.dart';

// Notebook——HD 标签内联切换：无打开的 Notebook → NotebookHomeScreen（列表）；
// 打开某个 → NotebookEditorScreen（宽屏自适应成左 Cell 列表 + 右聚焦编辑双栏）。
// 用 onOpen/onExit 回调在同一标签内切换，不 push 新路由，保留 HD 侧栏。
// 编辑器的运行/保存/AI/SQL/R 逻辑全部走手机端同一套，不分叉。
class HdNotebookPage extends StatefulWidget {
  const HdNotebookPage({super.key});

  @override
  State<HdNotebookPage> createState() => _HdNotebookPageState();
}

class _HdNotebookPageState extends State<HdNotebookPage> {
  String? _openNbId;

  @override
  Widget build(BuildContext context) {
    if (_openNbId == null) {
      return NotebookHomeScreen(
        onOpen: (id) => setState(() => _openNbId = id),
      );
    }
    return NotebookEditorScreen(
      // 换 notebook 时用 ValueKey 强制重建，避免复用上一个 notebook 的 State
      key: ValueKey(_openNbId),
      nbId: _openNbId!,
      onExit: () => setState(() => _openNbId = null),
    );
  }
}
