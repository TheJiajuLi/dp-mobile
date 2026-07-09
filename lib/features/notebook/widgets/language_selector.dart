import 'package:flutter/material.dart';

import '../models/notebook_language.dart';

class LanguageSelector extends StatelessWidget {
  final NotebookLanguage current;
  final void Function(NotebookLanguage) onChanged;

  const LanguageSelector({
    super.key,
    required this.current,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      height: 44,
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: isDark
                ? Colors.white.withValues(alpha: 0.06)
                : const Color(0xFFEBEBEB),
            width: 0.5,
          ),
        ),
      ),
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        children: NotebookLanguage.values
            .map(
              (lang) => _LangPill(
                lang: lang,
                isSelected: lang == current,
                onTap: () => onChanged(lang),
              ),
            )
            .toList(),
      ),
    );
  }
}

class _LangPill extends StatelessWidget {
  final NotebookLanguage lang;
  final bool isSelected;
  final VoidCallback onTap;

  const _LangPill({
    required this.lang,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        margin: const EdgeInsets.only(right: 6),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: isSelected
              ? const Color(0xFF6366F1).withValues(alpha: 0.12)
              : isDark
              ? Colors.white.withValues(alpha: 0.04)
              : const Color(0xFFF5F5F5),
          borderRadius: BorderRadius.circular(99),
          border: Border.all(
            color: isSelected
                ? const Color(0xFF6366F1).withValues(alpha: 0.6)
                : isDark
                ? Colors.white.withValues(alpha: 0.08)
                : const Color(0xFFE5E5E5),
            width: 0.5,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(
                color: lang.dotColor,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 5),
            Text(
              lang.displayName,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: isSelected
                    ? const Color(0xFF818CF8)
                    : isDark
                    ? Colors.white.withValues(alpha: 0.5)
                    : const Color(0xFF888888),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
