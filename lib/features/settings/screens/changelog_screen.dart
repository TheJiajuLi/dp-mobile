import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../l10n/generated/app_localizations.dart';

// 最新版本号——每次发布前手动更新。设置页「更新日志」的"新动态"角标、
// 本页"当前版本"、以及已读判断都用它当唯一真相
const String kLatestVersion = 'v1.0.0';

const String _kLastSeenKey = 'about_last_seen_version';

// 设置页「更新日志」是否有没看过的新版本：读 SharedPreferences 里存的
// last_seen_version 跟 kLatestVersion 比。进过一次更新日志页就置为已读，
// invalidate 这个 provider 让角标消失
final changelogUnseenProvider = FutureProvider<bool>((ref) async {
  final prefs = await SharedPreferences.getInstance();
  return prefs.getString(_kLastSeenKey) != kLatestVersion;
});

enum ChangeType { feature, improve, fix, breaking }

class _Change {
  final String text;
  final ChangeType type;
  const _Change(this.text, this.type);

  Color get color => switch (type) {
    ChangeType.feature => const Color(0xFF6366F1),
    ChangeType.improve => const Color(0xFF2563EB),
    ChangeType.fix => const Color(0xFFD97706),
    ChangeType.breaking => const Color(0xFFEF4444),
  };
}

String _typeLabel(ChangeType t) => switch (t) {
  ChangeType.feature => '新功能',
  ChangeType.improve => '优化',
  ChangeType.fix => '修复',
  ChangeType.breaking => '重要',
};

Color _typeColor(ChangeType t) => switch (t) {
  ChangeType.feature => const Color(0xFF6366F1),
  ChangeType.improve => const Color(0xFF2563EB),
  ChangeType.fix => const Color(0xFFD97706),
  ChangeType.breaking => const Color(0xFFEF4444),
};

class _Version {
  final String version;
  final String date;
  final List<_Change> changes;
  const _Version({
    required this.version,
    required this.date,
    required this.changes,
  });
}

class ChangelogScreen extends ConsumerStatefulWidget {
  const ChangelogScreen({super.key});

  @override
  ConsumerState<ChangelogScreen> createState() => _ChangelogScreenState();

  // 版本数据——每次发布前手动维护，单语言硬编码（发布说明本就该跟发布
  // 节奏严格对齐，手工维护比接口/多语言词条更可靠）。changes 是扁平列表，
  // 卡片里按 type 分组渲染，只显示最近 10 个版本
  static const List<_Version> _versions = [
    _Version(
      version: 'v1.0.0',
      date: '2026.07.15',
      changes: [
        _Change('新增会员订阅系统（PRO / PRO MAX）', ChangeType.feature),
        _Change('极光创作者计划自动审核上线', ChangeType.feature),
        _Change('作品管理页全面重构', ChangeType.feature),
        _Change('专栏管理支持自定义封面', ChangeType.feature),
        _Change('新增更新日志页面', ChangeType.feature),
        _Change('关注 Tab 预加载，切换无延迟', ChangeType.improve),
        _Change('Pyodide 全局预热，代码运行更快', ChangeType.improve),
        _Change('小梦回答打字机逐字渲染效果', ChangeType.improve),
        _Change('小梦代码块偶发残缺问题', ChangeType.fix),
        _Change(r'LaTeX \\ 换行不渲染', ChangeType.fix),
        _Change('群聊发文件重复发送', ChangeType.fix),
        _Change('Pro 角标在自己主页消失', ChangeType.fix),
      ],
    ),
  ];
}

class _ChangelogScreenState extends ConsumerState<ChangelogScreen> {
  @override
  void initState() {
    super.initState();
    _markSeen();
  }

  // 进页面即"已读到最新版本"，并让设置页的"新动态"角标失效
  Future<void> _markSeen() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kLastSeenKey, kLatestVersion);
    if (mounted) ref.invalidate(changelogUnseenProvider);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = Theme.of(context).scaffoldBackgroundColor;
    final ink = isDark ? const Color(0xFFF0F2F8) : const Color(0xFF1A1A1A);
    final muted = isDark ? const Color(0xFF7A80A0) : const Color(0xFF888888);

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        title: Text(l10n.changelog),
        backgroundColor: bg,
        foregroundColor: ink,
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
        children: [
          _buildHeader(ink, muted),
          ...ChangelogScreen._versions
              .take(10)
              .map((v) => _VersionCard(version: v, isDark: isDark)),
        ],
      ),
    );
  }

  Widget _buildHeader(Color ink, Color muted) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: const Color(0xFF6366F1),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Center(
              child: Text(
                '极',
                style: TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
            ),
          ),
          const SizedBox(height: 14),
          Text(
            '极梦 DreamingPolar',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w500,
              color: ink,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '当前版本 $kLatestVersion',
            style: TextStyle(fontSize: 13, color: muted),
          ),
          const SizedBox(height: 8),
          Text(
            '让知识创作变得像写笔记\n一样自然。',
            style: TextStyle(fontSize: 13, color: muted, height: 1.6),
          ),
        ],
      ),
    );
  }
}

class _VersionCard extends StatelessWidget {
  final _Version version;
  final bool isDark;
  const _VersionCard({required this.version, required this.isDark});

  @override
  Widget build(BuildContext context) {
    final ink = isDark ? const Color(0xFFF0F2F8) : const Color(0xFF1A1A1A);
    final muted = isDark ? const Color(0xFF7A80A0) : const Color(0xFF888888);
    final divider = isDark
        ? Colors.white.withValues(alpha: 0.06)
        : const Color(0xFFF0F0F0);

    // 按 type 顺序（新功能→优化→修复→重要）分组，跳过空组
    final groups = <ChangeType, List<_Change>>{};
    for (final t in ChangeType.values) {
      final items = version.changes.where((c) => c.type == t).toList();
      if (items.isNotEmpty) groups[t] = items;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        // 无边框、极轻背景色；浅色再加一层极淡投影制造"浮起"，不然在近白
        // 页面上几乎看不出卡片
        color: isDark ? const Color(0xFF17171F) : const Color(0xFFFCFCFD),
        borderRadius: BorderRadius.circular(24),
        boxShadow: isDark
            ? null
            : [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.03),
                  blurRadius: 16,
                  offset: const Offset(0, 6),
                ),
              ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                version.version,
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: ink,
                ),
              ),
              const Spacer(),
              Text(version.date, style: TextStyle(fontSize: 12, color: muted)),
            ],
          ),
          const SizedBox(height: 14),
          Container(height: 0.5, color: divider),
          const SizedBox(height: 16),
          for (final entry in groups.entries) ...[
            _pill(_typeLabel(entry.key), _typeColor(entry.key)),
            const SizedBox(height: 8),
            ...entry.value.map((c) => _changeRow(c)),
            if (entry.key != groups.keys.last) const SizedBox(height: 16),
          ],
        ],
      ),
    );
  }

  // 分组标签：纯文字胶囊（无 emoji），浅色淡底、深色半透明底
  Widget _pill(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: isDark ? 0.18 : 0.1),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }

  // 变更项：纯色小圆点（无 emoji）+ 文字
  Widget _changeRow(_Change change) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 6,
            height: 6,
            margin: const EdgeInsets.only(right: 8, top: 6),
            decoration: BoxDecoration(
              color: change.color,
              shape: BoxShape.circle,
            ),
          ),
          Expanded(
            child: Text(
              change.text,
              style: TextStyle(
                fontSize: 14,
                color: isDark
                    ? const Color(0xFFB0B8D0)
                    : const Color(0xFF444444),
                height: 1.6,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
