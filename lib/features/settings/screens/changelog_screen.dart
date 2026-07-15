import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../l10n/generated/app_localizations.dart';

class ChangelogScreen extends StatelessWidget {
  const ChangelogScreen({super.key});

  // 版本数据——每次发布前手动更新。内容单语言硬编码，不接 l10n（发布
  // 说明本来就该跟发布节奏严格对齐，手工维护比接口/多语言词条更可靠）
  static const _versions = [
    _Version(
      version: 'v1.0.0',
      date: '2026年7月15日',
      isLatest: true,
      newFeatures: [
        '会员订阅系统上线（PRO / PRO MAX）',
        '极光创作者计划自动审核',
        '作品管理页全面重构',
        '专栏管理支持自定义封面',
        '更新日志页面',
      ],
      fixes: [
        '小梦回答代码块偶发残缺问题',
        'LaTeX \\\\ 换行不渲染',
        '群聊发文件重复发送问题',
        'Pro 角标在自己主页消失',
        '极索/发布页文字公式混排渲染',
      ],
      improvements: [
        '关注 Tab 预加载，切换无延迟',
        'Pyodide 全局预热，代码运行更快',
        '发布页摘要支持 LaTeX 渲染',
      ],
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final card = isDark ? AppColors.darkSurface : Colors.white;
    final border = isDark
        ? Colors.white.withValues(alpha: 0.06)
        : const Color(0xFFEBEBEB);
    final ink = isDark ? const Color(0xFFF0F2F8) : const Color(0xFF1A1A1A);
    final muted = isDark ? const Color(0xFF7A80A0) : const Color(0xFF888888);

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.changelog),
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        foregroundColor: ink,
        elevation: 0,
      ),
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: ListView.builder(
        padding: const EdgeInsets.fromLTRB(14, 8, 14, 24),
        itemCount: _versions.length,
        itemBuilder: (ctx, i) => _VersionCard(
          version: _versions[i],
          card: card,
          border: border,
          ink: ink,
          muted: muted,
        ),
      ),
    );
  }
}

// 版本卡片
class _VersionCard extends StatelessWidget {
  final _Version version;
  final Color card;
  final Color border;
  final Color ink;
  final Color muted;

  const _VersionCard({
    required this.version,
    required this.card,
    required this.border,
    required this.ink,
    required this.muted,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: border, width: 0.5),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
            child: Row(
              children: [
                Text(
                  version.version,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                    color: ink,
                  ),
                ),
                const SizedBox(width: 8),
                if (version.isLatest)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF0FFF5),
                      borderRadius: BorderRadius.circular(99),
                    ),
                    child: const Text(
                      '最新版本',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w500,
                        color: Color(0xFF16A34A),
                      ),
                    ),
                  ),
                const Spacer(),
                Text(
                  version.date,
                  style: TextStyle(fontSize: 11, color: muted),
                ),
              ],
            ),
          ),
          Divider(height: 0.5, color: border),
          Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (version.newFeatures.isNotEmpty) ...[
                  _ChangeGroup(
                    label: '新功能',
                    color: const Color(0xFF6366F1),
                    bg: const Color(0xFFEEF0FF),
                    items: version.newFeatures,
                    muted: muted,
                  ),
                  const SizedBox(height: 10),
                ],
                if (version.fixes.isNotEmpty) ...[
                  _ChangeGroup(
                    label: '修复',
                    color: const Color(0xFF16A34A),
                    bg: const Color(0xFFF0FFF5),
                    items: version.fixes,
                    muted: muted,
                  ),
                  const SizedBox(height: 10),
                ],
                if (version.improvements.isNotEmpty)
                  _ChangeGroup(
                    label: '优化',
                    color: const Color(0xFFD97706),
                    bg: const Color(0xFFFEF3C7),
                    items: version.improvements,
                    muted: muted,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// 变更分组
class _ChangeGroup extends StatelessWidget {
  final String label;
  final Color color;
  final Color bg;
  final List<String> items;
  final Color muted;

  const _ChangeGroup({
    required this.label,
    required this.color,
    required this.bg,
    required this.items,
    required this.muted,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(99),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w500,
              color: color,
            ),
          ),
        ),
        const SizedBox(height: 6),
        ...items.map(
          (item) => Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('·  ', style: TextStyle(color: muted, fontSize: 12)),
                Expanded(
                  child: Text(
                    item,
                    style: TextStyle(fontSize: 12, color: muted, height: 1.6),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// 数据模型
class _Version {
  final String version;
  final String date;
  final bool isLatest;
  final List<String> newFeatures;
  final List<String> fixes;
  final List<String> improvements;

  const _Version({
    required this.version,
    required this.date,
    this.isLatest = false,
    this.newFeatures = const [],
    this.fixes = const [],
    this.improvements = const [],
  });
}
