import 'package:flutter/material.dart';

class AddCellBar extends StatelessWidget {
  final VoidCallback onAddCode;
  final VoidCallback onAddText;
  final VoidCallback onAddLatex;

  const AddCellBar({
    super.key,
    required this.onAddCode,
    required this.onAddText,
    required this.onAddLatex,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(
            color: isDark ? Colors.white.withValues(alpha: 0.04) : const Color(0xFFEBEBEB),
            width: 0.5,
          ),
        ),
      ),
      child: Row(
        children: [
          _AddBtn(icon: Icons.add, label: '代码', onTap: onAddCode, isDark: isDark),
          const SizedBox(width: 8),
          _AddBtn(icon: Icons.notes, label: '文本', onTap: onAddText, isDark: isDark),
          const SizedBox(width: 8),
          _AddBtn(icon: Icons.functions, label: 'LaTeX', onTap: onAddLatex, isDark: isDark),
        ],
      ),
    );
  }
}

class _AddBtn extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool isDark;

  const _AddBtn({
    required this.icon,
    required this.label,
    required this.onTap,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: isDark ? Colors.white.withValues(alpha: 0.04) : const Color(0xFFF8F8F8),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isDark ? Colors.white.withValues(alpha: 0.12) : const Color(0xFFE0E0E0),
              width: 0.5,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 13,
                color: isDark ? Colors.white.withValues(alpha: 0.4) : const Color(0xFFAAAAAA),
              ),
              const SizedBox(width: 5),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  color: isDark ? Colors.white.withValues(alpha: 0.4) : const Color(0xFFAAAAAA),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
