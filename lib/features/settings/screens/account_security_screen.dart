import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/network/api_client.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../../shared/widgets/app_toast.dart';
import '../../auth/auth_service.dart';
import '../widgets/settings_row.dart';

class AccountSecurityScreen extends ConsumerWidget {
  const AccountSecurityScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      // 顶栏跟页面背景统一用 scaffoldBackgroundColor，不再用 cardColor——
      // 之前顶栏+下面三行列表都套了一层 cardColor（浅色下是白），跟再往下
      // 的 scaffoldBackgroundColor（浅灰）撞出一块"白色色块贴灰色背景"的
      // 接缝。整页统一成一个背景色，组内三行改靠分割线区分，不再靠单独的
      // 色块框出一张"卡片"
      appBar: AppBar(
        title: Text(l10n.accountSecurity),
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        foregroundColor: Theme.of(context).textTheme.bodyLarge?.color,
        elevation: 0,
      ),
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: ListView(
        children: [
          const SizedBox(height: 8),
          // 跟隐私设置/设置页一样，收进浮在页面背景上的圆角卡片（16 圆角 +
          // 组内分割线），对齐当前视觉语言，不再是贴边到底的扁平列表
          SettingsGroup([
            SettingsRow(
              icon: Icons.lock_outline,
              iconColor: Colors.grey,
              iconBg: Theme.of(context).dividerColor,
              title: l10n.changePassword,
              subtitle: l10n.changePasswordSubtitle,
              onTap: () => _showChangePassword(context, ref),
            ),
            SettingsRow(
              icon: Icons.history,
              iconColor: Colors.grey,
              iconBg: Theme.of(context).dividerColor,
              title: l10n.loginHistory,
              subtitle: l10n.loginHistorySubtitle,
              onTap: () => context.push('/settings/security/history'),
            ),
            SettingsRow(
              icon: Icons.person_remove_outlined,
              iconColor: const Color(0xFFDC2626),
              iconBg: const Color(0xFFFEE2E2),
              title: l10n.deleteAccount,
              titleColor: const Color(0xFFDC2626),
              subtitle: l10n.deleteAccountSubtitle,
              onTap: () => _showDeleteAccount(context, ref),
            ),
          ]),
        ],
      ),
    );
  }

  void _showChangePassword(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final oldCtrl = TextEditingController();
    final newCtrl = TextEditingController();
    final confirmCtrl = TextEditingController();
    bool saving = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) {
          Future<void> submit() async {
            if (oldCtrl.text.isEmpty || newCtrl.text.isEmpty) {
              ScaffoldMessenger.of(
                ctx,
              ).showSnackBar(SnackBar(content: Text(l10n.fillAllFields)));
              return;
            }
            if (newCtrl.text.length < 6) {
              ScaffoldMessenger.of(ctx).showSnackBar(
                SnackBar(content: Text(l10n.registerErrorPasswordTooShort)),
              );
              return;
            }
            if (newCtrl.text != confirmCtrl.text) {
              ScaffoldMessenger.of(
                ctx,
              ).showSnackBar(SnackBar(content: Text(l10n.newPasswordMismatch)));
              return;
            }

            setSheetState(() => saving = true);
            // 实测 /auth/change-password 目前是 404，后端还没做这个接口——
            // 真上线后这里会自动走真实的成功/失败分支，不用等接口就绪再改代码
            final res = await ref
                .read(apiClientProvider)
                .post(
                  '/auth/change-password',
                  data: {
                    'oldPassword': oldCtrl.text,
                    'newPassword': newCtrl.text,
                  },
                );
            if (!ctx.mounted) return;
            setSheetState(() => saving = false);

            if (res.success) {
              Navigator.pop(ctx);
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(l10n.passwordChangeSuccess)),
                );
              }
            } else if (res.statusCode == 404) {
              Navigator.pop(ctx);
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(l10n.changePasswordComingSoon)),
                );
              }
            } else {
              ScaffoldMessenger.of(ctx).showSnackBar(
                SnackBar(content: Text(res.message ?? l10n.changeFailedRetry)),
              );
            }
          }

          return Container(
            decoration: BoxDecoration(
              color: Theme.of(ctx).cardColor,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(20),
              ),
            ),
            padding: EdgeInsets.fromLTRB(
              20,
              20,
              20,
              MediaQuery.of(ctx).viewInsets.bottom + 20,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  l10n.changePassword,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: oldCtrl,
                  obscureText: true,
                  decoration: InputDecoration(
                    labelText: l10n.currentPasswordLabel,
                    border: const OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: newCtrl,
                  obscureText: true,
                  decoration: InputDecoration(
                    labelText: l10n.newPasswordLabel,
                    border: const OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: confirmCtrl,
                  obscureText: true,
                  decoration: InputDecoration(
                    labelText: l10n.confirmNewPasswordLabel,
                    border: const OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF6366F1),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    onPressed: saving ? null : submit,
                    child: saving
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : Text(
                            l10n.save,
                            style: const TextStyle(color: Colors.white),
                          ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  void _showDeleteAccount(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    const danger = Color(0xFFDC2626);
    showDialog(
      context: context,
      builder: (ctx) {
        final isDark = Theme.of(ctx).brightness == Brightness.dark;
        final ink = isDark ? const Color(0xFFF0F2F8) : const Color(0xFF1A1A1A);
        final muted = isDark ? Colors.white70 : const Color(0xFF6B7280);
        return Dialog(
          backgroundColor: isDark ? const Color(0xFF1C1D24) : Colors.white,
          insetPadding: const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(22),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(22, 22, 22, 14),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 危险警示图标——红底柔光方块，一眼看出是不可逆操作
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
                  l10n.deleteAccount,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: ink,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  l10n.deleteAccountWarning,
                  style: TextStyle(fontSize: 14, height: 1.55, color: muted),
                ),
                const SizedBox(height: 22),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: Text(
                        l10n.cancel,
                        style: TextStyle(color: muted, fontSize: 15),
                      ),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton(
                      onPressed: () async {
                        Navigator.pop(ctx);
                        // 实测 /auth/account 目前是 404，后端还没做这个接口——
                        // 真上线后这里会自动走真实的删除+登出流程，不用等接口
                        // 就绪再改代码
                        final res = await ref
                            .read(apiClientProvider)
                            .delete('/auth/account');
                        if (res.success) {
                          final userId = ref.read(currentUserProvider)?.id;
                          await ref.read(authServiceProvider).logout();
                          // 只清这个账号自己的本地数据（星座/链接/登录记录/
                          // 隐私开关/Notebook 本地文档/社区分页缓存，都是
                          // '${userId}_' 前缀）。不能用 prefs.clear()——那会把
                          // 设备上其它账号的数据、以及主题/字体/通知这些全局
                          // App 设置也一起清掉
                          if (userId != null && userId.isNotEmpty) {
                            final prefs = await SharedPreferences.getInstance();
                            final keys = prefs.getKeys().where(
                              (k) => k.startsWith('${userId}_'),
                            );
                            for (final key in keys.toList()) {
                              await prefs.remove(key);
                            }
                          }
                          if (context.mounted) {
                            context.go('/login');
                            showAppToast(context, l10n.accountDeleted, ok: true);
                          }
                          return;
                        }
                        if (!context.mounted) return;
                        showAppToast(
                          context,
                          res.statusCode == 404
                              ? l10n.deleteAccountComingSoon
                              : l10n.deleteFailedRetry,
                        );
                      },
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
                        l10n.confirmDeletion,
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
  }
}
