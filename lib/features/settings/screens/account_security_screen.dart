import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';

class AccountSecurityScreen extends ConsumerWidget {
  const AccountSecurityScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('账号安全'),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
      ),
      backgroundColor: const Color(0xFFF8F8F8),
      body: ListView(
        children: [
          const SizedBox(height: 8),
          Container(
            color: Colors.white,
            child: Column(
              children: [
                _SecurityRow(
                  title: '修改密码',
                  subtitle: '定期更换密码保护账号安全',
                  onTap: () => _showChangePassword(context, ref),
                ),
                _SecurityRow(
                  title: '登录记录',
                  subtitle: '查看最近的登录设备和时间',
                  onTap: () => ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('登录记录即将上线，敬请期待')),
                  ),
                ),
                _SecurityRow(
                  title: '注销账号',
                  subtitle: '永久删除账号和所有数据',
                  titleColor: const Color(0xFFDC2626),
                  onTap: () => _showDeleteAccount(context),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showChangePassword(BuildContext context, WidgetRef ref) {
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
              ).showSnackBar(const SnackBar(content: Text('请填写完整')));
              return;
            }
            if (newCtrl.text != confirmCtrl.text) {
              ScaffoldMessenger.of(
                ctx,
              ).showSnackBar(const SnackBar(content: Text('两次输入的新密码不一致')));
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
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(const SnackBar(content: Text('密码修改成功')));
              }
            } else if (res.statusCode == 404) {
              Navigator.pop(ctx);
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('修改密码功能即将上线，敬请期待')),
                );
              }
            } else {
              ScaffoldMessenger.of(ctx).showSnackBar(
                SnackBar(content: Text(res.message ?? '修改失败，请重试')),
              );
            }
          }

          return Container(
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
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
                const Text(
                  '修改密码',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: oldCtrl,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: '当前密码',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: newCtrl,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: '新密码',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: confirmCtrl,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: '确认新密码',
                    border: OutlineInputBorder(),
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
                        : const Text(
                            '保存',
                            style: TextStyle(color: Colors.white),
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

  void _showDeleteAccount(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('注销账号'),
        content: const Text('注销后所有数据将永久删除，无法恢复。确定要继续吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('注销账号功能即将上线，敬请期待')),
              );
            },
            child: const Text('注销', style: TextStyle(color: Color(0xFFDC2626))),
          ),
        ],
      ),
    );
  }
}

class _SecurityRow extends StatelessWidget {
  final String title;
  final String subtitle;
  final Color? titleColor;
  final VoidCallback onTap;

  const _SecurityRow({
    required this.title,
    required this.subtitle,
    this.titleColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => ListTile(
    title: Text(title, style: TextStyle(color: titleColor ?? const Color(0xFF1C1C1E))),
    subtitle: Text(subtitle, style: const TextStyle(fontSize: 12, color: Colors.grey)),
    trailing: const Icon(Icons.chevron_right, color: Colors.grey),
    onTap: onTap,
  );
}
