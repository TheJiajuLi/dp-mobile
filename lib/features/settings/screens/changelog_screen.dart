import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../l10n/generated/app_localizations.dart';

// 最新版本号——每次发布前手动更新。设置页「更新日志」的"新动态"角标、
// 本页"当前版本"、以及已读判断都用它当唯一真相
const String kLatestVersion = 'v1.4.0';

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
    ChangeType.feature => AppColors.primary,
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
  ChangeType.feature => AppColors.primary,
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
      version: 'v1.4.0',
      date: '2026.07.18',
      changes: [
        _Change('极梦HD iPad版上线——侧边导航/三栏阅读/自适应断点', ChangeType.feature),
        _Change('HD首页/发现三栏布局——列表+阅读+目录联动', ChangeType.feature),
        _Change('HD极索/小梦/Notebook/设置/通知全部接通', ChangeType.feature),
        _Change('HD自适应断点——1024三栏/768双栏/窄屏单栏', ChangeType.feature),
        _Change('ArticleBodyView抽取——手机/HD共用一套正文渲染', ChangeType.feature),
        _Change('R语言内核接入——webR/WebAssembly/图表捕获', ChangeType.feature),
        _Change('R内核状态指示——加载中/就绪/不可用实时显示', ChangeType.feature),
        _Change('文章阅读页沉浸式Header——封面视差/标题渐隐渐显', ChangeType.feature),
        _Change('文章阅读页目录——BottomSheet/跳转定位/scroll-spy高亮', ChangeType.feature),
        _Change('公式自动编号——居中/右侧(n)/autoNumber开关', ChangeType.feature),
        _Change('参考文献Block——结构化条目/DOI自动抓取/GB/T样式', ChangeType.feature),
        _Change('用户协议页——原创声明/著作权存证/签署/撤回', ChangeType.feature),
        _Change('APNs推送通知基础设施配置', ChangeType.feature),
        _Change('极索推荐问题接入服务端题库——秒开/社区热点', ChangeType.improve),
        _Change('阅读页排版升级——字号/行高/标题层级/毛玻璃底栏', ChangeType.improve),
        _Change('专栏详情页深色主题适配', ChangeType.improve),
        _Change('Notebook描述生成代码——自然语言转Python', ChangeType.improve),
        _Change('SQL内核多表升级——所有DataFrame自动注册', ChangeType.improve),
        _Change('MySQL数据库从5.7升级至8.0', ChangeType.improve),
        _Change('Redis正式安装并配置开机自启', ChangeType.improve),
        _Change('文章阅读页代码块支持直接编辑——编辑/完成/重置', ChangeType.fix),
        _Change('小梦帮我写标题解析为heading块——目录可正确定位', ChangeType.fix),
        _Change('PDF导出行内LaTeX跳过代码内联/渲染失败回退', ChangeType.fix),
        _Change('PDF行内公式按字号比例缩放——统一字形大小', ChangeType.fix),
        _Change('Markdown块完整重写——受控controller/焦点驱动', ChangeType.fix),
        _Change('空白块Delete删除trim口径对齐修复', ChangeType.fix),
      ],
    ),
    _Version(
      version: 'v1.3.0',
      date: '2026.07.17',
      changes: [
        _Change('Notebook可视化Cell——绿色主题/matplotlib图表/保存图表', ChangeType.feature),
        _Change('Notebook描述生成代码——自然语言转Python/快捷示例/自动插入', ChangeType.feature),
        _Change(
          'Notebook SQL内核多表——所有DataFrame自动注册为SQLite表',
          ChangeType.feature,
        ),
        _Change('Notebook SQL动态可用表提示+AI感知表结构', ChangeType.feature),
        _Change('文章阅读页目录——Bottom Sheet/跳转定位/scroll-spy高亮', ChangeType.feature),
        _Change('文章阅读页数据集自动注入内核——进页静默执行', ChangeType.feature),
        _Change('阅读页数据集块折叠为琥珀色小卡片', ChangeType.feature),
        _Change('聊天消息删除——仅对自己不可见/云端同步', ChangeType.feature),
        _Change('问题分享聊天卡片——紫色渐变/写回答/查看详情', ChangeType.feature),
        _Change('注册邀请码统一入口——invite/founder/promo三表依次匹配', ChangeType.feature),
        _Change('元老邀请码DREAMINGPOLAR上线（限10名）', ChangeType.feature),
        _Change('创作者数据详情页接入真实接口——获赞趋势/互动分布/热门文章', ChangeType.feature),
        _Change('本月数据查看详情打通CreatorStatsScreen', ChangeType.feature),
        _Change('GitHub Actions自动部署——push main自动触发', ChangeType.feature),
        _Change('SMTP迁移企业邮箱support@dreamingpolar.com', ChangeType.improve),
        _Change('邮件Logo换成极梦彩虹弧形/消除「极极梦」预览文字', ChangeType.improve),
        _Change('极索推荐问题缓存优化——进页秒开/后台静默刷新', ChangeType.improve),
        _Change('Markdown块完整重写——受控controller/焦点驱动/标题渲染', ChangeType.fix),
        _Change('空白块Delete删除——trim口径对齐修复', ChangeType.fix),
        _Change('极索推荐问题请求体格式修复——AI真实生成', ChangeType.fix),
        _Change('文章详情页+发现页摘要LaTeX渲染统一', ChangeType.fix),
        _Change('PDF导出图片限宽515pt/单篇失败不中断整批', ChangeType.fix),
        _Change('聊天撤回消息后不自动弹键盘', ChangeType.fix),
        _Change('帮助与反馈页删除多余账号安全和会员支付入口', ChangeType.fix),
        _Change('注册页邀请码权益深色模式下文字可见', ChangeType.fix),
        _Change('私信问题分享豁免陌生人首条纯文字限制', ChangeType.fix),
        _Change('登录记录地名繁体字符级转换简体', ChangeType.fix),
      ],
    ),
    _Version(
      version: 'v1.2.0',
      date: '2026.07.16',
      changes: [
        _Change('Notebook AI辅助——查错/优化/解释/续写/转换语言（Pro）', ChangeType.feature),
        _Change('问题详情页任何人可回答——底部悬浮写回答按钮', ChangeType.feature),
        _Change('问题详情分享——论坛/群组/好友三种方式', ChangeType.feature),
        _Change('发布前原创声明——一次签署永久记录', ChangeType.feature),
        _Change('发布页工具栏新增Markdown块', ChangeType.feature),
        _Change('小梦帮我写/AI辅助流式打字机输出', ChangeType.feature),
        _Change('极索推荐问题每次进入刷新/下拉刷新', ChangeType.feature),
        _Change('小梦推荐问题每次进入App刷新——随机领域', ChangeType.feature),
        _Change('发布页今日灵感24小时AI刷新', ChangeType.feature),
        _Change('新用户注册后自动跳转创作指南', ChangeType.feature),
        _Change('各内容块工具栏加复制按钮', ChangeType.improve),
        _Change('滚动时自动隐藏键盘——私聊/群聊/Notebook/发布页', ChangeType.improve),
        _Change('小梦AI输出区域限高+滚动——打字机自动滚到底', ChangeType.improve),
        _Change('极索历史会话标题/气泡去掉语言指令前缀', ChangeType.improve),
        _Change('搜索页统一淡入动画/骨架屏/并行加载', ChangeType.improve),
        _Change('Notebook代码高亮接入/文件导入bytes兜底', ChangeType.improve),
        _Change('创作设置全面落地——可见性/自动保存/预览/默认块等', ChangeType.improve),
        _Change('ProMax文案改为「AI工具使用无限制」', ChangeType.improve),
        _Change('免费用户内容发布数量限制移除', ChangeType.improve),
        _Change('小梦帮我写公式跨行匹配修复/脏格式清理', ChangeType.fix),
        _Change('极索AI回答h4-h6标题正确渲染', ChangeType.fix),
        _Change('LaTeX结尾孤立反斜杠自动清理', ChangeType.fix),
        _Change('Notebook编辑器运行代码无需Pro门禁', ChangeType.fix),
        _Change('代码编辑器禁用智能标点/弯引号自动替换', ChangeType.fix),
        _Change('空白Cell按Delete直接删除', ChangeType.fix),
        _Change('登录记录繁体字统一改为简体', ChangeType.fix),
        _Change('转载设置落地——关闭时隐藏PDF导出和分享按钮', ChangeType.fix),
      ],
    ),
    _Version(
      version: 'v1.1.0',
      date: '2026.07.15',
      changes: [
        _Change('创作者中心全功能打通——数据分析/创作指南/邀请好友/创作设置', ChangeType.feature),
        _Change('邀请好友系统——专属邀请码/双方各得7天Pro', ChangeType.feature),
        _Change('Notebook 文件导入——CSV/Excel/JSON/TXT数据集注入内核', ChangeType.feature),
        _Change('付费管理页面——订阅详情/套餐切换/管理入口', ChangeType.feature),
        _Change('小梦帮我写重设计——对话式问答/生成内容填入编辑器', ChangeType.feature),
        _Change('专栏管理支持自定义封面——图片上传/预设配色方案', ChangeType.feature),
        _Change('元老创作者专属卡片——ProMax剩余天数/永久Pro状态', ChangeType.feature),
        _Change('更新日志新动态角标——已读后自动消失', ChangeType.feature),
        _Change('小梦回答打字机逐字渲染效果', ChangeType.improve),
        _Change('Notebook 数据集Cell橙色标识/内核状态指示/重置按钮', ChangeType.improve),
        _Change('Block间插入+号——滚动时展开/静止收起', ChangeType.improve),
        _Change('空内容块按Delete直接消失', ChangeType.improve),
        _Change('非Python代码块点运行显示友好提示', ChangeType.improve),
        _Change('极索/发布页文字公式混排渲染', ChangeType.fix),
        _Change('Pro角标在别人主页正常显示', ChangeType.fix),
        _Change('小梦代码块偶发残缺问题（SSE行缓冲修复）', ChangeType.fix),
        _Change('群聊退出/发消息后标记已读', ChangeType.fix),
        _Change('极光创作者权益修正——获得Pro而非ProMax', ChangeType.fix),
      ],
    ),
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
          // 极梦极光弧线 logo（最新款）
          SvgPicture.asset('assets/icons/logo_aurora.svg', width: 60),
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
