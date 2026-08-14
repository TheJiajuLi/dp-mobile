import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';

// 全站统一的轻量结果提示——浮动居中的圆角胶囊：卡片底 + 成功绿/失败红
// 图标 + 柔和阴影，替代默认那条铺满全宽的纯色 SnackBar，跟全站卡片语言
// 一致。ok=true 显示绿色对勾，否则红色感叹号。
void showAppToast(BuildContext context, String message, {bool ok = false}) {
  final dark = Theme.of(context).brightness == Brightness.dark;
  final ink = dark ? const Color(0xFFF0F2F8) : const Color(0xFF1A1A1A);
  final messenger = ScaffoldMessenger.of(context);
  messenger.hideCurrentSnackBar();
  messenger.showSnackBar(
    SnackBar(
      behavior: SnackBarBehavior.floating,
      backgroundColor: Colors.transparent,
      elevation: 0,
      duration: const Duration(milliseconds: 1800),
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 20),
      padding: EdgeInsets.zero,
      content: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: dark ? const Color(0xFF23262E) : Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: dark
                ? Border.all(
                    color: Colors.white.withValues(alpha: 0.08),
                    width: 0.5,
                  )
                : null,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: dark ? 0.3 : 0.12),
                blurRadius: 20,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                ok ? Icons.check_circle_rounded : Icons.error_outline_rounded,
                size: 18,
                color: ok ? AppColors.success : const Color(0xFFEF4444),
              ),
              const SizedBox(width: 10),
              Flexible(
                child: Text(
                  message,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: ink,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
