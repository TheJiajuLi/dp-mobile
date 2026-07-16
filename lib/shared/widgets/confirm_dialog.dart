import 'package:flutter/material.dart';

// 全站统一的「危险操作」二次确认弹窗——红底警示图标 + 圆角卡片 + 取消(幽灵)/
// 确认(红色实心)，跟注销账号那套一致。返回 true=确认、false/dismiss=取消。
// 别再在各页各手搓一份 AlertDialog
Future<bool> showDangerConfirm(
  BuildContext context, {
  required String title,
  required String message,
  String confirmText = '删除',
  String cancelText = '取消',
}) async {
  const danger = Color(0xFFDC2626);
  final result = await showDialog<bool>(
    context: context,
    builder: (ctx) {
      final isDark = Theme.of(ctx).brightness == Brightness.dark;
      final ink = isDark ? const Color(0xFFF0F2F8) : const Color(0xFF1A1A1A);
      final muted = isDark ? Colors.white70 : const Color(0xFF6B7280);
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
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: danger.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.warning_amber_rounded,
                  color: danger,
                  size: 24,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                title,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: ink,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                message,
                style: TextStyle(fontSize: 14, height: 1.55, color: muted),
              ),
              const SizedBox(height: 22),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(ctx, false),
                    child: Text(
                      cancelText,
                      style: TextStyle(color: muted, fontSize: 15),
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: () => Navigator.pop(ctx, true),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: danger,
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
  return result ?? false;
}
