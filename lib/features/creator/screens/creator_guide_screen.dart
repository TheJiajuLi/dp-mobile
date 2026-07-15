import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_client.dart';
import '../../auth/auth_service.dart';
import 'creator_center_screen.dart' show auroraNoteTarget;

// 创作指南——这是一张「帮助/上手」页，内容以 app 内置的静态 how-to 为主
// （指南卡片没有后端文章源，硬接接口只能是空的）。真实数据只接两处：
//   · 快速入门清单里「发布第一篇 / 发布10篇」的完成状态 → 本人已发布篇数
//   · 底部「离极光还差 X 篇」→ 同一份已发布篇数 vs auroraNoteTarget(10)
// 指南卡片点开是内置的静态讲解，不是编造的后端数据。
const _primary = Color(0xFF6366F1);

class CreatorGuideScreen extends ConsumerStatefulWidget {
  const CreatorGuideScreen({super.key});

  @override
  ConsumerState<CreatorGuideScreen> createState() => _CreatorGuideScreenState();
}

class _CreatorGuideScreenState extends ConsumerState<CreatorGuideScreen> {
  int _cat = 0; // 分类标签下标
  int _published = 0;
  bool _isAurora = false;
  bool _loading = true;

  static const _cats = ['全部', '入门', 'LaTeX', '代码', 'Notebook', '增长'];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final user = ref.read(currentUserProvider);
    if (user == null) {
      setState(() => _loading = false);
      return;
    }
    final res = await ref
        .read(apiClientProvider)
        .get(
          '/auth/tutorials',
          queryParameters: {
            'author': user.username,
            'status': 'published',
            'limit': 1,
          },
        );
    if (!mounted) return;
    setState(() {
      _published = res.success && res.data != null
          ? (res.data['total'] as num?)?.toInt() ?? 0
          : 0;
      _isAurora = user.isAuroraCreator;
      _loading = false;
    });
  }

  // 指南卡片按分类过滤：全部=不过滤，否则匹配主分类或 tags
  List<_Guide> get _filtered {
    if (_cat == 0) return _guides;
    final key = _cats[_cat];
    return _guides.where((g) => g.cat == key || g.tags.contains(key)).toList();
  }

  // 清单只在「全部 / 入门」下出现（它本就是入门流程）
  bool get _showChecklist => _cat == 0 || _cat == 1;
  // 极光提示只在「全部」、且还没入选时出现
  bool get _showAurora => _cat == 0 && !_isAurora;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark
        ? Theme.of(context).scaffoldBackgroundColor
        : const Color(0xFFFAFAF8);
    final card = isDark ? const Color(0xFF17171F) : Colors.white;
    final border = isDark
        ? Colors.white.withValues(alpha: 0.06)
        : const Color(0xFFEDEDE9);
    final ink = isDark ? const Color(0xFFF0F2F8) : const Color(0xFF111111);
    final muted = isDark ? const Color(0xFF7A80A0) : const Color(0xFF888888);

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: isDark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
      child: Scaffold(
        backgroundColor: bg,
        appBar: AppBar(
          backgroundColor: bg,
          elevation: 0,
          scrolledUnderElevation: 0,
          centerTitle: false,
          titleSpacing: 0,
          leading: IconButton(
            icon: Icon(Icons.arrow_back_ios_new, size: 18, color: ink),
            onPressed: () => context.pop(),
          ),
          title: Text(
            '创作指南',
            style: TextStyle(
              fontSize: 19,
              fontWeight: FontWeight.w700,
              color: ink,
            ),
          ),
        ),
        body: ListView(
          padding: const EdgeInsets.only(bottom: 36),
          children: [
            _buildHero(),
            _buildCategoryTabs(isDark, ink, border),
            if (_showChecklist) _buildChecklist(card, border, ink, muted),
            _buildGuideSection(card, border, ink, muted),
            if (_showAurora && !_loading) _buildAuroraCard(),
          ],
        ),
      ),
    );
  }

  // —————————————————————————————— Hero
  Widget _buildHero() {
    return Container(
      margin: const EdgeInsets.fromLTRB(14, 8, 14, 4),
      padding: const EdgeInsets.fromLTRB(22, 24, 22, 24),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF1D1B38), Color(0xFF131228)],
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Stack(
          children: [
            Positioned(
              right: -30,
              top: -20,
              child: Container(
                width: 130,
                height: 130,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFF6366F1).withValues(alpha: 0.14),
                ),
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'CREATOR GUIDE',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.5,
                    color: Color(0xFF8B87F5),
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  '在极梦创作\n你需要知道的一切',
                  style: TextStyle(
                    fontSize: 23,
                    height: 1.28,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  '从第一篇文章到极光创作者，\n我们帮你走得更快。',
                  style: TextStyle(
                    fontSize: 13.5,
                    height: 1.5,
                    color: Colors.white.withValues(alpha: 0.55),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // —————————————————————————————— 分类标签
  Widget _buildCategoryTabs(bool isDark, Color ink, Color border) {
    return SizedBox(
      height: 38,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
        itemCount: _cats.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (ctx, i) {
          final selected = _cat == i;
          return GestureDetector(
            onTap: () => setState(() => _cat = i),
            child: Container(
              alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                color: selected
                    ? (isDark ? Colors.white : const Color(0xFF111111))
                    : (isDark ? const Color(0xFF17171F) : Colors.white),
                borderRadius: BorderRadius.circular(20),
                border: selected ? null : Border.all(color: border, width: 0.5),
              ),
              child: Text(
                _cats[i],
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                  color: selected
                      ? (isDark ? const Color(0xFF111111) : Colors.white)
                      : ink,
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  // —————————————————————————————— 快速入门清单
  Widget _buildChecklist(Color card, Color border, Color ink, Color muted) {
    final steps = <_Step>[
      _Step(
        '注册并完善个人资料',
        done: true,
        onTap: () {
          context.push('/edit-profile');
        },
      ),
      _Step(
        '发布第一篇文章',
        done: _published >= 1,
        onTap: () {
          context.push('/publish');
        },
      ),
      _Step(
        '在文章中插入 LaTeX 公式',
        done: false,
        onTap: () {
          _openGuide(_guides.firstWhere((g) => g.id == 'latex'));
        },
      ),
      _Step(
        '添加可运行代码块',
        done: false,
        onTap: () {
          _openGuide(_guides.firstWhere((g) => g.id == 'code'));
        },
      ),
      _Step(
        '发布 10 篇文章，申请极光计划',
        done: _published >= auroraNoteTarget,
        onTap: () {
          context.push('/creator/aurora');
        },
      ),
    ];

    return Container(
      margin: const EdgeInsets.fromLTRB(14, 12, 14, 0),
      decoration: BoxDecoration(
        color: card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: border, width: 0.5),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
            child: Row(
              children: [
                const Text('🚀', style: TextStyle(fontSize: 16)),
                const SizedBox(width: 8),
                Text(
                  '快速入门清单',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: ink,
                  ),
                ),
              ],
            ),
          ),
          ...List.generate(steps.length, (i) {
            return _buildStepRow(
              index: i,
              step: steps[i],
              showDivider: i != steps.length - 1,
              border: border,
              ink: ink,
              muted: muted,
            );
          }),
        ],
      ),
    );
  }

  Widget _buildStepRow({
    required int index,
    required _Step step,
    required bool showDivider,
    required Color border,
    required Color ink,
    required Color muted,
  }) {
    return InkWell(
      onTap: step.onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          border: showDivider
              ? Border(bottom: BorderSide(color: border, width: 0.5))
              : null,
        ),
        child: Row(
          children: [
            // 完成=绿勾圈；未完成=淡紫数字圈
            Container(
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: step.done
                    ? const Color(0xFF22C55E).withValues(alpha: 0.14)
                    : _primary.withValues(alpha: 0.12),
              ),
              child: Center(
                child: step.done
                    ? const Icon(
                        Icons.check,
                        size: 14,
                        color: Color(0xFF16A34A),
                      )
                    : Text(
                        '${index + 1}',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: _primary,
                        ),
                      ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                step.label,
                style: TextStyle(
                  fontSize: 14.5,
                  fontWeight: FontWeight.w500,
                  color: step.done ? muted : ink,
                ),
              ),
            ),
            if (step.done)
              const Icon(Icons.check, size: 18, color: Color(0xFF16A34A))
            else
              Icon(Icons.chevron_right, size: 20, color: muted),
          ],
        ),
      ),
    );
  }

  // —————————————————————————————— 精选指南卡片
  Widget _buildGuideSection(Color card, Color border, Color ink, Color muted) {
    final list = _filtered;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 22, 14, 8),
          child: Text(
            _cat == 0 ? '精选指南' : '${_cats[_cat]} · ${list.length} 篇',
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: muted,
            ),
          ),
        ),
        ...list.map((g) => _buildGuideCard(g, card, border, ink, muted)),
      ],
    );
  }

  Widget _buildGuideCard(
    _Guide g,
    Color card,
    Color border,
    Color ink,
    Color muted,
  ) {
    return GestureDetector(
      onTap: () => _openGuide(g),
      child: Container(
        margin: const EdgeInsets.fromLTRB(14, 0, 14, 10),
        padding: const EdgeInsets.fromLTRB(14, 14, 12, 12),
        decoration: BoxDecoration(
          color: card,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: border, width: 0.5),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: g.iconBg,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(g.icon, size: 21, color: g.iconColor),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        g.title,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: ink,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        g.desc,
                        style: TextStyle(
                          fontSize: 12.5,
                          height: 1.4,
                          color: muted,
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Icon(Icons.chevron_right, size: 20, color: muted),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Divider(height: 1, thickness: 0.5, color: border),
            const SizedBox(height: 10),
            Row(
              children: [
                ...g.tags.map((t) => _tagChip(t)),
                const Spacer(),
                Text(
                  '${g.minutes} 分钟阅读',
                  style: TextStyle(fontSize: 11.5, color: muted),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _tagChip(String tag) {
    // 按分类给标签一点色彩区分，跟卡片图标呼应
    final map = {
      '入门': const [Color(0xFFE8F7EE), Color(0xFF16A34A)],
      'LaTeX': const [Color(0xFFEDEBFF), Color(0xFF6D5DF6)],
      '代码': const [Color(0xFFE9F7EF), Color(0xFF16A34A)],
      'Notebook': const [Color(0xFFFDF0DC), Color(0xFFD97706)],
      '增长': const [Color(0xFFEDEBFF), Color(0xFF6D5DF6)],
    };
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final c = map[tag] ?? const [Color(0xFFF0F0F0), Color(0xFF888888)];
    return Container(
      margin: const EdgeInsets.only(right: 6),
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: isDark ? c[1].withValues(alpha: 0.16) : c[0],
        borderRadius: BorderRadius.circular(7),
      ),
      child: Text(
        tag,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: c[1],
        ),
      ),
    );
  }

  // —————————————————————————————— 底部极光进度
  Widget _buildAuroraCard() {
    final remain = auroraNoteTarget - _published;
    final reached = remain <= 0;
    return GestureDetector(
      onTap: () => context.push('/creator/aurora'),
      child: Container(
        margin: const EdgeInsets.fromLTRB(14, 12, 14, 0),
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF15291D), Color(0xFF0E2016)],
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Text('✨', style: TextStyle(fontSize: 15)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    reached ? '已满足发布篇数，去查看极光进度' : '离极光创作者还有 $remain 篇',
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF5FD98C),
                    ),
                  ),
                ),
                const Icon(
                  Icons.chevron_right,
                  size: 20,
                  color: Color(0xFF4E7A5E),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              reached
                  ? '发布篇数已达标，还差点赞/粉丝等其他条件，点开看看还缺什么。'
                  : '再发布 $remain 篇文章即可达到入选条件，免费获得 PRO 会员 + 流量分成。',
              style: const TextStyle(
                fontSize: 13,
                height: 1.5,
                color: Color(0xFF7C9885),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // —————————————————————————————— 指南详情（内置静态内容）
  void _openGuide(_Guide g) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final card = isDark ? const Color(0xFF17171F) : const Color(0xFFFAFAF8);
    final ink = isDark ? const Color(0xFFF0F2F8) : const Color(0xFF111111);
    final body = isDark ? const Color(0xFFC7CBDC) : const Color(0xFF444444);
    final muted = isDark ? const Color(0xFF7A80A0) : const Color(0xFF888888);

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(ctx).size.height * 0.82,
        ),
        decoration: BoxDecoration(
          color: card,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.only(top: 10, bottom: 6),
              decoration: BoxDecoration(
                color: Colors.grey.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(99),
              ),
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(22, 14, 22, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: g.iconBg,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Icon(g.icon, size: 22, color: g.iconColor),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                g.title,
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w700,
                                  color: ink,
                                ),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                '${g.tags.join(' · ')}   ${g.minutes} 分钟阅读',
                                style: TextStyle(fontSize: 12, color: muted),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    ..._buildBody(g.body, ink, body),
                  ],
                ),
              ),
            ),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(22, 6, 22, 12),
                child: SizedBox(
                  width: double.infinity,
                  child: TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    style: TextButton.styleFrom(
                      backgroundColor: const Color(0xFF111111),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text(
                      '知道了',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // 把内置正文（【小标题】+段落）渲染成层级文本
  List<Widget> _buildBody(String raw, Color ink, Color body) {
    final blocks = raw.trim().split('\n\n');
    final widgets = <Widget>[];
    for (final b in blocks) {
      final t = b.trim();
      if (t.isEmpty) continue;
      if (t.startsWith('【') && t.endsWith('】')) {
        widgets.add(
          Padding(
            padding: EdgeInsets.only(top: widgets.isEmpty ? 0 : 18, bottom: 6),
            child: Text(
              t.substring(1, t.length - 1),
              style: TextStyle(
                fontSize: 14.5,
                fontWeight: FontWeight.w700,
                color: ink,
              ),
            ),
          ),
        );
      } else {
        widgets.add(
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text(
              t,
              style: TextStyle(fontSize: 14, height: 1.7, color: body),
            ),
          ),
        );
      }
    }
    return widgets;
  }
}

class _Step {
  final String label;
  final bool done;
  final VoidCallback onTap;
  const _Step(this.label, {required this.done, required this.onTap});
}

class _Guide {
  final String id;
  final String cat;
  final IconData icon;
  final Color iconBg;
  final Color iconColor;
  final String title;
  final String desc;
  final List<String> tags;
  final int minutes;
  final String body;
  const _Guide({
    required this.id,
    required this.cat,
    required this.icon,
    required this.iconBg,
    required this.iconColor,
    required this.title,
    required this.desc,
    required this.tags,
    required this.minutes,
    required this.body,
  });
}

// 内置指南内容——静态 how-to，不来自后端。改文案在这里改。
const _guides = <_Guide>[
  _Guide(
    id: 'first',
    cat: '入门',
    icon: Icons.edit_note_outlined,
    iconBg: Color(0xFFE8F7EE),
    iconColor: Color(0xFF16A34A),
    title: '发布你的第一篇文章',
    desc: '从新建、写作到发布的完整流程',
    tags: ['入门'],
    minutes: 2,
    body: '''第一次发文章？跟着这几步，几分钟就能发布。

【新建文章】
点底部的「+」或创作入口，进入编辑器。

【写作】
先写标题，再用文字、公式块、代码块、图片自由组合正文。内容会自动保存草稿，不怕丢。

【完善信息】
发布前填好摘要、封面和标签——这些决定别人在信息流里第一眼看到什么。

【发布】
点「发布」即可。发布后可在「作品管理」里随时编辑、设为私密或下架。''',
  ),
  _Guide(
    id: 'latex',
    cat: 'LaTeX',
    icon: Icons.functions,
    iconBg: Color(0xFFEDEBFF),
    iconColor: Color(0xFF6D5DF6),
    title: '如何在极梦写 LaTeX 公式',
    desc: '行内公式、块级公式、多行对齐的完整写法',
    tags: ['LaTeX', '入门'],
    minutes: 3,
    body: '''极梦支持三种公式写法，覆盖从行内到多行推导的所有场景。

【行内公式】
用一对 \$ 包住，例如 \$E=mc^2\$，公式会嵌在正文里、跟文字同一行。适合在句子中提到某个变量或短表达式。

【块级公式】
新建一个「公式块」，或用一对 \$\$ 包住，公式会单独成行、居中显示。适合重要的定义、定理和推导。

【多行对齐】
在块级公式里使用 aligned 环境，用 & 标记每行的对齐位置、用两个反斜杠换行，就能让等号整齐地竖直对齐。

小技巧：编辑器工具栏的公式按钮可直接插入公式块，常用符号有面板可选，不必背命令。''',
  ),
  _Guide(
    id: 'code',
    cat: '代码',
    icon: Icons.code,
    iconBg: Color(0xFFE9F7EF),
    iconColor: Color(0xFF16A34A),
    title: '添加可运行的 Python 代码块',
    desc: '让读者直接运行你的代码，验证分析结论',
    tags: ['代码'],
    minutes: 5,
    body: '''让读者不只是「看」你的代码，而是直接在文章里点运行、亲眼验证你的结论。

【插入代码块】
在编辑器里新建「代码块」，粘贴你的 Python 代码，选择语言为 Python。

【标记为可运行】
打开代码块的「可运行」开关，读者端就会出现运行按钮，点击即可在云端执行并看到输出。

【最佳实践】
每段代码保持独立、能单独跑通；在代码前用一段文字说明它要验证什么；输出较长时先给关键结论再放完整结果。

可运行代码是极梦区别于普通图文的核心能力，善用它能显著提升文章的可信度。''',
  ),
  _Guide(
    id: 'notebook',
    cat: 'Notebook',
    icon: Icons.menu_book_outlined,
    iconBg: Color(0xFFFDF0DC),
    iconColor: Color(0xFFD97706),
    title: 'Notebook 一键发布为文章',
    desc: '数据分析完成后，一键转化为完整的知识文章',
    tags: ['Notebook'],
    minutes: 4,
    body: '''做完数据分析后不用重新排版——把 Notebook 一键转成结构完整的知识文章。

【导入 Notebook】
在发布页选择「从 Notebook 导入」，上传你的 .ipynb 文件。

【自动转换】
Markdown 单元会变成正文段落，代码单元会变成可运行代码块，图表和输出一并保留。

【润色发布】
导入后可以像普通文章一样增删、调整顺序、补充讲解，确认无误后发布。

适合把探索性的分析过程，快速沉淀成一篇能被别人读懂、复现的文章。''',
  ),
  _Guide(
    id: 'growth',
    cat: '增长',
    icon: Icons.trending_up,
    iconBg: Color(0xFFEDEBFF),
    iconColor: Color(0xFF6D5DF6),
    title: '如何快速涨粉获得更多曝光',
    desc: '选题策略、标题优化、内容结构的实战技巧',
    tags: ['增长'],
    minutes: 6,
    body: '''好内容也需要被看见。这几个实战技巧能帮你的文章获得更多曝光和关注。

【选题策略】
优先写「有具体问题、有明确读者」的题目，小而深比大而全更容易被搜索和推荐命中。

【标题优化】
标题讲清楚「读者能得到什么」，用具体数字和关键词，避免空泛的形容词。

【内容结构】
开头三句话说清价值，中间用小标题分段，重要结论前置。可运行代码和公式能显著提升停留时长。

【持续更新】
稳定的发布节奏比偶尔爆发更利于涨粉，同一主题成系列更容易沉淀忠实读者。''',
  ),
];
