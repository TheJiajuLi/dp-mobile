import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';

const _danger = Color(0xFFDC2626);

// 统一的"确认删除"卡片——原来云端存储页三处删除（单个文件/教程/清空
// 分类）各自一份 AlertDialog，是纯 Material 默认样式（居中弹窗、方角、
// 左右两个 Button），跟极梦其它页面已经统一的"底部圆角sheet+图标胶囊+
// 大号操作按钮"这套视觉语言不是一回事。抽成一个共用的底部sheet，红色
// 图标徽章+居中文案+全宽删除/取消按钮，跟系统原生删除确认（比如相册
// 删除照片）同一个思路，三处调用方只传各自的文案，样式统一维护一份
Future<bool> showDeleteConfirmSheet(
  BuildContext context, {
  required String title,
  required String message,
  String? infoLine,
  Color? infoLineColor,
  String? warningLine,
  Color? warningLineColor,
  required String confirmLabel,
  required String cancelLabel,
}) async {
  final result = await showModalBottomSheet<bool>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (ctx) => _DeleteConfirmSheet(
      title: title,
      message: message,
      infoLine: infoLine,
      infoLineColor: infoLineColor,
      warningLine: warningLine,
      warningLineColor: warningLineColor,
      confirmLabel: confirmLabel,
      cancelLabel: cancelLabel,
    ),
  );
  return result ?? false;
}

class _DeleteConfirmSheet extends StatelessWidget {
  final String title;
  final String message;
  final String? infoLine;
  final Color? infoLineColor;
  final String? warningLine;
  final Color? warningLineColor;
  final String confirmLabel;
  final String cancelLabel;

  const _DeleteConfirmSheet({
    required this.title,
    required this.message,
    required this.infoLine,
    required this.infoLineColor,
    required this.warningLine,
    required this.warningLineColor,
    required this.confirmLabel,
    required this.cancelLabel,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final ink = isDark ? AppColors.darkTextPrimary : const Color(0xFF1A1A1A);
    final muted = isDark
        ? AppColors.darkTextSecondary
        : const Color(0xFF888888);

    return Container(
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkCard : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(bottom: 20),
                decoration: BoxDecoration(
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.15)
                      : const Color(0xFFE5E5EA),
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: _danger.withValues(alpha: isDark ? 0.16 : 0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.delete_outline,
                  color: _danger,
                  size: 26,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                title,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: ink,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                message,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14, height: 1.5, color: muted),
              ),
              if (infoLine != null) ...[
                const SizedBox(height: 10),
                Text(
                  infoLine!,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: infoLineColor ?? const Color(0xFF16A34A),
                  ),
                ),
              ],
              if (warningLine != null) ...[
                const SizedBox(height: 6),
                Text(
                  warningLine!,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 12,
                    color: warningLineColor ?? muted,
                  ),
                ),
              ],
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: GestureDetector(
                  onTap: () => Navigator.pop(context, true),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    decoration: BoxDecoration(
                      color: _danger,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Text(
                      confirmLabel,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: GestureDetector(
                  onTap: () => Navigator.pop(context, false),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    decoration: BoxDecoration(
                      color: isDark
                          ? Colors.white.withValues(alpha: 0.06)
                          : const Color(0xFFF5F5F7),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Text(
                      cancelLabel,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: ink,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
