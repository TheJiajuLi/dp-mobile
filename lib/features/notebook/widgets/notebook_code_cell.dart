import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// 代码类 cell（python/sql/javascript/r/julia/html）的正文——始终是等宽
// 编辑框，跟 markdown/latex 那种"未选中渲染/选中编辑"不是一回事，从
// notebook_editor_screen.dart 的 _buildCellBody 里拆出来。
// B 阶段·对齐 IDE：左侧加行号 gutter（按逻辑行测量换行高度对齐，跟代码框
// 同步滚动）
class NotebookCodeCellBody extends StatefulWidget {
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

  @override
  State<NotebookCodeCellBody> createState() => _NotebookCodeCellBodyState();
}

class _NotebookCodeCellBodyState extends State<NotebookCodeCellBody> {
  // 代码框内部滚动 + 行号列滚动，用监听保持同步（行号列关掉手势滚动，
  // 只跟随代码框）
  final ScrollController _codeScroll = ScrollController();
  final ScrollController _gutterScroll = ScrollController();

  // 等宽字体度量：12 号 × 1.7 行高 = 20.4，行号和代码共用，保证逐行对齐
  static const double _fontSize = 12;
  static const double _lineHeight = _fontSize * 1.7; // 20.4
  static const double _padV = 12; // 代码框上下内边距
  static const double _gutterW = 42;
  static const double _maxH = 240;

  @override
  void initState() {
    super.initState();
    _codeScroll.addListener(_syncGutter);
    // 文字变化时行数/换行会变，需要重建行号列
    widget.controller.addListener(_onTextChanged);
  }

  @override
  void didUpdateWidget(NotebookCodeCellBody old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) {
      old.controller.removeListener(_onTextChanged);
      widget.controller.addListener(_onTextChanged);
    }
  }

  void _onTextChanged() {
    if (mounted) setState(() {});
  }

  // 代码框滚动 → 行号列同步偏移（两侧内容高度一致，offset 直接对齐）
  void _syncGutter() {
    if (!_gutterScroll.hasClients) return;
    final max = _gutterScroll.position.maxScrollExtent;
    final target = _codeScroll.offset.clamp(0.0, max);
    if ((_gutterScroll.offset - target).abs() > 0.5) {
      _gutterScroll.jumpTo(target);
    }
  }

  @override
  void dispose() {
    _codeScroll.removeListener(_syncGutter);
    widget.controller.removeListener(_onTextChanged);
    _codeScroll.dispose();
    _gutterScroll.dispose();
    super.dispose();
  }

  // 包一层 Focus 当祖先拦 Backspace/Delete：内容为空时删本 cell，非空时
  // ignored 交回输入框正常删字符。跟发布页编辑器同一套写法
  KeyEventResult _handleBackspace(KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final isDeleteKey =
        event.logicalKey == LogicalKeyboardKey.backspace ||
        event.logicalKey == LogicalKeyboardKey.delete;
    if (!isDeleteKey ||
        widget.controller.text.isNotEmpty ||
        widget.onEmptyBackspace == null) {
      return KeyEventResult.ignored;
    }
    widget.onEmptyBackspace!();
    return KeyEventResult.handled;
  }

  TextStyle get _codeStyle => TextStyle(
    fontFamily: 'monospace',
    fontSize: _fontSize,
    height: 1.7,
    color: widget.isDark ? const Color(0xFFE0E2F0) : const Color(0xFF1A1A1A),
  );

  // 逐行测量：给定代码内容区宽度，算出每个逻辑行占几个视觉行（软换行）
  List<int> _measureVisualLines(double contentWidth) {
    final lines = widget.controller.text.split('\n');
    return [
      for (final line in lines)
        TextPainter(
          text: TextSpan(text: line.isEmpty ? ' ' : line, style: _codeStyle),
          textDirection: TextDirection.ltr,
          maxLines: null,
        ).let((tp) {
          tp.layout(maxWidth: contentWidth);
          return tp.computeLineMetrics().length.clamp(1, 99999);
        }),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final divider = widget.isDark
        ? Colors.white.withValues(alpha: 0.06)
        : const Color(0xFFEFEFEF);
    return Container(
      width: double.infinity,
      color: Colors.transparent,
      child: LayoutBuilder(
        builder: (context, c) {
          // 代码框实际文字区宽度 = 总宽 − 行号列 − 分隔线 − 代码框左右内边距
          final contentWidth = (c.maxWidth - _gutterW - 0.5 - 24).clamp(
            40.0,
            double.infinity,
          );
          final visual = _measureVisualLines(contentWidth);
          final totalVisual = visual.fold<int>(0, (a, v) => a + v);
          final contentHeight = _padV * 2 + totalVisual * _lineHeight;
          final boxHeight = contentHeight.clamp(_padV * 2 + _lineHeight, _maxH);
          return SizedBox(
            height: boxHeight,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildGutter(visual, divider),
                Expanded(
                  child: Focus(
                    onKeyEvent: (node, event) => _handleBackspace(event),
                    child: TextField(
                      controller: widget.controller,
                      focusNode: widget.focusNode,
                      scrollController: _codeScroll,
                      maxLines: null,
                      expands: true,
                      onTap: widget.onTap,
                      // 代码框关掉 iOS 智能标点/自动纠错——否则直引号会被替换成弯
                      // 引号（' " → ' ' " "）、连字符变破折号，粘进 Python/SQL
                      // 直接语法报错
                      autocorrect: false,
                      enableSuggestions: false,
                      smartDashesType: SmartDashesType.disabled,
                      smartQuotesType: SmartQuotesType.disabled,
                      keyboardType: TextInputType.multiline,
                      textAlignVertical: TextAlignVertical.top,
                      style: _codeStyle,
                      decoration: InputDecoration(
                        // filled:false 显式关掉——否则会吃全局 InputDecorationTheme
                        // 的 filled:true 灰底，代码块正文区就跟 markdown/latex 的
                        // 白底不一致了
                        filled: false,
                        border: InputBorder.none,
                        isDense: true,
                        contentPadding: const EdgeInsets.fromLTRB(
                          12,
                          _padV,
                          12,
                          _padV,
                        ),
                        hintText: NotebookCodeCellBody.hintFor(widget.cellType),
                        hintStyle: TextStyle(
                          fontFamily: 'monospace',
                          fontSize: _fontSize,
                          color: widget.isDark
                              ? const Color(0xFF444444)
                              : const Color(0xFFCCCCCC),
                        ),
                      ),
                      onChanged: widget.onChanged,
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  // 行号列：跟代码框逐行对齐（多视觉行的逻辑行只在首行标号，其余留空）。
  // 顶部留一段 = 代码框 contentPadding.top，保证 1 号行对齐第一行代码
  Widget _buildGutter(List<int> visual, Color divider) {
    final numColor = widget.isDark
        ? const Color(0xFF565B70)
        : const Color(0xFFBFC2CC);
    return Container(
      width: _gutterW,
      decoration: BoxDecoration(
        color: widget.isDark
            ? Colors.white.withValues(alpha: 0.02)
            : const Color(0xFFFAFAFB),
        border: Border(right: BorderSide(color: divider, width: 0.5)),
      ),
      child: SingleChildScrollView(
        controller: _gutterScroll,
        physics: const NeverScrollableScrollPhysics(),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: _padV),
            for (int i = 0; i < visual.length; i++)
              SizedBox(
                height: _lineHeight * visual[i],
                child: Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Text(
                    '${i + 1}',
                    textAlign: TextAlign.right,
                    maxLines: 1,
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: _fontSize,
                      height: 1.7,
                      color: numColor,
                    ),
                  ),
                ),
              ),
            const SizedBox(height: _padV),
          ],
        ),
      ),
    );
  }
}

// TextPainter 没有链式返回，借个小扩展让上面的测量写成表达式
extension _Let<T> on T {
  R let<R>(R Function(T) f) => f(this);
}
