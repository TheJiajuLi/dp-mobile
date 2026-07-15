import 'package:flutter/material.dart';

// 创作者中心（作品管理 / 专栏管理）通用的底部弹层组件——图标方框 + 主标题
// + 副标题的操作行，以及「危险确认」弹层。两个页面共用同一套视觉语言，
// 不各写一遍。
const _danger = Color(0xFFEF4444);

Color _sheetBg(BuildContext c) => Theme.of(c).cardColor;
bool _isDark(BuildContext c) => Theme.of(c).brightness == Brightness.dark;
Color _ink(BuildContext c) =>
    _isDark(c) ? const Color(0xFFF0F2F8) : const Color(0xFF1A1A1A);
Color _muted(BuildContext c) =>
    _isDark(c) ? const Color(0xFF7A80A0) : const Color(0xFF888888);

Widget _grabber() => Center(
  child: Container(
    width: 36,
    height: 4,
    margin: const EdgeInsets.only(bottom: 16),
    decoration: BoxDecoration(
      color: Colors.grey.withValues(alpha: 0.4),
      borderRadius: BorderRadius.circular(99),
    ),
  ),
);

// 操作菜单弹层：标题 + 一列 CreatorSheetItem
Future<T?> showCreatorActionSheet<T>(
  BuildContext context, {
  required String title,
  required List<Widget> children,
}) {
  return showModalBottomSheet<T>(
    context: context,
    backgroundColor: Colors.transparent,
    builder: (ctx) => Container(
      decoration: BoxDecoration(
        color: _sheetBg(ctx),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
      ),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _grabber(),
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
              child: Text(
                title,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: _ink(ctx),
                ),
              ),
            ),
            ...children,
          ],
        ),
      ),
    ),
  );
}

class CreatorSheetItem extends StatelessWidget {
  final IconData icon;
  final Color accent;
  final String label;
  final String? sub;
  final VoidCallback onTap;
  final bool isRed;

  const CreatorSheetItem({
    super.key,
    required this.icon,
    required this.accent,
    required this.label,
    this.sub,
    required this.onTap,
    this.isRed = false,
  });

  @override
  Widget build(BuildContext context) {
    final dark = _isDark(context);
    final a = isRed ? _danger : accent;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
        child: Row(
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: a.withValues(alpha: dark ? 0.2 : 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: a, size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: isRed ? _danger : _ink(context),
                    ),
                  ),
                  if (sub != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      sub!,
                      style: TextStyle(fontSize: 12, color: _muted(context)),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// 轻量结果提示——替代默认那条铺满全宽的纯色 SnackBar。浮动居中的圆角
// 胶囊：卡片底 + 成功绿/失败红图标 + 柔和阴影，跟全站卡片语言一致
void showCreatorToast(BuildContext context, String message, {bool ok = false}) {
  final dark = _isDark(context);
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
                color: ok ? const Color(0xFF16A34A) : const Color(0xFFEF4444),
              ),
              const SizedBox(width: 10),
              Flexible(
                child: Text(
                  message,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: _ink(context),
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

Widget creatorSheetDivider(BuildContext context) => Divider(
  height: 12,
  thickness: 0.5,
  color: _isDark(context)
      ? Colors.white.withValues(alpha: 0.08)
      : const Color(0xFFF0F0F0),
);

// 危险/确认弹层：标题 + 说明 + 主按钮（可危险红底）+ 取消
Future<bool> showCreatorConfirmSheet(
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
      final dark = _isDark(ctx);
      return Container(
        decoration: BoxDecoration(
          color: _sheetBg(ctx),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _grabber(),
              Text(
                title,
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: _ink(ctx),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                message,
                style: TextStyle(fontSize: 14, height: 1.6, color: _muted(ctx)),
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
                    style: TextStyle(fontSize: 15, color: _muted(ctx)),
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
