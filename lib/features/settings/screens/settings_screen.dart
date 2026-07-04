import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/font_size_provider.dart';
import '../../../core/notification_provider.dart';
import '../../../core/theme_provider.dart';
import '../../auth/auth_service.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  static const _themeLabels = {
    ThemePreference.system: '跟随系统',
    ThemePreference.light: '浅色',
    ThemePreference.dark: '深色',
  };

  // double 重写了 ==/hashCode，不能作为 const map 的 key，这里用 final
  static final _fontSizeLabels = <double, String>{
    0.85: '小',
    1.0: '标准',
    1.15: '大',
    1.3: '超大',
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themePref = ref.watch(themeProvider);
    final fontSize = ref.watch(fontSizeProvider);

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(
        child: Column(
          children: [
            Container(
              color: Theme.of(context).cardColor,
              padding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 14,
              ),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: () => context.pop(),
                    child: const Icon(Icons.arrow_back_ios, size: 18),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '设置',
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      color: Theme.of(context).textTheme.bodyLarge?.color,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                children: [
                  const _SectionTitle('账号'),
                  _SettingsGroup([
                    _SettingsRow(
                      icon: Icons.shield_outlined,
                      iconColor: const Color(0xFF2563EB),
                      iconBg: const Color(0xFFE6F1FB),
                      title: '账号安全',
                      subtitle: '密码、登录记录',
                      onTap: () => context.push('/settings/security'),
                    ),
                    _SettingsRow(
                      icon: Icons.notifications_outlined,
                      iconColor: const Color(0xFF6366F1),
                      iconBg: const Color(0xFFEEF0FF),
                      title: '通知设置',
                      subtitle: '点赞、评论、关注',
                      onTap: () => showModalBottomSheet(
                        context: context,
                        builder: (_) => const _NotifSettingsSheet(),
                      ),
                    ),
                    _SettingsRow(
                      icon: Icons.lock_outlined,
                      iconColor: const Color(0xFF16A34A),
                      iconBg: const Color(0xFFE8F8F0),
                      title: '隐私',
                      subtitle: '谁可以看我的内容',
                      onTap: () => context.push('/settings/privacy'),
                    ),
                  ]),

                  const _SectionTitle('通用'),
                  _SettingsGroup([
                    _SettingsRow(
                      icon: Icons.palette_outlined,
                      iconColor: const Color(0xFFD97706),
                      iconBg: const Color(0xFFFFF7E6),
                      title: '主题',
                      trailing: _themeLabels[themePref],
                      onTap: () => _showThemePicker(context, ref),
                    ),
                    _SettingsRow(
                      icon: Icons.text_fields,
                      iconColor: const Color(0xFF6366F1),
                      iconBg: const Color(0xFFEEF0FF),
                      title: '字体大小',
                      trailing: _fontSizeLabels[fontSize] ?? '标准',
                      onTap: () => _showFontPicker(context, ref),
                    ),
                    _SettingsRow(
                      icon: Icons.language,
                      iconColor: const Color(0xFF2563EB),
                      iconBg: const Color(0xFFE6F1FB),
                      title: '语言',
                      trailing: '简体中文',
                      onTap: () => _todo(context, '多语言即将上线，敬请期待'),
                    ),
                    _SettingsRow(
                      icon: Icons.cloud_outlined,
                      iconColor: const Color(0xFF16A34A),
                      iconBg: const Color(0xFFE8F8F0),
                      title: '云端存储',
                      subtitle: '已用 234 MB / 1 GB',
                      onTap: () => context.push('/settings/storage'),
                    ),
                    _SettingsRow(
                      icon: Icons.delete_outline,
                      iconColor: Colors.grey,
                      iconBg: Theme.of(context).dividerColor,
                      title: '清除缓存',
                      onTap: () => _clearCache(context, ref),
                    ),
                  ]),

                  const _SectionTitle('会员中心'),
                  _SettingsGroup([
                    _SettingsRow(
                      icon: Icons.workspace_premium,
                      iconColor: const Color(0xFFD97706),
                      iconBg: const Color(0xFFFFF7E6),
                      title: '我的会员',
                      subtitle: '当前：免费版',
                      trailing: '升级 Pro',
                      trailingColor: const Color(0xFF6366F1),
                      onTap: () => context.push('/settings/subscription'),
                    ),
                    _SettingsRow(
                      icon: Icons.credit_card_outlined,
                      iconColor: const Color(0xFF2563EB),
                      iconBg: const Color(0xFFE6F1FB),
                      title: '支付方式',
                      subtitle: '管理绑定的支付方式',
                      onTap: () => context.push('/settings/payment'),
                    ),
                    _SettingsRow(
                      icon: Icons.receipt_long_outlined,
                      iconColor: const Color(0xFF16A34A),
                      iconBg: const Color(0xFFE8F8F0),
                      title: '订阅管理',
                      subtitle: '查看订阅记录',
                      onTap: () => context.push('/settings/subscription'),
                    ),
                  ]),

                  const _SectionTitle('创作'),
                  _SettingsGroup([
                    _SettingsRow(
                      icon: Icons.edit_note,
                      iconColor: const Color(0xFF6366F1),
                      iconBg: const Color(0xFFEEF0FF),
                      title: '创作中心',
                      subtitle: '管理教程、数据统计',
                      onTap: () => _todo(context, '创作中心即将上线，敬请期待'),
                    ),
                  ]),

                  const _SectionTitle('关于'),
                  _SettingsGroup([
                    _SettingsRow(
                      icon: Icons.info_outline,
                      iconColor: Colors.grey,
                      iconBg: Theme.of(context).dividerColor,
                      title: '关于极梦',
                      subtitle: 'v1.0.0',
                      onTap: () => context.push('/settings/about'),
                    ),
                    _SettingsRow(
                      icon: Icons.description_outlined,
                      iconColor: Colors.grey,
                      iconBg: Theme.of(context).dividerColor,
                      title: '用户协议',
                      onTap: () => context.push('/settings/about'),
                    ),
                    _SettingsRow(
                      icon: Icons.privacy_tip_outlined,
                      iconColor: Colors.grey,
                      iconBg: Theme.of(context).dividerColor,
                      title: '隐私政策',
                      onTap: () => context.push('/settings/about'),
                    ),
                  ]),

                  const _SectionTitle(''),
                  _SettingsGroup([
                    _SettingsRow(
                      icon: Icons.switch_account_outlined,
                      iconColor: const Color(0xFF2563EB),
                      iconBg: const Color(0xFFE6F1FB),
                      title: '切换账号',
                      onTap: () => _switchAccount(context, ref),
                    ),
                    _SettingsRow(
                      icon: Icons.logout,
                      iconColor: const Color(0xFFDC2626),
                      iconBg: const Color(0xFFFEF2F2),
                      title: '退出登录',
                      titleColor: const Color(0xFFDC2626),
                      onTap: () => _logout(context, ref),
                    ),
                  ]),

                  const SizedBox(height: 40),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _todo(BuildContext context, String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  void _showThemePicker(BuildContext context, WidgetRef ref) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: BoxDecoration(
          color: Theme.of(ctx).cardColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: const EdgeInsets.all(20),
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
              '主题',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: Theme.of(ctx).textTheme.bodyLarge?.color,
              ),
            ),
            const SizedBox(height: 16),
            Consumer(
              builder: (ctx, ref, _) {
                final current = ref.watch(themeProvider);
                return Column(
                  children: _themeLabels.entries
                      .map(
                        (e) => ListTile(
                          title: Text(e.value),
                          trailing: current == e.key
                              ? const Icon(Icons.check, color: Color(0xFF6366F1))
                              : null,
                          onTap: () {
                            ref.read(themeProvider.notifier).setTheme(e.key);
                            Navigator.pop(ctx);
                          },
                        ),
                      )
                      .toList(),
                );
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  void _showFontPicker(BuildContext context, WidgetRef ref) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: BoxDecoration(
          color: Theme.of(ctx).cardColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: const EdgeInsets.all(20),
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
              '字体大小',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: Theme.of(ctx).textTheme.bodyLarge?.color,
              ),
            ),
            const SizedBox(height: 16),
            Consumer(
              builder: (ctx, ref, _) {
                final current = ref.watch(fontSizeProvider);
                return Column(
                  children: _fontSizeLabels.entries
                      .map(
                        (e) => ListTile(
                          title: Text(e.value),
                          trailing: current == e.key
                              ? const Icon(Icons.check, color: Color(0xFF6366F1))
                              : null,
                          onTap: () {
                            ref.read(fontSizeProvider.notifier).setSize(e.key);
                            Navigator.pop(ctx);
                          },
                        ),
                      )
                      .toList(),
                );
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  // 只清community feed分页缓存（community_provider.dart 里的
  // '${userId}_community_p<page>'）——不是简单的"删掉除白名单外的一切"。
  // 用户给的方案假定了 '${userId}_token'/'jm_last_user_id' 这类实际上
  // 根本不存在的 key（token 存在 FlutterSecureStorage，不在 SharedPreferences
  // 里），而真正需要保留的 '${userId}_zodiac'/'${userId}_links'（编辑资料页
  // 写的）和 '${userId}_nb_recent'/'${userId}_nb_<id>'（本地 Notebook 文档，
  // 不是缓存）都不在他们的白名单里，且不是 'nb_' 前缀开头（是
  // '${userId}_nb_' 开头），也不会被 !key.startsWith('nb_') 挡住——
  // 照抄会把用户的星座/链接/所有 Notebook 都删掉
  Future<void> _clearCache(BuildContext context, WidgetRef ref) async {
    final prefs = await SharedPreferences.getInstance();
    final keys = prefs.getKeys().where((k) => k.contains('_community_p'));
    for (final key in keys) {
      await prefs.remove(key);
    }
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('缓存已清除')));
    }
  }

  Future<void> _logout(BuildContext context, WidgetRef ref) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('退出登录'),
        content: const Text('确定要退出当前账号吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消', style: TextStyle(color: Colors.grey)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('退出', style: TextStyle(color: Color(0xFFDC2626))),
          ),
        ],
      ),
    );
    if (confirm == true) {
      await ref.read(authServiceProvider).logout();
      if (context.mounted) context.go('/login');
    }
  }

  Future<void> _switchAccount(BuildContext context, WidgetRef ref) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('切换账号'),
        content: const Text('退出当前账号并跳转到登录页？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消', style: TextStyle(color: Colors.grey)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('确认', style: TextStyle(color: Color(0xFF6366F1))),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    await ref.read(authServiceProvider).logout();
    if (context.mounted) context.go('/login');
  }
}

class _NotifSettingsSheet extends ConsumerWidget {
  const _NotifSettingsSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(notifProvider);
    final notifier = ref.read(notifProvider.notifier);

    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: const EdgeInsets.all(20),
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
            '通知设置',
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w700,
              color: Theme.of(context).textTheme.bodyLarge?.color,
            ),
          ),
          const SizedBox(height: 8),
          _toggle('点赞通知', settings.likes, (v) => notifier.toggle('likes', v)),
          _toggle(
            '评论通知',
            settings.comments,
            (v) => notifier.toggle('comments', v),
          ),
          _toggle(
            '关注通知',
            settings.follows,
            (v) => notifier.toggle('follows', v),
          ),
          _toggle(
            '系统通知',
            settings.system,
            (v) => notifier.toggle('system', v),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _toggle(String title, bool value, ValueChanged<bool> onChanged) {
    return SwitchListTile(
      title: Text(title, style: const TextStyle(fontSize: 15)),
      value: value,
      onChanged: onChanged,
      activeThumbColor: const Color(0xFF6366F1),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String title;
  const _SectionTitle(this.title);
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
    child: Text(
      title.toUpperCase(),
      style: const TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w600,
        color: Colors.grey,
        letterSpacing: 0.5,
      ),
    ),
  );
}

class _SettingsGroup extends StatelessWidget {
  final List<Widget> children;
  const _SettingsGroup(this.children);
  @override
  Widget build(BuildContext context) =>
      Container(color: Theme.of(context).cardColor, child: Column(children: children));
}

class _SettingsRow extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final Color iconBg;
  final String title;
  final Color? titleColor;
  final String? subtitle;
  final String? trailing;
  final Color? trailingColor;
  final VoidCallback onTap;

  const _SettingsRow({
    required this.icon,
    required this.iconColor,
    required this.iconBg,
    required this.title,
    this.titleColor,
    this.subtitle,
    this.trailing,
    this.trailingColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: Theme.of(context).dividerColor)),
        ),
        child: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: iconBg,
                borderRadius: BorderRadius.circular(9),
              ),
              child: Icon(icon, color: iconColor, size: 17),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 15,
                      color: titleColor ?? Theme.of(context).textTheme.bodyLarge?.color,
                    ),
                  ),
                  if (subtitle != null)
                    Text(
                      subtitle!,
                      style: const TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                ],
              ),
            ),
            if (trailing != null)
              Text(
                trailing!,
                style: TextStyle(
                  fontSize: 14,
                  color: trailingColor ?? Colors.grey,
                ),
              ),
            const SizedBox(width: 4),
            const Icon(Icons.chevron_right, color: Colors.grey, size: 18),
          ],
        ),
      ),
    );
  }
}
