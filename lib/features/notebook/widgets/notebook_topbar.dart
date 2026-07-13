import 'package:flutter/material.dart';

class NotebookTopBar extends StatelessWidget {
  final String title;
  final bool isRunning;
  final VoidCallback onBack;
  final VoidCallback onSave;
  final VoidCallback onRunAll;

  const NotebookTopBar({
    super.key,
    required this.title,
    required this.isRunning,
    required this.onBack,
    required this.onSave,
    required this.onRunAll,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final divColor = isDark
        ? Colors.white.withValues(alpha: 0.08)
        : const Color(0xFFEBEBEB);
    final btnBg = isDark
        ? Colors.white.withValues(alpha: 0.06)
        : const Color(0xFFF0F0F0);
    final btnBorder = isDark
        ? Colors.white.withValues(alpha: 0.1)
        : const Color(0xFFE5E5E5);
    final iconColor = isDark
        ? Colors.white.withValues(alpha: 0.6)
        : const Color(0xFF555555);
    final runBg = isDark ? const Color(0xFF6366F1) : const Color(0xFF1A1A1A);

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 8),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: divColor, width: 0.5)),
      ),
      child: Row(
        children: [
          GestureDetector(
            onTap: onBack,
            child: Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                color: btnBg,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: btnBorder, width: 0.5),
              ),
              child: Icon(Icons.chevron_left, size: 20, color: iconColor),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              title,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: isDark
                    ? Colors.white.withValues(alpha: 0.9)
                    : const Color(0xFF1A1A1A),
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: onSave,
            child: Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                color: btnBg,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: btnBorder, width: 0.5),
              ),
              child: Icon(Icons.save_outlined, size: 16, color: iconColor),
            ),
          ),
          const SizedBox(width: 6),
          GestureDetector(
            onTap: isRunning ? null : onRunAll,
            child: Container(
              height: 30,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: runBg,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  isRunning
                      ? const SizedBox(
                          width: 12,
                          height: 12,
                          child: CircularProgressIndicator(
                            strokeWidth: 1.5,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(
                          Icons.play_arrow,
                          size: 14,
                          color: Colors.white,
                        ),
                  const SizedBox(width: 4),
                  Text(
                    isRunning ? '运行中' : '运行',
                    style: const TextStyle(
                      fontSize: 12,
                      color: Colors.white,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
