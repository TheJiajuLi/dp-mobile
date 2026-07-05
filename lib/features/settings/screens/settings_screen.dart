import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/font_size_provider.dart';
import '../../../core/locale_provider.dart';
import '../../../core/notification_provider.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../providers/storage_provider.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  // double 重写了 ==/hashCode，不能作为 const map 的 key，这里用 final
  static Map<double, String> _fontSizeLabels(AppLocalizations l10n) => {
    0.85: l10n.fontSizeSmall,
    1.0: l10n.fontSizeStandard,
    1.15: l10n.fontSizeLarge,
    1.3: l10n.fontSizeExtraLarge,
  };

  static Map<AppLocale, String> _localeLabels(AppLocalizations l10n) => {
    AppLocale.system: l10n.themeSystem,
    AppLocale.zh: l10n.languageZh,
    AppLocale.en: l10n.languageEn,
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final fontSize = ref.watch(fontSizeProvider);
    final localePref = ref.watch(localeProvider);

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      // top/bottom 不在这层留白，改成顶栏自己的 SafeArea(bottom:false)
      // 把白色背景铺进状态栏安全区，避免这层统一留白露出 Scaffold 背景
      // 跟顶栏纯白刀切不连贯（跟 publish_screen.dart 顶栏是同一套处理）
      body: SafeArea(
        top: false,
        bottom: false,
        child: Column(
          children: [
            Container(
              color: Theme.of(context).cardColor,
              child: SafeArea(
                bottom: false,
                child: Padding(
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
                        l10n.settingsTitle,
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                          color: Theme.of(context).textTheme.bodyLarge?.color,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Expanded(
              child: ListView(
                children: [
                  _SectionTitle(l10n.sectionAccount),
                  _SettingsGroup([
                    _SettingsRow(
                      icon: Icons.shield_outlined,
                      iconColor: const Color(0xFF2563EB),
                      iconBg: const Color(0xFFE6F1FB),
                      title: l10n.accountSecurity,
                      subtitle: l10n.accountSecuritySubtitle,
                      onTap: () => context.push('/settings/security'),
                    ),
                    _SettingsRow(
                      icon: Icons.notifications_outlined,
                      iconColor: const Color(0xFF6366F1),
                      iconBg: const Color(0xFFEEF0FF),
                      title: l10n.notificationSettings,
                      subtitle: l10n.notificationSettingsSubtitle,
                      onTap: () => showModalBottomSheet(
                        context: context,
                        builder: (_) => const _NotifSettingsSheet(),
                      ),
                    ),
                    _SettingsRow(
                      icon: Icons.lock_outlined,
                      iconColor: const Color(0xFF16A34A),
                      iconBg: const Color(0xFFE8F8F0),
                      title: l10n.privacy,
                      subtitle: l10n.privacySubtitle,
                      onTap: () => context.push('/settings/privacy'),
                    ),
                  ]),

                  _SectionTitle(l10n.sectionGeneral),
                  _SettingsGroup([
                    _SettingsRow(
                      icon: Icons.text_fields,
                      iconColor: const Color(0xFF6366F1),
                      iconBg: const Color(0xFFEEF0FF),
                      title: l10n.fontSize,
                      trailing:
                          _fontSizeLabels(l10n)[fontSize] ??
                          l10n.fontSizeStandard,
                      onTap: () => _showFontPicker(context, ref),
                    ),
                    _SettingsRow(
                      icon: Icons.language,
                      iconColor: const Color(0xFF2563EB),
                      iconBg: const Color(0xFFE6F1FB),
                      title: l10n.language,
                      trailing: _localeLabels(l10n)[localePref],
                      onTap: () => _showLanguagePicker(context, ref),
                    ),
                    Consumer(
                      builder: (ctx, ref, _) {
                        final storage = ref.watch(storageUsageProvider);
                        return storage.when(
                          data: (data) {
                            final total =
                                (data['totalBytes'] as num?)?.toInt() ?? 0;
                            final quota =
                                (data['quota'] as num?)?.toInt() ??
                                200 * 1024 * 1024;
                            return _SettingsRow(
                              icon: Icons.cloud_outlined,
                              iconColor: const Color(0xFF16A34A),
                              iconBg: const Color(0xFFE8F8F0),
                              title: l10n.cloudStorage,
                              subtitle: l10n.storageUsedOfQuota(
                                _formatBytes(total),
                                _formatQuota(quota),
                              ),
                              onTap: () => context.push('/settings/storage'),
                            );
                          },
                          loading: () => _SettingsRow(
                            icon: Icons.cloud_outlined,
                            iconColor: const Color(0xFF16A34A),
                            iconBg: const Color(0xFFE8F8F0),
                            title: l10n.cloudStorage,
                            subtitle: l10n.loadingEllipsis,
                            onTap: () => context.push('/settings/storage'),
                          ),
                          error: (_, __) => _SettingsRow(
                            icon: Icons.cloud_outlined,
                            iconColor: const Color(0xFF16A34A),
                            iconBg: const Color(0xFFE8F8F0),
                            title: l10n.cloudStorage,
                            subtitle: l10n.tapToViewDetails,
                            onTap: () => context.push('/settings/storage'),
                          ),
                        );
                      },
                    ),
                    _SettingsRow(
                      icon: Icons.delete_outline,
                      iconColor: Colors.grey,
                      iconBg: Theme.of(context).dividerColor,
                      title: l10n.clearCache,
                      onTap: () => _clearCache(context, ref),
                    ),
                  ]),

                  _SectionTitle(l10n.sectionMembership),
                  _SettingsGroup([
                    _SettingsRow(
                      icon: Icons.workspace_premium,
                      iconColor: const Color(0xFFD97706),
                      iconBg: const Color(0xFFFFF7E6),
                      title: l10n.myMembership,
                      subtitle: l10n.currentFreeVersion,
                      trailing: l10n.upgradePro,
                      trailingColor: const Color(0xFF6366F1),
                      onTap: () => context.push('/settings/subscription'),
                    ),
                    _SettingsRow(
                      icon: Icons.credit_card_outlined,
                      iconColor: const Color(0xFF2563EB),
                      iconBg: const Color(0xFFE6F1FB),
                      title: l10n.paymentMethod,
                      subtitle: l10n.paymentMethodSubtitle,
                      onTap: () => context.push('/settings/payment'),
                    ),
                    _SettingsRow(
                      icon: Icons.receipt_long_outlined,
                      iconColor: const Color(0xFF16A34A),
                      iconBg: const Color(0xFFE8F8F0),
                      title: l10n.subscriptionManagement,
                      subtitle: l10n.subscriptionManagementSubtitle,
                      onTap: () => context.push('/settings/subscription'),
                    ),
                  ]),

                  _SectionTitle(l10n.sectionAbout),
                  _SettingsGroup([
                    _SettingsRow(
                      icon: Icons.info_outline,
                      iconColor: Colors.grey,
                      iconBg: Theme.of(context).dividerColor,
                      title: l10n.aboutApp,
                      subtitle: 'v1.0.0',
                      onTap: () => context.push('/settings/about'),
                    ),
                    _SettingsRow(
                      icon: Icons.description_outlined,
                      iconColor: Colors.grey,
                      iconBg: Theme.of(context).dividerColor,
                      title: l10n.userAgreement,
                      onTap: () => context.push('/settings/about'),
                    ),
                    _SettingsRow(
                      icon: Icons.privacy_tip_outlined,
                      iconColor: Colors.grey,
                      iconBg: Theme.of(context).dividerColor,
                      title: l10n.privacyPolicy,
                      onTap: () => context.push('/settings/about'),
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

  String _formatBytes(int b) {
    if (b < 1024 * 1024) return '${(b / 1024).toStringAsFixed(0)}KB';
    if (b < 1024 * 1024 * 1024)
      return '${(b / 1024 / 1024).toStringAsFixed(1)}MB';
    return '${(b / 1024 / 1024 / 1024).toStringAsFixed(1)}GB';
  }

  String _formatQuota(int b) {
    if (b >= 1024 * 1024 * 1024) {
      return '${(b / 1024 / 1024 / 1024).toStringAsFixed(0)}GB';
    }
    return '${(b / 1024 / 1024).toStringAsFixed(0)}MB';
  }

  void _showFontPicker(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
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
              l10n.fontSize,
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
                  children: _fontSizeLabels(l10n).entries
                      .map(
                        (e) => ListTile(
                          title: Text(e.value),
                          trailing: current == e.key
                              ? const Icon(
                                  Icons.check,
                                  color: Color(0xFF6366F1),
                                )
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

  void _showLanguagePicker(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
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
              l10n.selectLanguage,
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: Theme.of(ctx).textTheme.bodyLarge?.color,
              ),
            ),
            const SizedBox(height: 16),
            Consumer(
              builder: (ctx, ref, _) {
                final current = ref.watch(localeProvider);
                return Column(
                  children: _localeLabels(l10n).entries
                      .map(
                        (e) => ListTile(
                          title: Text(e.value),
                          trailing: current == e.key
                              ? const Icon(
                                  Icons.check,
                                  color: Color(0xFF6366F1),
                                )
                              : null,
                          onTap: () {
                            ref.read(localeProvider.notifier).setLocale(e.key);
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context)!.cacheCleared)),
      );
    }
  }
}

class _NotifSettingsSheet extends ConsumerWidget {
  const _NotifSettingsSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
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
            l10n.notificationSettings,
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w700,
              color: Theme.of(context).textTheme.bodyLarge?.color,
            ),
          ),
          const SizedBox(height: 8),
          _toggle(
            l10n.likeNotifications,
            settings.likes,
            (v) => notifier.toggle('likes', v),
          ),
          _toggle(
            l10n.commentNotifications,
            settings.comments,
            (v) => notifier.toggle('comments', v),
          ),
          _toggle(
            l10n.followNotifications,
            settings.follows,
            (v) => notifier.toggle('follows', v),
          ),
          _toggle(
            l10n.systemNotifications,
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
  Widget build(BuildContext context) => Container(
    color: Theme.of(context).cardColor,
    child: Column(children: children),
  );
}

class _SettingsRow extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final Color iconBg;
  final String title;
  final String? subtitle;
  final String? trailing;
  final Color? trailingColor;
  final VoidCallback onTap;

  const _SettingsRow({
    required this.icon,
    required this.iconColor,
    required this.iconBg,
    required this.title,
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
          border: Border(
            bottom: BorderSide(color: Theme.of(context).dividerColor),
          ),
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
                      color: Theme.of(context).textTheme.bodyLarge?.color,
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
