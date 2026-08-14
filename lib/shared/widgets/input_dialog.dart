import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';

// 全站统一的「文本输入」弹窗——圆角卡片 + 品牌紫聚焦输入框 + 字数计数 +
// 取消(幽灵)/保存(紫色实心)，跟 showDangerConfirm 同一套视觉语言。返回
// 输入的字符串（已 trim）；取消/dismiss 返回 null。别再各页手搓 AlertDialog。
const _primary = AppColors.primary;

Future<String?> showInputDialog(
  BuildContext context, {
  required String title,
  String initial = '',
  String? hint,
  int maxLength = 50,
  int maxLines = 1,
  String confirmText = '保存',
  String cancelText = '取消',
}) async {
  final ctrl = TextEditingController(text: initial);
  final result = await showDialog<String>(
    context: context,
    builder: (ctx) {
      final isDark = Theme.of(ctx).brightness == Brightness.dark;
      final ink = isDark ? const Color(0xFFF0F2F8) : const Color(0xFF1A1A1A);
      final muted = isDark ? Colors.white70 : const Color(0xFF6B7280);
      final fieldBg = isDark ? Colors.white.withValues(alpha: 0.05) : const Color(0xFFF7F7F9);
      final fieldBorder = isDark
          ? Colors.white.withValues(alpha: 0.08)
          : const Color(0xFFE5E5EA);
      return Dialog(
        backgroundColor: isDark ? const Color(0xFF1C1D24) : Colors.white,
        insetPadding: const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 22, 22, 14),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: ink,
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: ctrl,
                autofocus: true,
                maxLength: maxLength,
                maxLines: maxLines,
                minLines: maxLines > 1 ? maxLines : 1,
                style: TextStyle(fontSize: 15, color: ink),
                textInputAction: maxLines > 1
                    ? TextInputAction.newline
                    : TextInputAction.done,
                onSubmitted: maxLines > 1
                    ? null
                    : (v) => Navigator.pop(ctx, v.trim()),
                decoration: InputDecoration(
                  hintText: hint,
                  hintStyle: TextStyle(color: muted, fontSize: 14),
                  filled: true,
                  fillColor: fieldBg,
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 12,
                  ),
                  counterStyle: TextStyle(fontSize: 11, color: muted),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: fieldBorder, width: 0.5),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: fieldBorder, width: 0.5),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: _primary, width: 1.2),
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: Text(
                      cancelText,
                      style: TextStyle(color: muted, fontSize: 15),
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _primary,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 11,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: Text(
                      confirmText,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    },
  );
  ctrl.dispose();
  return result;
}
