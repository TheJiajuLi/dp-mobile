import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// 代码类 cell（python/sql/javascript/r/julia/html）的正文——始终是等宽
// 编辑框，跟 markdown/latex 那种"未选中渲染/选中编辑"不是一回事，从
// notebook_editor_screen.dart 的 _buildCellBody 里拆出来
class NotebookCodeCellBody extends StatelessWidget {
  final String cellType;
  final bool isDark;
  final TextEditingController controller;
  final FocusNode focusNode;
  final VoidCallback onTap;
  final ValueChanged<String> onChanged;
  // 空白 cell 按 Backspace/Delete 时删除本 cell（内容非空时不拦，交回输入框）
  final VoidCallback? onEmptyBackspace;

  const NotebookCodeCellBody({
    super.key,
    required this.cellType,
    required this.isDark,
    required this.controller,
    required this.focusNode,
    required this.onTap,
    required this.onChanged,
    this.onEmptyBackspace,
  });

  static String hintFor(String type) => switch (type) {
    'sql' => '-- 输入 SQL…',
    _ => '# 输入代码…',
  };

  // 包一层 Focus 当祖先拦 Backspace/Delete：内容为空时删本 cell，非空时
  // ignored 交回输入框正常删字符。跟发布页编辑器同一套写法
  KeyEventResult _handleBackspace(KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final isDeleteKey =
        event.logicalKey == LogicalKeyboardKey.backspace ||
        event.logicalKey == LogicalKeyboardKey.delete;
    if (!isDeleteKey ||
        controller.text.isNotEmpty ||
        onEmptyBackspace == null) {
      return KeyEventResult.ignored;
    }
    onEmptyBackspace!();
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      // 正文区跟设计稿一致用白底（透明=露出卡片白），头部浅灰、正文纯白，
      // 靠头部底色和分割线区分，不再给正文另铺一层冷灰
      color: Colors.transparent,
      child: Focus(
        onKeyEvent: (node, event) => _handleBackspace(event),
        // 限高 240：超出后代码框内部自滚，不再无限撑高整个 Cell
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 240),
          child: TextField(
            controller: controller,
            focusNode: focusNode,
            maxLines: null,
          onTap: onTap,
          // 代码框关掉 iOS 智能标点/自动纠错——否则直引号会被替换成弯引号
          // （' " → ‘ ’ “ ”）、连字符变破折号，粘进 Python/SQL 直接语法报错
          autocorrect: false,
          enableSuggestions: false,
          smartDashesType: SmartDashesType.disabled,
          smartQuotesType: SmartQuotesType.disabled,
          keyboardType: TextInputType.multiline,
          style: TextStyle(
            fontFamily: 'monospace',
            fontSize: 12,
            height: 1.7,
            color: isDark ? const Color(0xFFE0E2F0) : const Color(0xFF1A1A1A),
          ),
          decoration: InputDecoration(
            // filled:false 显式关掉——否则会吃全局 InputDecorationTheme 的
            // filled:true 灰底，代码块正文区就跟 markdown/latex 的白底不一致了
            filled: false,
            border: InputBorder.none,
            isDense: true,
            contentPadding: const EdgeInsets.all(12),
            hintText: hintFor(cellType),
            hintStyle: TextStyle(
              fontFamily: 'monospace',
              fontSize: 12,
              color: isDark ? const Color(0xFF444444) : const Color(0xFFCCCCCC),
            ),
          ),
          onChanged: onChanged,
          ),
        ),
      ),
    );
  }
}
