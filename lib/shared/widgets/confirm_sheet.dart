import 'package:flutter/material.dart';

// 全站统一的「危险/确认」底部弹层——替代系统默认的居中 AlertDialog，跟
// 全站卡片语言一致：圆角抓手 + 标题 + 说明 + 主按钮（危险时红底红字）+
// 取消。返回 bool（确认 true / 取消或点空白 false）。
const _danger = Color(0xFFEF4444);

Future<bool> showConfirmSheet(
  BuildContext context, {
  required String title,
  required String message,
  required String confirmLabel,
  bool isDanger = false,
  String cancelLabel = '取消',
}) async {
  final res = await showModalBottomSheet<bool>(
    context: context,
    backgroundColor: Colors.transparent,
    builder: (ctx) {
      final dark = Theme.of(ctx).brightness == Brightness.dark;
      final ink = dark ? const Color(0xFFF0F2F8) : const Color(0xFF1A1A1A);
      final muted = dark ? const Color(0xFF7A80A0) : const Color(0xFF888888);
      return Container(
        decoration: BoxDecoration(
          color: Theme.of(ctx).cardColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: Colors.grey.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
              ),
              Text(
                title,
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: ink,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                message,
                style: TextStyle(fontSize: 14, height: 1.6, color: muted),
              ),
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                child: TextButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  style: TextButton.styleFrom(
                    backgroundColor: isDanger
                        ? (dark
                              ? _danger.withValues(alpha: 0.16)
                              : const Color(0xFFFEF2F2))
                        : const Color(0xFF1A1A1A),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: isDanger
                          ? BorderSide(
                              color: dark
                                  ? _danger.withValues(alpha: 0.4)
                                  : const Color(0xFFFECACA),
                              width: 0.5,
                            )
                          : BorderSide.none,
                    ),
                  ),
                  child: Text(
                    confirmLabel,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: isDanger ? _danger : Colors.white,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  style: TextButton.styleFrom(
                    backgroundColor: dark
                        ? Colors.white.withValues(alpha: 0.06)
                        : const Color(0xFFF5F5F5),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: Text(
                    cancelLabel,
                    style: TextStyle(fontSize: 15, color: muted),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
  return res ?? false;
}
