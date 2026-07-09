import 'package:flutter/material.dart';

// 纯展示组件——方向键跟符号键都是回调，具体怎么作用到编辑器（WebView里的
// CodeMirror）由调用方决定
class KeyboardToolbar extends StatelessWidget {
  final void Function(String) onInsert;
  final VoidCallback onMoveUp;
  final VoidCallback onMoveDown;

  const KeyboardToolbar({
    super.key,
    required this.onInsert,
    required this.onMoveUp,
    required this.onMoveDown,
  });

  static const _keys = [
    ('(', '('),
    (')', ')'),
    ('[', '['),
    (']', ']'),
    (':', ':'),
    ('=', '='),
    ('.', '.'),
    ('"', '"'),
  ];

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      height: 40,
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(
            color: isDark
                ? Colors.white.withValues(alpha: 0.06)
                : const Color(0xFFEBEBEB),
            width: 0.5,
          ),
        ),
      ),
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        children: [
          _KbdKey('⇥', isDark, onTap: () => onInsert('\t')),
          Container(
            width: 0.5,
            margin: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            color: isDark ? Colors.white.withValues(alpha: 0.1) : const Color(0xFFE0E0E0),
          ),
          _KbdKey('↑', isDark, onTap: onMoveUp),
          _KbdKey('↓', isDark, onTap: onMoveDown),
          Container(
            width: 0.5,
            margin: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            color: isDark ? Colors.white.withValues(alpha: 0.1) : const Color(0xFFE0E0E0),
          ),
          ..._keys.map((k) => _KbdKey(k.$1, isDark, onTap: () => onInsert(k.$2))),
        ],
      ),
    );
  }
}

class _KbdKey extends StatelessWidget {
  final String label;
  final bool isDark;
  final VoidCallback onTap;

  const _KbdKey(this.label, this.isDark, {required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(right: 5),
        padding: EdgeInsets.symmetric(
          horizontal: label.length > 1 ? 12 : 8,
          vertical: 4,
        ),
        decoration: BoxDecoration(
          color: isDark ? Colors.white.withValues(alpha: 0.07) : const Color(0xFFF0F0F0),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: isDark ? Colors.white.withValues(alpha: 0.1) : const Color(0xFFE0E0E0),
            width: 0.5,
          ),
          boxShadow: isDark
              ? null
              : const [BoxShadow(color: Color(0x15000000), offset: Offset(0, 1), blurRadius: 0)],
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontFamily: 'Menlo',
            color: isDark ? Colors.white.withValues(alpha: 0.6) : const Color(0xFF555555),
          ),
        ),
      ),
    );
  }
}
