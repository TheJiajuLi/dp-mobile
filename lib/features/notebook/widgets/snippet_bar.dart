import 'package:flutter/material.dart';

import '../models/notebook_language.dart';

// 纯展示组件——onInsert 具体怎么把 code 塞进编辑器由调用方决定（真实
// 场景里是 evaluateJavascript(window.ins(code)) 捅进 CodeMirror WebView，
// 不是绑一个 TextEditingController，因为真正的输入焦点在 WebView 里）
class SnippetBar extends StatelessWidget {
  final NotebookLanguage language;
  final void Function(String code) onInsert;

  const SnippetBar({super.key, required this.language, required this.onInsert});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final dividerColor = isDark
        ? Colors.white.withValues(alpha: 0.06)
        : const Color(0xFFEBEBEB);

    return Container(
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: dividerColor, width: 0.5)),
      ),
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            language.snippetLabel,
            style: TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.w600,
              letterSpacing: .08,
              color: isDark
                  ? Colors.white.withValues(alpha: 0.25)
                  : const Color(0xFFC5C5CC),
            ),
          ),
          const SizedBox(height: 6),
          SizedBox(
            height: 30,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: language.snippets.length,
              separatorBuilder: (_, _) => const SizedBox(width: 6),
              itemBuilder: (ctx, i) {
                final snip = language.snippets[i];
                return _SnipChip(
                  label: snip.label,
                  onTap: () => onInsert(snip.code),
                  isDark: isDark,
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _SnipChip extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  final bool isDark;

  const _SnipChip({required this.label, required this.onTap, required this.isDark});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: isDark
              ? Colors.white.withValues(alpha: 0.05)
              : const Color(0xFFF5F5F5),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isDark
                ? Colors.white.withValues(alpha: 0.08)
                : const Color(0xFFE5E5E5),
            width: 0.5,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontFamily: 'Menlo',
            color: isDark
                ? Colors.white.withValues(alpha: 0.55)
                : const Color(0xFF555555),
          ),
        ),
      ),
    );
  }
}
