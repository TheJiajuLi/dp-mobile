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
    // 分段控制器的高亮跟着 TabController 走（点分段/左右滑动都要同步）
    _tabCtrl.addListener(() {
      if (mounted) setState(() {});
    });
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

  int get _totalLikes => _allWorks.fold(0, (s, t) => s + t.likes);

  String _formatCount(int n) {
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}k';
    return '$n';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _header(),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
              child: _statsRow(),
            ),
            _segmented(),
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

  Widget _header() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
      color: _bg,
      child: Row(
        children: [
          GestureDetector(
            onTap: () => context.pop(),
            child: Icon(Icons.arrow_back, size: 20, color: _ink),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              '作品管理',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: _ink,
              ),
            ),
          ),
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
              color: _isDark ? Colors.white70 : const Color(0xFF555555),
            ),
          ),
          const SizedBox(width: 14),
          GestureDetector(
            onTap: () => ScaffoldMessenger.of(
              context,
            ).showSnackBar(const SnackBar(content: Text('批量操作即将上线，敬请期待'))),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: _fill,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text('批量', style: TextStyle(fontSize: 12, color: _ink)),
            ),
          ),
        ],
      ),
    );
  }

  // 顶部三格总览——左对齐大数值 + 灰色小标签，克制不抢戏。收藏数列表
  // 批量接口不返回（只有单篇详情接口带），先占位显示 0，等后端在
  // listTutorials 里补上 save_count 直接生效
  Widget _statsRow() {
    Widget statCard(String value, String label) {
      return Expanded(
        child: Container(
          margin: const EdgeInsets.all(4),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: _card,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: _border, width: 0.5),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                value,
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w500,
                  color: _ink,
                ),
              ),
              const SizedBox(height: 2),
              Text(label, style: TextStyle(fontSize: 11, color: _muted)),
            ],
          ),
        ),
      );
    }

    return Row(
      children: [
        statCard('${_allWorks.length}', '篇文章'),
        statCard(_formatCount(_totalLikes), '总获赞'),
        statCard('0', '总收藏'),
      ],
    );
  }

  // 全部/已发布/草稿/下架——iOS 风格分段控制器，选中项浮出白色胶囊，
  // 替代原来的下划线 TabBar，视觉更一线。驱动同一个 _tabCtrl（点/滑同步）
  Widget _segmented() {
    return Container(
      margin: const EdgeInsets.fromLTRB(14, 2, 14, 10),
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: _isDark ? AppColors.darkCard : const Color(0xFFF0F0F0),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: _WorkTab.values.map((t) {
          final selected = _tabCtrl.index == t.index;
          return Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => _tabCtrl.animateTo(t.index),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                padding: const EdgeInsets.symmetric(vertical: 7),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: selected
                      ? (_isDark ? AppColors.darkSurface : Colors.white)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                  boxShadow: selected && !_isDark
                      ? [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.05),
                            blurRadius: 4,
                            offset: const Offset(0, 1),
                          ),
                        ]
                      : null,
                ),
                child: Text(
                  t.label,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                    color: selected
                        ? (_isDark ? Colors.white : const Color(0xFF1A1A1A))
                        : _muted,
                  ),
                ),
              ),
            ),
          );
        }).toList(),
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
      return Center(
        child: Text(
          _query.isNotEmpty
              ? '没有匹配的作品'
              : switch (tab) {
                  _WorkTab.all => '还没有任何作品',
                  _WorkTab.published => '还没有发布的作品',
                  _WorkTab.draft => '草稿箱是空的',
                  _WorkTab.archived => '没有已下架的内容',
                },
          style: TextStyle(fontSize: 13, color: _muted),
        ),
      );
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
                            _timeAgo(t.createdAt),
                            style: TextStyle(
                              fontSize: 11.5,
                              color: _isDark
                                  ? AppColors.darkTextMuted
                                  : const Color(0xFFC7C7CC),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          _miniStat(Icons.thumb_up_outlined, '${t.likes}'),
                          const SizedBox(width: 12),
                          _miniStat(Icons.bookmark_outline, '0'),
                          const SizedBox(width: 12),
                          _miniStat(
                            Icons.visibility_outlined,
                            _formatCount(t.views),
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
            child: IntrinsicHeight(
              child: Row(children: _withDividers(_actionsFor(tab, t))),
            ),
          ),
        ],
      ),
    );
  }

  Widget _miniStat(IconData icon, String value) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: _muted),
        const SizedBox(width: 3),
        Text(value, style: TextStyle(fontSize: 12, color: _muted)),
      ],
    );
  }

  // 操作按钮之间插竖分割线——靠外层 IntrinsicHeight 给 VerticalDivider
  // 一个有界高度
  List<Widget> _withDividers(List<Widget> btns) {
    final out = <Widget>[];
    for (var i = 0; i < btns.length; i++) {
      if (i > 0) {
        out.add(VerticalDivider(width: 0.5, thickness: 0.5, color: _border));
      }
      out.add(btns[i]);
    }
    return out;
  }

  String _timeAgo(int ms) {
    final d = DateTime.now().difference(
      DateTime.fromMillisecondsSinceEpoch(ms),
    );
    if (d.inDays >= 365) return '${(d.inDays / 365).floor()}年前';
    if (d.inDays >= 30) return '${(d.inDays / 30).floor()}个月前';
    if (d.inDays >= 1) return '${d.inDays}天前';
    if (d.inHours >= 1) return '${d.inHours}小时前';
    if (d.inMinutes >= 1) return '${d.inMinutes}分钟前';
    return '刚刚';
  }

  Widget _statusChip(_WorkTab tab) {
    // 已发布用绿色，其余（草稿/下架）用中性灰——胶囊 badge，浅底深字
    final (label, color) = switch (tab) {
      _WorkTab.published => ('已发布', const Color(0xFF16A34A)),
      _WorkTab.draft => ('草稿', const Color(0xFF888888)),
      _WorkTab.archived => ('已下架', const Color(0xFF999999)),
      _WorkTab.all => ('', const Color(0xFF999999)),
    };
    if (label.isEmpty) return const SizedBox.shrink();
    final published = tab == _WorkTab.published;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: _isDark
            ? color.withValues(alpha: 0.12)
            : (published ? const Color(0xFFF0FFF5) : const Color(0xFFF5F5F5)),
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
