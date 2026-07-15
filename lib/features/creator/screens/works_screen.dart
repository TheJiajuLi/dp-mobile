import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_client.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/models/tutorial_model.dart';
import '../../../shared/utils/topic_badge.dart';
import '../../auth/auth_service.dart';

const _primary = Color(0xFF6366F1);

// 教程的 status 是数据库 ENUM('draft','published','deleted')，只有这三个
// 合法值——这里的"下架"不是调用 DELETE /auth/tutorials/:id 真删（那个
// 接口会连带清掉评论/点赞/收藏，且没有恢复入口，跟"下架"这个词的直觉不
// 符），而是把 status 改成 'deleted'：内容还在，公开列表里不再出现，且
// 可以在"下架"tab里一键恢复上架。真正的永久删除只在草稿/已下架内容里
// 提供，那两种情况下数据本来就还没公开或已经不公开，删掉不会有社交层面
// 的连带损失
enum _WorkTab { all, published, draft, archived }

extension on _WorkTab {
  String get label => switch (this) {
    _WorkTab.all => '全部',
    _WorkTab.published => '已发布',
    _WorkTab.draft => '草稿',
    _WorkTab.archived => '下架',
  };
}

class WorksScreen extends ConsumerStatefulWidget {
  final int initialTab;
  const WorksScreen({super.key, this.initialTab = 0});
  @override
  ConsumerState<WorksScreen> createState() => _WorksScreenState();
}

class _WorksScreenState extends ConsumerState<WorksScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabCtrl;
  final Map<_WorkTab, List<TutorialModel>> _lists = {
    _WorkTab.published: [],
    _WorkTab.draft: [],
    _WorkTab.archived: [],
  };
  final Map<_WorkTab, bool> _loading = {
    _WorkTab.published: true,
    _WorkTab.draft: true,
    _WorkTab.archived: true,
  };
  bool _searching = false;
  final _searchCtrl = TextEditingController();
  String _query = '';

  bool get _isDark => Theme.of(context).brightness == Brightness.dark;
  Color get _bg => _isDark ? AppColors.darkBg : const Color(0xFFFAFAF8);
  Color get _card => _isDark ? AppColors.darkCard : Colors.white;
  Color get _ink =>
      _isDark ? AppColors.darkTextPrimary : const Color(0xFF1A1A1A);
  Color get _muted =>
      _isDark ? AppColors.darkTextSecondary : const Color(0xFF999999);
  Color get _border => _isDark ? AppColors.darkBorder : const Color(0xFFF0F0F0);
  Color get _fill =>
      _isDark ? Colors.white.withValues(alpha: 0.06) : const Color(0xFFF5F5F7);

  @override
  void initState() {
    super.initState();
    // 参考图里"全部作品"是带 tab 的第一项，实际 tab 数从原来的 3 个
    // （已发布/草稿/下架）变成 4 个（全部/已发布/草稿/下架），initialTab
    // 是从创作者中心"草稿箱"卡片带过来的，原来对应 index 1（草稿），
    // 现在往后挪一位变成 index 2
    final rawInitial = widget.initialTab.clamp(0, 2);
    final initialIndex = rawInitial == 0 ? 0 : rawInitial + 1;
    _tabCtrl = TabController(
      length: 4,
      vsync: this,
      initialIndex: initialIndex.clamp(0, 3),
    );
    _loadAll();
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  String _statusFor(_WorkTab tab) => switch (tab) {
    _WorkTab.all => '',
    _WorkTab.published => 'published',
    _WorkTab.draft => 'draft',
    _WorkTab.archived => 'deleted',
  };

  Future<void> _loadAll() async {
    await Future.wait(
      [_WorkTab.published, _WorkTab.draft, _WorkTab.archived].map(_load),
    );
  }

  Future<void> _load(_WorkTab tab) async {
    final user = ref.read(currentUserProvider);
    if (user == null) return;
    final res = await ref
        .read(apiClientProvider)
        .get(
          '/auth/tutorials',
          queryParameters: {
            'author': user.username,
            'status': _statusFor(tab),
            'limit': 50,
          },
        );
    if (!mounted) return;
    var list = <TutorialModel>[];
    if (res.success && res.data != null) {
      list = ((res.data['tutorials'] as List?) ?? [])
          .map((j) => TutorialModel.fromJson(j as Map<String, dynamic>))
          .where((t) => t.userId == user.id)
          .toList();
    }
    setState(() {
      _lists[tab] = list;
      _loading[tab] = false;
    });
  }

  // 下架/恢复/删除都要"整份覆盖"式的 PUT，先把这篇教程的完整内容（含
  // blocks）拉回来，只改 status 一个字段，其余原样传回去，不然
  // updateTutorial 会把 blocks/tags 清空成默认值
  Future<bool> _changeStatus(String id, String newStatus) async {
    final api = ref.read(apiClientProvider);
    final full = await api.get('/auth/tutorials/$id');
    if (!full.success || full.data == null) return false;
    final t = full.data as Map;
    final res = await api.put(
      '/auth/tutorials/$id',
      data: {
        'title': t['title'],
        'summary': t['summary'],
        'cover_image': t['cover_image'],
        'tags': t['tags'],
        'blocks': t['blocks'],
        'status': newStatus,
      },
    );
    return res.success;
  }

  Future<void> _confirmAndRun({
    required String title,
    required String message,
    required Future<bool> Function() action,
  }) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消', style: TextStyle(color: Colors.grey)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('确定', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final ok = await action();
    if (!mounted) return;
    if (ok) {
      await _loadAll();
    } else {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('操作失败，请重试')));
    }
  }

  List<TutorialModel> get _allWorks => [
    ..._lists[_WorkTab.published] ?? [],
    ..._lists[_WorkTab.draft] ?? [],
    ..._lists[_WorkTab.archived] ?? [],
  ];

  int get _totalViews => _allWorks.fold(0, (s, t) => s + t.views);
  int get _totalLikes => _allWorks.fold(0, (s, t) => s + t.likes);

  String _formatCount(int n) {
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}k';
    return '$n';
  }

  // 后端没有 updatedAt，"继续编辑"只能退而求其次用 createdAt 排序，
  // 不是真的"最近编辑"，是"最近创建"的草稿——没有更精确的数据源可拼
  TutorialModel? get _latestDraft {
    final drafts = _lists[_WorkTab.draft] ?? [];
    if (drafts.isEmpty) return null;
    return ([
      ...drafts,
    ]..sort((a, b) => b.createdAt.compareTo(a.createdAt))).first;
  }

  String get _greeting {
    final h = DateTime.now().hour;
    if (h < 5) return '夜深了';
    if (h < 12) return '早上好';
    if (h < 18) return '下午好';
    return '晚上好';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _hero(),
            Container(
              color: _bg,
              child: TabBar(
                controller: _tabCtrl,
                isScrollable: true,
                labelColor: _primary,
                unselectedLabelColor: _muted,
                indicatorColor: _primary,
                tabs: _WorkTab.values
                    .map((t) => Tab(text: '${t.label} ${_countFor(t)}'))
                    .toList(),
              ),
            ),
            Expanded(
              // 点空白处收起键盘
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => FocusScope.of(context).unfocus(),
                child: TabBarView(
                  controller: _tabCtrl,
                  children: _WorkTab.values.map(_buildTab).toList(),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  int _countFor(_WorkTab tab) =>
      tab == _WorkTab.all ? _allWorks.length : (_lists[tab]?.length ?? 0);

  // 把原来的"标题栏+四格统计卡"合并成一张渐变Hero卡——问候语+核心数据+
  // "继续写"入口一次给全，比一整排小方块更有"创作台"的感觉，不是后台
  // 管理页。收藏数/评论数没有批量接口字段，跟原来一样只保留真实拿得到的
  // 作品数/阅读量/点赞数三项，不硬凑
  Widget _hero() {
    final user = ref.watch(currentUserProvider);
    final draft = _latestDraft;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 10, 16, 14),
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF6366F1), Color(0xFF818CF8)],
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: _primary.withValues(alpha: 0.28),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              GestureDetector(
                onTap: () => context.pop(),
                child: const Icon(
                  Icons.arrow_back,
                  size: 20,
                  color: Colors.white,
                ),
              ),
              const Spacer(),
              GestureDetector(
                onTap: () => setState(() {
                  _searching = !_searching;
                  if (!_searching) {
                    _searchCtrl.clear();
                    _query = '';
                  }
                }),
                child: Icon(
                  _searching ? Icons.close : Icons.search,
                  size: 20,
                  color: Colors.white,
                ),
              ),
              const SizedBox(width: 14),
              GestureDetector(
                onTap: () => ScaffoldMessenger.of(
                  context,
                ).showSnackBar(const SnackBar(content: Text('批量操作即将上线，敬请期待'))),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Text(
                    '批量',
                    style: TextStyle(fontSize: 12, color: Colors.white),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            '$_greeting${(user?.username.isNotEmpty ?? false) ? '，${user!.username}' : ''}',
            style: const TextStyle(
              fontSize: 19,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            '继续你的创作',
            style: TextStyle(fontSize: 13, color: Color(0xE6FFFFFF)),
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              _heroStat('${_allWorks.length}', '作品'),
              _heroStat(_formatCount(_totalViews), '阅读'),
              _heroStat(_formatCount(_totalLikes), '点赞'),
            ],
          ),
          if (draft != null) ...[
            const SizedBox(height: 16),
            GestureDetector(
              onTap: () => context.push('/publish/${draft.id}'),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.edit_outlined, size: 15, color: _primary),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        '继续写「${draft.title}」',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: _primary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _heroStat(String value, String label) {
    return Padding(
      padding: const EdgeInsets.only(right: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 1),
          Text(
            label,
            style: const TextStyle(fontSize: 11, color: Color(0xB3FFFFFF)),
          ),
        ],
      ),
    );
  }

  Widget _buildTab(_WorkTab tab) {
    final isAll = tab == _WorkTab.all;
    final anyLoading = isAll
        ? _loading.values.any((v) => v)
        : _loading[tab] == true;
    if (anyLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    var list = isAll ? _allWorks : (_lists[tab] ?? []);
    if (_query.isNotEmpty) {
      list = list
          .where((t) => t.title.toLowerCase().contains(_query.toLowerCase()))
          .toList();
    }
    if (list.isEmpty) {
      if (_query.isNotEmpty) {
        return Center(
          child: Text('没有匹配的作品', style: TextStyle(fontSize: 13, color: _muted)),
        );
      }
      return _emptyState(tab);
    }
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (_searching) ...[
          TextField(
            controller: _searchCtrl,
            autofocus: true,
            onChanged: (v) => setState(() => _query = v),
            style: TextStyle(color: _ink),
            decoration: InputDecoration(
              hintText: '搜索作品标题',
              prefixIcon: const Icon(Icons.search, size: 18),
              filled: true,
              fillColor: _fill,
              contentPadding: const EdgeInsets.symmetric(vertical: 10),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide.none,
              ),
            ),
          ),
          const SizedBox(height: 14),
        ],
        ...list.map(
          (t) => Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _workCard(isAll ? _tabFor(t) : tab, t),
          ),
        ),
      ],
    );
  }

  // 原来空状态只有一行灰字，太单薄。换成柔和渐变图标胶囊+标题+一句引导
  // 文案+创建入口——下架tab没有"创建"的意义，不给CTA
  Widget _emptyState(_WorkTab tab) {
    final (icon, title, subtitle) = switch (tab) {
      _WorkTab.all => (
        Icons.auto_stories_outlined,
        '还没有任何作品',
        '分享知识、记录思考，建立属于自己的知识宇宙',
      ),
      _WorkTab.published => (
        Icons.auto_stories_outlined,
        '还没有发布的作品',
        '完成一篇创作，分享给更多人',
      ),
      _WorkTab.draft => (Icons.edit_note_outlined, '草稿箱是空的', '想法先存起来，随时回来完成它'),
      _WorkTab.archived => (Icons.inventory_2_outlined, '没有已下架的内容', ''),
    };
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  colors: [
                    _primary.withValues(alpha: _isDark ? 0.2 : 0.12),
                    _primary.withValues(alpha: 0),
                  ],
                ),
                shape: BoxShape.circle,
              ),
              child: Icon(
                icon,
                size: 28,
                color: _primary.withValues(alpha: 0.7),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              title,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: _ink,
              ),
            ),
            if (subtitle.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                subtitle,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12.5, color: _muted, height: 1.5),
              ),
            ],
            if (tab != _WorkTab.archived) ...[
              const SizedBox(height: 20),
              GestureDetector(
                onTap: () => context.push('/publish'),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: _primary,
                    borderRadius: BorderRadius.circular(99),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.add, size: 16, color: Colors.white),
                      SizedBox(width: 4),
                      Text(
                        '创建新作品',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  _WorkTab _tabFor(TutorialModel t) {
    if (_lists[_WorkTab.draft]?.any((x) => x.id == t.id) == true) {
      return _WorkTab.draft;
    }
    if (_lists[_WorkTab.archived]?.any((x) => x.id == t.id) == true) {
      return _WorkTab.archived;
    }
    return _WorkTab.published;
  }

  Widget _workCard(_WorkTab tab, TutorialModel t) {
    final rule = matchedTopicRuleFor(t.tags);
    final bg = rule?.bg ?? const Color(0xFFF5F5F5);
    final fg = rule?.fg ?? const Color(0xFF999999);
    final categoryLabel = topicCategoryLabelFor(t.tags);
    final time = DateTime.fromMillisecondsSinceEpoch(t.createdAt);
    final timeLabel =
        '${time.year}-${time.month.toString().padLeft(2, '0')}-'
        '${time.day.toString().padLeft(2, '0')}';

    return Container(
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _border, width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: bg,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(Icons.description_outlined, color: fg, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              t.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: _ink,
                              ),
                            ),
                          ),
                          if (categoryLabel != null) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: bg,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                categoryLabel,
                                style: TextStyle(fontSize: 10, color: fg),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          _statusChip(tab),
                          const SizedBox(width: 8),
                          Text(
                            timeLabel,
                            style: TextStyle(
                              fontSize: 11.5,
                              color: _isDark
                                  ? AppColors.darkTextMuted
                                  : const Color(0xFFC7C7CC),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Icon(
                            Icons.visibility_outlined,
                            size: 13,
                            color: _muted,
                          ),
                          const SizedBox(width: 3),
                          Text(
                            '${t.views}',
                            style: TextStyle(fontSize: 12, color: _muted),
                          ),
                          const SizedBox(width: 10),
                          Icon(Icons.favorite_border, size: 13, color: _muted),
                          const SizedBox(width: 3),
                          Text(
                            '${t.likes}',
                            style: TextStyle(fontSize: 12, color: _muted),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Container(
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: _border, width: 0.5)),
            ),
            child: Row(children: _actionsFor(tab, t)),
          ),
        ],
      ),
    );
  }

  Widget _statusChip(_WorkTab tab) {
    final (label, color) = switch (tab) {
      _WorkTab.published => ('已发布', const Color(0xFF16A34A)),
      _WorkTab.draft => ('草稿', const Color(0xFFD97706)),
      _WorkTab.archived => ('已下架', const Color(0xFF999999)),
      _WorkTab.all => ('', const Color(0xFF999999)),
    };
    if (label.isEmpty) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }

  List<Widget> _actionsFor(_WorkTab tab, TutorialModel t) {
    switch (tab) {
      case _WorkTab.all:
      case _WorkTab.published:
        return [
          _actionBtn('编辑', Icons.edit_outlined, _actionInk, () {
            context.push('/publish/${t.id}');
          }),
          _actionBtn('数据', Icons.bar_chart_outlined, _actionInk, () {
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(const SnackBar(content: Text('数据详情即将上线，敬请期待')));
          }),
          _actionBtn('下架', Icons.visibility_off_outlined, Colors.red, () {
            _confirmAndRun(
              title: '下架这篇内容？',
              message: '下架后读者将看不到这篇内容，你可以随时在"下架"里恢复上架。',
              action: () => _changeStatus(t.id, 'deleted'),
            );
          }),
        ];
      case _WorkTab.draft:
        return [
          _actionBtn('编辑', Icons.edit_outlined, _actionInk, () {
            context.push('/publish/${t.id}');
          }),
          _actionBtn('删除', Icons.delete_outline, Colors.red, () {
            _confirmAndRun(
              title: '删除这篇草稿？',
              message: '删除后无法恢复。',
              action: () async {
                final res = await ref
                    .read(apiClientProvider)
                    .delete('/auth/tutorials/${t.id}');
                return res.success;
              },
            );
          }),
        ];
      case _WorkTab.archived:
        return [
          _actionBtn('恢复上架', Icons.visibility_outlined, _primary, () {
            _confirmAndRun(
              title: '恢复上架这篇内容？',
              message: '恢复后读者可以重新看到这篇内容。',
              action: () => _changeStatus(t.id, 'published'),
            );
          }),
          _actionBtn('彻底删除', Icons.delete_forever_outlined, Colors.red, () {
            _confirmAndRun(
              title: '彻底删除这篇内容？',
              message: '删除后连同评论/点赞/收藏一起清除，无法恢复。',
              action: () async {
                final res = await ref
                    .read(apiClientProvider)
                    .delete('/auth/tutorials/${t.id}');
                return res.success;
              },
            );
          }),
        ];
    }
  }

  Color get _actionInk => _isDark ? Colors.white70 : const Color(0xFF555555);

  Widget _actionBtn(
    String label,
    IconData icon,
    Color color,
    VoidCallback onTap,
  ) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 15, color: color),
              const SizedBox(width: 5),
              Text(label, style: TextStyle(fontSize: 12.5, color: color)),
            ],
          ),
        ),
      ),
    );
  }
}
