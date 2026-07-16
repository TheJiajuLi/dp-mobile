import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../l10n/generated/app_localizations.dart';
import '../widgets/settings_row.dart';
import 'changelog_screen.dart' show kLatestVersion;

class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  Future<void> _open(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      // AppBar 跟页面背景统一用 scaffoldBackgroundColor，不再用
      // cardColor——之前顶栏套一层 cardColor（浅色下是白），跟下面
      // scaffoldBackgroundColor（浅灰）撞出一块"白色色块贴灰色背景"的
      // 接缝，跟账号安全/隐私设置页同一个坑，这里补齐
      appBar: AppBar(
        title: Text(l10n.aboutApp),
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        foregroundColor: Theme.of(context).textTheme.bodyLarge?.color,
        elevation: 0,
      ),
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: ListView(
        children: [
          const SizedBox(height: 40),
          // Logo区
          Center(
            child: Column(
              children: [
                Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    color: const Color(0xFF6366F1),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Icon(
                    Icons.auto_awesome,
                    color: Colors.white,
                    size: 40,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  l10n.appName,
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  l10n.appSlogan,
                  style: const TextStyle(fontSize: 14, color: Colors.grey),
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEEF0FF),
                    borderRadius: BorderRadius.circular(99),
                  ),
                  child: const Text(
                    kLatestVersion,
                    style: TextStyle(
                      fontSize: 13,
                      color: Color(0xFF6366F1),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 40),

          // 信息列表——跟账号安全/隐私设置页同一套视觉语言，收进浮在
          // 页面背景上的圆角卡片，组内分割线区分，不再是贴边到底的
          // 扁平列表
          SettingsGroup(dividerIndent: 16, [
            ListTile(
              title: Text(l10n.versionNumber),
              trailing: const Text(
                kLatestVersion,
                style: TextStyle(color: Colors.grey),
              ),
            ),
            ListTile(
              title: Text(l10n.devTeam),
              trailing: const Text(
                'Dreaming Polar',
                style: TextStyle(
                  color: Color(0xFF6366F1),
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            ListTile(
              title: Text(l10n.officialWebsite),
              trailing: const Text(
                'dreamingpolar.com',
                style: TextStyle(color: Color(0xFF6366F1)),
              ),
              onTap: () => _open('https://dreamingpolar.com'),
            ),
            ListTile(
              title: Text(l10n.userAgreement),
              trailing: const Icon(Icons.chevron_right, color: Colors.grey),
              onTap: () => context.push('/settings/terms'),
            ),
            ListTile(
              title: Text(l10n.privacyPolicy),
              trailing: const Icon(Icons.chevron_right, color: Colors.grey),
              onTap: () => context.push('/settings/privacy-policy'),
            ),
          ]),
          const SizedBox(height: 20),
          Center(
            child: Text(
              l10n.copyrightFooter,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 12,
                color: Colors.grey,
                height: 1.6,
              ),
            ),
          ),
          const SizedBox(height: 40),
        ],
      ),
    );
  }
}
