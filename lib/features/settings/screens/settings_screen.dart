import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../auth/auth_service.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F8F8),
      body: SafeArea(
        child: Column(
          children: [
            Container(
              color: Colors.white,
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
                  const Text(
                    '设置',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
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
                      onTap: () => _todo(context, '隐私设置即将上线，敬请期待'),
                    ),
                  ]),

                  const _SectionTitle('通用'),
                  _SettingsGroup([
                    _SettingsRow(
                      icon: Icons.palette_outlined,
                      iconColor: const Color(0xFFD97706),
                      iconBg: const Color(0xFFFFF7E6),
                      title: '主题',
                      trailing: '跟随系统',
                      onTap: () => _showThemePicker(context),
                    ),
                    _SettingsRow(
                      icon: Icons.text_fields,
                      iconColor: const Color(0xFF6366F1),
                      iconBg: const Color(0xFFEEF0FF),
                      title: '字体大小',
                      trailing: '标准',
                      onTap: () => _showFontPicker(context),
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
                      onTap: () => _todo(context, '云存储管理即将上线，敬请期待'),
                    ),
                    _SettingsRow(
                      icon: Icons.delete_outline,
                      iconColor: Colors.grey,
                      iconBg: const Color(0xFFF5F5F5),
                      title: '清除缓存',
                      onTap: () => _clearCache(context),
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
                      iconBg: const Color(0xFFF5F5F5),
                      title: '关于极梦',
                      subtitle: 'v1.0.0',
                      onTap: () => _showAbout(context),
                    ),
                    _SettingsRow(
                      icon: Icons.description_outlined,
                      iconColor: Colors.grey,
                      iconBg: const Color(0xFFF5F5F5),
                      title: '用户协议',
                      onTap: () => _todo(context, '用户协议即将上线，敬请期待'),
                    ),
                    _SettingsRow(
                      icon: Icons.privacy_tip_outlined,
                      iconColor: Colors.grey,
                      iconBg: const Color(0xFFF5F5F5),
                      title: '隐私政策',
                      onTap: () => _todo(context, '隐私政策即将上线，敬请期待'),
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

  void _showThemePicker(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
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
            const Text(
              '主题',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 16),
            ...['跟随系统', '浅色', '深色'].map(
              (t) => ListTile(
                title: Text(t),
                trailing: t == '跟随系统'
                    ? const Icon(Icons.check, color: Color(0xFF6366F1))
                    : null,
                onTap: () => Navigator.pop(ctx),
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  void _showFontPicker(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
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
            const Text(
              '字体大小',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 16),
            ...['小', '标准', '大', '超大'].map(
              (s) => ListTile(
                title: Text(s),
                trailing: s == '标准'
                    ? const Icon(Icons.check, color: Color(0xFF6366F1))
                    : null,
                onTap: () => Navigator.pop(ctx),
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Future<void> _clearCache(BuildContext context) async {
    final prefs = await SharedPreferences.getInstance();
    // 只清除 feed/教程缓存，不碰账号数据（token/zodiac/links 等带 userId 前缀的 key）
    await prefs.remove('cached_feed');
    await prefs.remove('cached_tutorials');
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('缓存已清除')));
    }
  }

  void _showAbout(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('极梦'),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('版本：v1.0.0'),
            SizedBox(height: 4),
            Text('数据分析，为创造而生。'),
            SizedBox(height: 4),
            Text('© 2026 Dreaming Polar'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('确定', style: TextStyle(color: Color(0xFF6366F1))),
          ),
        ],
      ),
    );
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
    await ref.read(authServiceProvider).logout();
    if (context.mounted) context.go('/login');
  }
}

class _NotifSettingsSheet extends StatefulWidget {
  const _NotifSettingsSheet();
  @override
  State<_NotifSettingsSheet> createState() => _NotifSettingsSheetState();
}

class _NotifSettingsSheetState extends State<_NotifSettingsSheet> {
  bool _likes = true;
  bool _comments = true;
  bool _follows = true;
  bool _system = true;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
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
          const Text(
            '通知设置',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          _toggle('点赞通知', _likes, (v) => setState(() => _likes = v)),
          _toggle('评论通知', _comments, (v) => setState(() => _comments = v)),
          _toggle('关注通知', _follows, (v) => setState(() => _follows = v)),
          _toggle('系统通知', _system, (v) => setState(() => _system = v)),
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
      Container(color: Colors.white, child: Column(children: children));
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
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: Color(0xFFF5F5F5))),
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
                      color: titleColor ?? const Color(0xFF1C1C1E),
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
