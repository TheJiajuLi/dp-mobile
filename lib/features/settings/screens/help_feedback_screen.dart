import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../widgets/settings_row.dart';

const _primary = AppColors.primary;

class HelpFeedbackScreen extends StatefulWidget {
  const HelpFeedbackScreen({super.key});

  @override
  State<HelpFeedbackScreen> createState() => _HelpFeedbackScreenState();
}

class _HelpFeedbackScreenState extends State<HelpFeedbackScreen> {
  final _searchCtrl = TextEditingController();

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  void _openFaq([String? query]) {
    context.push(
      '/settings/faq',
      extra: query?.trim().isEmpty == true ? null : query,
    );
  }

  Future<void> _openMail(String to, String subject) async {
    final uri = Uri(
      scheme: 'mailto',
      path: to,
      query: 'subject=${Uri.encodeComponent(subject)}',
    );
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    } else if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('请手动发送邮件至 $to')));
    }
  }

  Future<void> _open(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  void _showContactSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: BoxDecoration(
          color: Theme.of(ctx).cardColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const Text(
              '联系我们',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 16),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.email_outlined, color: _primary),
              title: const Text('邮件支持'),
              subtitle: const Text('support@dreamingpolar.com'),
              onTap: () {
                Navigator.pop(ctx);
                _openMail('support@dreamingpolar.com', '极梦App咨询');
              },
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.public, color: _primary),
              title: const Text('官方网站'),
              subtitle: const Text('dreamingpolar.com'),
              onTap: () {
                Navigator.pop(ctx);
                _open('https://dreamingpolar.com');
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text('帮助与反馈'),
        centerTitle: true,
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        foregroundColor: Theme.of(context).textTheme.bodyLarge?.color,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, size: 18),
          onPressed: () => context.pop(),
        ),
      ),
      body: ListView(
        padding: EdgeInsets.zero,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: TextField(
              controller: _searchCtrl,
              onSubmitted: _openFaq,
              onTap: () {
                if (_searchCtrl.text.trim().isEmpty) _openFaq();
              },
              readOnly: true,
              decoration: InputDecoration(
                hintText: '搜索常见问题...',
                prefixIcon: const Icon(Icons.search, size: 20),
                filled: true,
                fillColor: Theme.of(context).cardColor,
                contentPadding: const EdgeInsets.symmetric(vertical: 12),
                // 之前只设了 border/enabledBorder，没设 focusedBorder——
                // 一点进去（哪怕是readOnly）就吃主题默认的聚焦描边（更粗
                // 的品牌紫圈），看起来像个没改过样式的原生控件。直接去掉
                // 描边，靠 filled 的胶囊底色区分，聚焦态也不例外
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          SettingsSectionTitle('快速帮助'),
          SettingsGroup([
            SettingsRow(
              icon: Icons.help_outline,
              iconColor: _primary,
              iconBg: const Color(0xFFEEF0FF),
              title: '常见问题',
              subtitle: '查看高频问题解答',
              onTap: () => _openFaq(),
            ),
            SettingsRow(
              icon: Icons.feedback_outlined,
              iconColor: const Color(0xFF16A34A),
              iconBg: const Color(0xFFE8F8F0),
              title: '问题反馈',
              subtitle: 'Bug报告、功能建议',
              onTap: () => _openMail('support@dreamingpolar.com', '极梦App问题反馈'),
            ),
            SettingsRow(
              icon: Icons.headset_mic_outlined,
              iconColor: const Color(0xFFD97706),
              iconBg: const Color(0xFFFEF3E2),
              title: '联系我们',
              subtitle: '邮件、社群',
              onTap: _showContactSheet,
            ),
          ]),

          // 「账号与安全」「会员与支付」两组入口已移除——这些在设置主页各自
          // 有专属入口，帮助与反馈页只保留快速帮助
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}
