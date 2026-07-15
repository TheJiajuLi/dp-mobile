import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/font_size_provider.dart';
import '../../../core/locale_provider.dart';
import '../../../core/notification_provider.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../auth/auth_service.dart';
import '../providers/storage_provider.dart';
import '../widgets/settings_row.dart';

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
    final me = ref.watch(currentUserProvider);

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
              color: Theme.of(context).scaffoldBackgroundColor,
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
                        child: Icon(
                          Icons.arrow_back_ios,
                          size: 18,
                          color: Theme.of(context).textTheme.bodyLarge?.color,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        l10n.settingsTitle,
                        style: TextStyle(
                          fontSize: 22,
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
                // ListView 不显式传 padding 时会自动套 MediaQuery 安全区当
                // 默认padding——顶栏已经自己处理过安全区了，这里再叠一次
                // 就是"设置"标题跟下面第一个分组之间那截很大的空白的来源
                // （跟GridView那个坑是同一类问题，见CONTEXT.md踩坑#14）
                padding: EdgeInsets.zero,
                children: [
                  const SizedBox(height: 8),
                  // 会员中心入口——顶部一张紫色渐变 Hero 卡，会员态显示当前
                  // 档位、免费态引导开通
                  _MembershipEntryCard(
                    membership: me?.membership,
                    isAurora: me?.isAuroraCreator ?? false,
                  ),
                  SettingsSectionTitle(l10n.sectionAccount),
                  SettingsGroup([
                    SettingsRow(
                      icon: Icons.shield_outlined,
                      iconColor: const Color(0xFF2563EB),
                      iconBg: const Color(0xFFE6F1FB),
                      title: l10n.accountSecurity,
                      subtitle: l10n.accountSecuritySubtitle,
                      onTap: () => context.push('/settings/security'),
                    ),
                    SettingsRow(
                      icon: Icons.notifications_outlined,
                      iconColor: const Color(0xFF6366F1),
                      iconBg: const Color(0xFFEEF0FF),
                      title: l10n.notificationSettings,
                      subtitle: l10n.notificationSettingsSubtitle,
                      onTap: () => showModalBottomSheet(
                        context: context,
                        backgroundColor: Colors.transparent,
                        builder: (_) => const _NotifSettingsSheet(),
                      ),
                    ),
                    SettingsRow(
                      icon: Icons.lock_outlined,
                      iconColor: const Color(0xFF16A34A),
                      iconBg: const Color(0xFFE8F8F0),
                      title: l10n.privacy,
                      subtitle: l10n.privacySubtitle,
                      onTap: () => context.push('/settings/privacy'),
                    ),
                  ]),

                  SettingsSectionTitle(l10n.sectionGeneral),
                  SettingsGroup([
                    SettingsRow(
                      icon: Icons.text_fields,
                      iconColor: const Color(0xFF6366F1),
                      iconBg: const Color(0xFFEEF0FF),
                      title: l10n.fontSize,
                      trailing:
                          _fontSizeLabels(l10n)[fontSize] ??
                          l10n.fontSizeStandard,
                      onTap: () => _showFontPicker(context, ref),
                    ),
                    SettingsRow(
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
                            return SettingsRow(
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
                          loading: () => SettingsRow(
                            icon: Icons.cloud_outlined,
                            iconColor: const Color(0xFF16A34A),
                            iconBg: const Color(0xFFE8F8F0),
                            title: l10n.cloudStorage,
                            subtitle: l10n.loadingEllipsis,
                            onTap: () => context.push('/settings/storage'),
                          ),
                          error: (_, __) => SettingsRow(
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
                    SettingsRow(
                      icon: Icons.delete_outline,
                      iconColor: Colors.grey,
                      iconBg: Theme.of(context).dividerColor,
                      title: l10n.clearCache,
                      onTap: () => _clearCache(context, ref),
                    ),
                  ]),

                  SettingsSectionTitle(l10n.sectionAbout),
                  SettingsGroup([
                    SettingsRow(
                      icon: Icons.help_outline,
                      iconColor: const Color(0xFF6366F1),
                      iconBg: const Color(0xFFEEF0FF),
                      title: l10n.helpAndFeedback,
                      onTap: () => context.push('/settings/help'),
                    ),
                    SettingsRow(
                      icon: Icons.info_outline,
                      iconColor: Colors.grey,
                      iconBg: Theme.of(context).dividerColor,
                      title: l10n.aboutApp,
                      subtitle: 'v1.0.0',
                      onTap: () => context.push('/settings/about'),
                    ),
                    SettingsRow(
                      icon: Icons.description_outlined,
                      iconColor: Colors.grey,
                      iconBg: Theme.of(context).dividerColor,
                      title: l10n.userAgreement,
                      onTap: () => context.push('/settings/terms'),
                    ),
                    SettingsRow(
                      icon: Icons.privacy_tip_outlined,
                      iconColor: Colors.grey,
                      iconBg: Theme.of(context).dividerColor,
                      title: l10n.privacyPolicy,
                      onTap: () => context.push('/settings/privacy-policy'),
                    ),
                  ]),

                  // 2026-07-06 起从侧边栏（已整个移除）挪过来——切换账号/
                  // 退出登录单独成一组放最后，不加 SettingsSectionTitle（页面顶部
                  // 已经用过一次"账号"当分组标题了，这里再来一次会显得像
                  // 重复分组；退出登录标红跟原来侧边栏的处理一致）
                  const SizedBox(height: 12),
                  SettingsGroup([
                    SettingsRow(
                      icon: Icons.swap_horizontal_circle_outlined,
                      iconColor: const Color(0xFF6366F1),
                      iconBg: const Color(0xFFEEF0FF),
                      title: l10n.switchAccount,
                      onTap: () => context.push('/switch-account'),
                    ),
                    SettingsRow(
                      icon: Icons.logout,
                      iconColor: const Color(0xFFDC2626),
                      iconBg: const Color(0xFFFEE2E2),
                      title: l10n.logout,
                      onTap: () => _confirmLogout(context, ref, l10n),
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

  // 退出登录改成重设计的底部弹层：拖拽条 + 当前账号信息（头像/用户名/
  // 邮箱）+ 数据保留提示 + 红色「退出登录」+ 中性「取消」，比原来干巴巴的
  // AlertDialog 更贴合一线产品的退出体验
  void _confirmLogout(
    BuildContext context,
    WidgetRef ref,
    AppLocalizations l10n,
  ) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final currentUser = ref.read(currentUserProvider);

    // 头像可能是 data:image base64（app 内不少头像是内联的），NetworkImage
    // 处理不了这种，分流：base64 走 MemoryImage，http(s) 走 NetworkImage，
    // 都没有就退回首字母占位
    ImageProvider? avatarImage;
    final avatar = currentUser?.avatar;
    if (avatar != null && avatar.isNotEmpty) {
      if (avatar.startsWith('data:image')) {
        try {
          avatarImage = MemoryImage(base64Decode(avatar.split(',').last));
        } catch (_) {}
      } else {
        avatarImage = NetworkImage(avatar);
      }
    }
    final username = currentUser?.username ?? '';

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (sheetCtx) => Container(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 40),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF17171F) : Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          border: isDark
              ? Border(
                  top: BorderSide(
                    color: Colors.white.withValues(alpha: 0.08),
                    width: 0.5,
                  ),
                )
              : null,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 拖拽条
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: isDark
                      ? const Color(0xFF333333)
                      : const Color(0xFFE0E0E0),
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
            ),

            // 用户信息
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 4, 4, 14),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 24,
                    backgroundColor: const Color(0xFF6366F1),
                    backgroundImage: avatarImage,
                    child: avatarImage == null
                        ? Text(
                            username.isNotEmpty
                                ? username.substring(0, 1).toUpperCase()
                                : 'U',
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                            ),
                          )
                        : null,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          username,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w500,
                            color: isDark
                                ? const Color(0xFFF0F2F8)
                                : const Color(0xFF1A1A1A),
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          currentUser?.email ?? '',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            color: isDark
                                ? const Color(0xFF555555)
                                : Colors.grey[400],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // 分割线
            Divider(
              height: 0.5,
              color: isDark
                  ? Colors.white.withValues(alpha: 0.06)
                  : const Color(0xFFF0F0F0),
            ),

            const SizedBox(height: 16),

            // 提示文字
            Text(
              l10n.logoutDataRetainedHint,
              style: TextStyle(
                fontSize: 13,
                color: isDark ? const Color(0xFF555555) : Colors.grey[500],
                height: 1.6,
              ),
            ),

            const SizedBox(height: 16),

            // 退出登录按钮
            SizedBox(
              width: double.infinity,
              child: TextButton(
                onPressed: () async {
                  Navigator.pop(sheetCtx);
                  await ref.read(authServiceProvider).logout();
                  if (context.mounted) context.go('/login');
                },
                style: TextButton.styleFrom(
                  backgroundColor: isDark
                      ? const Color(0xFFEF4444).withValues(alpha: 0.12)
                      : const Color(0xFFFEF2F2),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(
                      color: isDark
                          ? const Color(0xFFEF4444).withValues(alpha: 0.25)
                          : const Color(0xFFFECACA),
                      width: 0.5,
                    ),
                  ),
                ),
                child: Text(
                  l10n.logout,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                    color: Color(0xFFEF4444),
                  ),
                ),
              ),
            ),

            const SizedBox(height: 10),

            // 取消按钮
            SizedBox(
              width: double.infinity,
              child: TextButton(
                onPressed: () => Navigator.pop(sheetCtx),
                style: TextButton.styleFrom(
                  backgroundColor: isDark
                      ? Colors.white.withValues(alpha: 0.06)
                      : const Color(0xFFF5F5F5),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: Text(
                  l10n.cancel,
                  style: TextStyle(
                    fontSize: 15,
                    color: isDark
                        ? const Color(0xFF7A80A0)
                        : const Color(0xFF555555),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NotifSettingsSheet extends ConsumerWidget {
  const _NotifSettingsSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final settings = ref.watch(notifProvider);
    final notifier = ref.read(notifProvider.notifier);

    // 四个开关之前直接平铺在sheet自己的白底容器里，没有独立的卡片边界，
    // 跟隐私设置/账号安全那两个已经改成 SettingsGroup 圆角卡片的设置页
    // 不是同一套视觉语言。这里把sheet背景换成跟设置页一样的
    // scaffoldBackgroundColor（中性灰白），开关组用同一个 SettingsGroup
    // 浮在上面，弹窗和常规设置页才是统一的一线产品视觉
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: const EdgeInsets.only(top: 20, bottom: 20),
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
          const SizedBox(height: 16),
          SettingsGroup(dividerIndent: 62, [
            SettingsSwitchRow(
              icon: Icons.favorite_border,
              iconColor: const Color(0xFF6366F1),
              iconBg: const Color(0xFFEEF0FF),
              title: l10n.likeNotifications,
              value: settings.likes,
              onChanged: (v) => notifier.toggle('likes', v),
            ),
            SettingsSwitchRow(
              icon: Icons.chat_bubble_outline,
              iconColor: const Color(0xFF2563EB),
              iconBg: const Color(0xFFE6F1FB),
              title: l10n.commentNotifications,
              value: settings.comments,
              onChanged: (v) => notifier.toggle('comments', v),
            ),
            SettingsSwitchRow(
              icon: Icons.person_add_alt_1,
              iconColor: const Color(0xFF16A34A),
              iconBg: const Color(0xFFE8F8F0),
              title: l10n.followNotifications,
              value: settings.follows,
              onChanged: (v) => notifier.toggle('follows', v),
            ),
            SettingsSwitchRow(
              icon: Icons.campaign_outlined,
              iconColor: Colors.grey,
              iconBg: Theme.of(context).dividerColor,
              title: l10n.systemNotifications,
              value: settings.system,
              onChanged: (v) => notifier.toggle('system', v),
            ),
          ]),
        ],
      ),
    );
  }
}

// 会员中心 Hero 卡——2026 一线产品视觉：紫色渐变 + 金色皇冠 + 柔和辉光，
// 白色 CTA 药丸。会员态显示当前档位与「管理」，免费态引导「立即开通」，
// 极光创作者显示已免费享 Pro。点击进 /settings/subscription
class _MembershipEntryCard extends StatelessWidget {
  final String? membership;
  final bool isAurora;
  const _MembershipEntryCard({
    required this.membership,
    required this.isAurora,
  });

  @override
  Widget build(BuildContext context) {
    final isMax = membership == 'pro_max';
    final isPro = membership == 'pro';
    final String title;
    final String sub;
    final String cta;
    if (isMax) {
      title = '极梦 Pro Max';
      sub = '已解锁全部权益 · 感谢支持';
      cta = '管理';
    } else if (isPro) {
      title = '极梦 Pro';
      sub = '尊享全部创作与 AI 权益';
      cta = '管理';
    } else if (isAurora) {
      title = '极光创作者';
      sub = '已免费尊享 Pro 全部权益';
      cta = '查看';
    } else {
      title = '开通极梦会员';
      sub = '解锁 Pro 创作、AI 与专属身份';
      cta = '立即开通';
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => context.push('/settings/subscription'),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF6D5DF6), Color(0xFF8B5CF6)],
            ),
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF6D5DF6).withValues(alpha: 0.30),
                blurRadius: 22,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.18),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.workspace_premium,
                  size: 24,
                  color: Color(0xFFFFD66B),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                        letterSpacing: 0.2,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      sub,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12.5,
                        height: 1.2,
                        color: Colors.white.withValues(alpha: 0.82),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  cta,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF6D5DF6),
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
