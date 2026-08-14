import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/network/api_client.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../auth/auth_service.dart';
import '../widgets/settings_row.dart';

class PrivacyScreen extends ConsumerStatefulWidget {
  const PrivacyScreen({super.key});

  @override
  ConsumerState<PrivacyScreen> createState() => _PrivacyScreenState();
}

class _PrivacyScreenState extends ConsumerState<PrivacyScreen> {
  bool _publicProfile = true;
  bool _publicFavorites = false;
  bool _allowComments = true;
  bool _allowMessages = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  // 实测（2026-07-04）：PUT /auth/users/privacy 已经上线能正常写入了，但
  // GET /auth/me 返回里完全没有 publicProfile/publicFavorites/
  // allowComments/allowMessages 这几个字段——只能写，读不回来。所以这几个
  // 开关的初始状态还是只能读本地 SharedPreferences（本地已经是唯一能读到
  // 当前值的地方），不能像后端已经返回的字段那样直接从 /auth/me 取
  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final userId = ref.read(currentUserProvider)?.id ?? '';
    if (!mounted) return;
    setState(() {
      _publicProfile =
          prefs.getBool('${userId}_privacy_public_profile') ?? true;
      _publicFavorites =
          prefs.getBool('${userId}_privacy_public_favorites') ?? false;
      _allowComments =
          prefs.getBool('${userId}_privacy_allow_comments') ?? true;
      _allowMessages =
          prefs.getBool('${userId}_privacy_allow_messages') ?? true;
    });
  }

  Future<void> _save(String key, bool value) async {
    final prefs = await SharedPreferences.getInstance();
    final userId = ref.read(currentUserProvider)?.id ?? '';
    await prefs.setBool('${userId}_$key', value);
    await _syncToBackend();
  }

  // 失败就悄悄忽略：本地已经存下了这次改动，不能因为这一次网络请求失败
  // 就打断用户操作或弹错误——本地状态本来就是这几个开关唯一能读回的地方
  Future<void> _syncToBackend() async {
    try {
      await ref
          .read(apiClientProvider)
          .put(
            '/auth/users/privacy',
            data: {
              'publicProfile': _publicProfile,
              'publicFavorites': _publicFavorites,
              'allowComments': _allowComments,
              'allowMessages': _allowMessages,
            },
          );
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    // 四行开关跟设置页 SettingsGroup 一样浮在页面背景上的圆角卡片，
    // 每行加上跟设置主页/账号安全统一的"圆框图标"（SettingsSwitchRow），
    // 分割线缩进 62 对齐图标右侧文字
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.privacySettings),
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        foregroundColor: Theme.of(context).textTheme.bodyLarge?.color,
        elevation: 0,
      ),
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: ListView(
        children: [
          const SizedBox(height: 8),
          SettingsGroup(dividerIndent: 62, [
            SettingsSwitchRow(
              icon: Icons.public,
              iconColor: const Color(0xFF2563EB),
              iconBg: const Color(0xFFE6F1FB),
              title: l10n.publicProfile,
              subtitle: l10n.publicProfileSubtitle,
              value: _publicProfile,
              onChanged: (v) {
                setState(() => _publicProfile = v);
                _save('privacy_public_profile', v);
              },
            ),
            SettingsSwitchRow(
              icon: Icons.bookmark_outline,
              iconColor: AppColors.success,
              iconBg: const Color(0xFFE8F8F0),
              title: l10n.publicFavorites,
              subtitle: l10n.publicFavoritesSubtitle,
              value: _publicFavorites,
              onChanged: (v) {
                setState(() => _publicFavorites = v);
                _save('privacy_public_favorites', v);
              },
            ),
            SettingsSwitchRow(
              icon: Icons.chat_bubble_outline,
              iconColor: AppColors.primary,
              iconBg: const Color(0xFFEEF0FF),
              title: l10n.allowComments,
              subtitle: l10n.allowCommentsSubtitle,
              value: _allowComments,
              onChanged: (v) {
                setState(() => _allowComments = v);
                _save('privacy_allow_comments', v);
              },
            ),
            SettingsSwitchRow(
              icon: Icons.mail_outline,
              iconColor: const Color(0xFF2563EB),
              iconBg: const Color(0xFFE6F1FB),
              title: l10n.allowMessages,
              subtitle: l10n.allowMessagesSubtitle,
              value: _allowMessages,
              onChanged: (v) {
                setState(() => _allowMessages = v);
                _save('privacy_allow_messages', v);
              },
            ),
          ]),
        ],
      ),
    );
  }
}
