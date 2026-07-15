import 'dart:io';
import 'dart:typed_data';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/network/api_client.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/models/tutorial_model.dart';
import '../../../shared/utils/pro_access.dart';
import '../../../shared/utils/topic_badge.dart';
import '../../auth/auth_service.dart';
import '../../column/models/column_model.dart';
import '../../community/services/tutorial_export_service.dart';
import '../widgets/creator_sheets.dart';

const _primary = Color(0xFF6366F1);
const _danger = Color(0xFFEF4444);

// 作品分区：全部 / 已发布 / 草稿 / 私密。私密 = status='private'（后端
// 已支持，独立状态、仅作者可见、可随时改回公开），不再用会被存储页懒清理
// 硬删的 deleted。删除文章走真正的 DELETE（永久，点赞/收藏/评论一并清除）
enum _WorkTab { all, published, draft, private }

extension on _WorkTab {
  String get label => switch (this) {
    _WorkTab.all => '全部',
    _WorkTab.published => '已发布',
    _WorkTab.draft => '草稿',
    _WorkTab.private => '私密',
  };

  String get status => switch (this) {
    _WorkTab.all => '',
    _WorkTab.published => 'published',
    _WorkTab.draft => 'draft',
    _WorkTab.private => 'private',
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
    _WorkTab.private: [],
  };
  final Map<_WorkTab, bool> _loading = {
    _WorkTab.published: true,
    _WorkTab.draft: true,
    _WorkTab.private: true,
  };
  // 分段控制器只显示 全部/已发布/草稿 三段（跟设计稿一致）。私密文章仍会
  // 加载，混在「全部」里用私密胶囊标出，不单独占一个 tab
  static const _segments = [_WorkTab.all, _WorkTab.published, _WorkTab.draft];
  bool _searching = false;
  final _searchCtrl = TextEditingController();
  String _query = '';
  String _sortBy = 'time'; // time | hot

  bool get _isDark => Theme.of(context).brightness == Brightness.dark;
  Color get _bg => _isDark ? AppColors.darkBg : const Color(0xFFFAFAF8);
  Color get _card => _isDark ? AppColors.darkCard : Colors.white;
  Color get _ink =>
      _isDark ? AppColors.darkTextPrimary : const Color(0xFF1A1A1A);
  Color get _muted =>
      _isDark ? AppColors.darkTextSecondary : const Color(0xFF888888);
  Color get _border => _isDark ? AppColors.darkBorder : const Color(0xFFEBEBEB);
  Color get _fill =>
      _isDark ? Colors.white.withValues(alpha: 0.06) : const Color(0xFFF5F5F7);

  @override
  void initState() {
    super.initState();
    // 创作者中心「草稿箱」卡片带 initialTab 过来定位到草稿；all=0，
    // 其余 +1（published=1/draft=2）。私密不作为外部入口，clamp 兜底
    final rawInitial = widget.initialTab.clamp(0, 2);
    final initialIndex = rawInitial == 0 ? 0 : rawInitial + 1;
    _tabCtrl = TabController(
      length: _segments.length,
      vsync: this,
      initialIndex: initialIndex.clamp(0, _segments.length - 1),
    );
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

  Future<void> _loadAll() async {
    await Future.wait(
      [_WorkTab.published, _WorkTab.draft, _WorkTab.private].map(_load),
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
            'status': tab.status,
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

  // 设为私密/公开/发布都是"整份覆盖"式 PUT——先把完整教程（含 blocks）
  // 拉回来只改 status，其余原样传回，不然 updateTutorial 会把 blocks/tags
  // 清空成默认值
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

  Future<void> _runStatus(String id, String status, String okMsg) async {
    final ok = await _changeStatus(id, status);
    if (!mounted) return;
    if (ok) {
      await _loadAll();
      _toast(okMsg, ok: true);
    } else {
      _toast('操作失败，请重试');
    }
  }

  void _toast(String msg, {bool ok = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: ok ? const Color(0xFF16A34A) : null,
      ),
    );
  }

  List<TutorialModel> get _allWorks => [
    ..._lists[_WorkTab.published] ?? [],
    ..._lists[_WorkTab.draft] ?? [],
    ..._lists[_WorkTab.private] ?? [],
  ];

  int get _totalLikes => _allWorks.fold(0, (s, t) => s + t.likes);
  int get _totalSaves => _allWorks.fold(0, (s, t) => s + t.saveCount);

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
            _segmented(),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
              child: _statsRow(),
            ),
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => FocusScope.of(context).unfocus(),
                child: TabBarView(
                  controller: _tabCtrl,
                  children: _segments.map(_buildTab).toList(),
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
      padding: const EdgeInsets.fromLTRB(16, 10, 12, 12),
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
          const SizedBox(width: 6),
          IconButton(
            icon: Icon(
              Icons.more_horiz,
              size: 22,
              color: _isDark ? Colors.white70 : const Color(0xFF555555),
            ),
            onPressed: _showMoreSheet,
          ),
        ],
      ),
    );
  }

  // 顶部三格总览——篇文章 / 总获赞 / 总收藏，全部真实数据（收藏来自
  // listTutorials 已补上的 save_count）
  Widget _statsRow() {
    Widget statCard(String value, String label) {
      return Expanded(
        child: Container(
          margin: const EdgeInsets.all(4),
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            color: _card,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: _border, width: 0.5),
          ),
          child: Column(
            children: [
              Text(
                value,
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: _ink,
                ),
              ),
              const SizedBox(height: 3),
              Text(label, style: TextStyle(fontSize: 11.5, color: _muted)),
            ],
          ),
        ),
      );
    }

    return Row(
      children: [
        statCard('${_allWorks.length}', '篇文章'),
        statCard(_formatCount(_totalLikes), '总获赞'),
        statCard(_formatCount(_totalSaves), '总收藏'),
      ],
    );
  }

  Widget _segmented() {
    return Container(
      margin: const EdgeInsets.fromLTRB(14, 8, 14, 12),
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: _isDark ? AppColors.darkCard : const Color(0xFFF0F0F0),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: _segments.map((t) {
          final idx = _segments.indexOf(t);
          final selected = _tabCtrl.index == idx;
          return Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => _tabCtrl.animateTo(idx),
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
    // 排序：时间（最新在前）/ 热度（获赞最多在前）
    list = [...list];
    if (_sortBy == 'hot') {
      list.sort((a, b) => b.likes.compareTo(a.likes));
    } else {
      list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
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
                  _WorkTab.private => '没有私密文章',
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
            child: _workCard(t),
          ),
        ),
      ],
    );
  }

  Widget _workCard(TutorialModel t) {
    return Container(
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(12),
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
                _buildCover(t),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        t.title.isEmpty ? '无标题' : t.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w600,
                          color: _ink,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Row(
                        children: [
                          _statusChip(t.status),
                          const SizedBox(width: 6),
                          Text(
                            _timeAgo(t.createdAt),
                            style: TextStyle(fontSize: 11, color: _muted),
                          ),
                        ],
                      ),
                      const SizedBox(height: 7),
                      Row(
                        children: [
                          _miniStat(Icons.thumb_up_outlined, '${t.likes}'),
                          const SizedBox(width: 10),
                          _miniStat(Icons.bookmark_outline, '${t.saveCount}'),
                          const SizedBox(width: 10),
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
              child: Row(children: _withDividers(_actionsFor(t))),
            ),
          ),
        ],
      ),
    );
  }

  // 有真实封面图就用封面，没有就按话题色给个图标兜底——跟专栏管理的
  // 无封面兜底同一套 matchedTopicRuleFor，不是编一个不存在的 domain 字段
  Widget _buildCover(TutorialModel t) {
    if ((t.coverImage ?? '').isNotEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: CachedNetworkImage(
          imageUrl: t.coverImage!,
          width: 52,
          height: 52,
          fit: BoxFit.cover,
          errorWidget: (context, url, error) => _coverIcon(t),
        ),
      );
    }
    return _coverIcon(t);
  }

  Widget _coverIcon(TutorialModel t) {
    final rule = matchedTopicRuleFor(t.tags);
    final bg = rule?.bg ?? const Color(0xFFF5F5F5);
    final fg = rule?.fg ?? const Color(0xFF999999);
    return Container(
      width: 52,
      height: 52,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Icon(Icons.description_outlined, color: fg, size: 22),
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

  Widget _statusChip(String status) {
    final (label, color) = switch (status) {
      'published' => ('已发布', const Color(0xFF16A34A)),
      'draft' => ('草稿', const Color(0xFF888888)),
      'private' => ('私密', const Color(0xFFD97706)),
      _ => ('', const Color(0xFF999999)),
    };
    if (label.isEmpty) return const SizedBox.shrink();
    final green = status == 'published';
    final amber = status == 'private';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: _isDark
            ? color.withValues(alpha: 0.14)
            : (green
                  ? const Color(0xFFF0FFF5)
                  : amber
                  ? const Color(0xFFFEF3C7)
                  : const Color(0xFFF5F5F5)),
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

  List<Widget> _actionsFor(TutorialModel t) {
    if (t.status == 'draft') {
      return [
        _actionBtn(
          '继续编辑',
          Icons.edit_outlined,
          _actionInk,
          () => context.push('/publish/${t.id}'),
        ),
        _actionBtn(
          '发布',
          Icons.send_outlined,
          _primary,
          () => _confirmPublish(t),
        ),
        _actionBtn(
          '删除',
          Icons.delete_outline,
          _danger,
          () => _confirmDelete(t),
        ),
      ];
    }
    // published / private
    return [
      _actionBtn(
        '编辑',
        Icons.edit_outlined,
        _actionInk,
        () => _showEditSheet(t),
      ),
      _actionBtn(
        '数据',
        Icons.bar_chart_outlined,
        _actionInk,
        () => _showStatsSheet(t),
      ),
      _actionBtn('删除', Icons.delete_outline, _danger, () => _confirmDelete(t)),
    ];
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

  // ============ 编辑文章 Sheet ============
  void _showEditSheet(TutorialModel t) {
    final isPrivate = t.status == 'private';
    showCreatorActionSheet(
      context,
      title: '编辑文章',
      children: [
        CreatorSheetItem(
          icon: Icons.edit_outlined,
          accent: _primary,
          label: '继续编辑',
          sub: '打开编辑器',
          onTap: () {
            Navigator.pop(context);
            context.push('/publish/${t.id}');
          },
        ),
        CreatorSheetItem(
          icon: Icons.library_books_outlined,
          accent: _primary,
          label: '移至专栏',
          sub: '添加到现有专栏',
          onTap: () {
            Navigator.pop(context);
            _moveToColumn(t);
          },
        ),
        CreatorSheetItem(
          icon: isPrivate ? Icons.public : Icons.visibility_off_outlined,
          accent: const Color(0xFFD97706),
          label: isPrivate ? '设为公开' : '设为私密',
          sub: isPrivate ? '所有人可见' : '仅自己可见',
          onTap: () {
            Navigator.pop(context);
            _runStatus(
              t.id,
              isPrivate ? 'published' : 'private',
              isPrivate ? '已公开' : '已设为私密',
            );
          },
        ),
        creatorSheetDivider(context),
        CreatorSheetItem(
          icon: Icons.delete_outline,
          accent: _danger,
          label: '删除文章',
          isRed: true,
          onTap: () {
            Navigator.pop(context);
            _confirmDelete(t);
          },
        ),
      ],
    );
  }

  // ============ 文章数据 Sheet ============
  void _showStatsSheet(TutorialModel t) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        Widget row(String label, String value, {bool accent = false}) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
            child: Row(
              children: [
                Text(label, style: TextStyle(fontSize: 14, color: _muted)),
                const Spacer(),
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                    color: accent ? _primary : _ink,
                  ),
                ),
              ],
            ),
          );
        }

        final divider = Divider(height: 0.5, thickness: 0.5, color: _border);
        return Container(
          decoration: BoxDecoration(
            color: _card,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
          ),
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 24),
          child: SafeArea(
            top: false,
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
                      color: Colors.grey.withValues(alpha: 0.4),
                      borderRadius: BorderRadius.circular(99),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 0, 4, 12),
                  child: Text(
                    '文章数据',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: _ink,
                    ),
                  ),
                ),
                Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: _border, width: 0.5),
                  ),
                  child: Column(
                    children: [
                      row('浏览量', '${t.views}'),
                      divider,
                      row('点赞', '${t.likes}'),
                      divider,
                      row('收藏', '${t.saveCount}'),
                      divider,
                      row('评论', '${t.commentCount}'),
                      divider,
                      row('分享', '${t.shares}', accent: true),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    style: TextButton.styleFrom(
                      backgroundColor: _fill,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: Text(
                      '关闭',
                      style: TextStyle(fontSize: 15, color: _ink),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // ============ 移至专栏 ============
  Future<void> _moveToColumn(TutorialModel t) async {
    final api = ref.read(apiClientProvider);
    final res = await api.get('/auth/columns/mine');
    if (!mounted) return;
    final cols = (res.success && res.data != null)
        ? ((res.data['columns'] as List?) ?? [])
              .map(
                (j) =>
                    ColumnModel.fromJson(Map<String, dynamic>.from(j as Map)),
              )
              .toList()
        : <ColumnModel>[];
    if (cols.isEmpty) {
      _toast('还没有专栏，先去专栏管理创建一个');
      return;
    }
    if (!mounted) return;
    showCreatorActionSheet(
      context,
      title: '移至专栏',
      children: cols.map((c) {
        return CreatorSheetItem(
          icon: Icons.library_books_outlined,
          accent: _primary,
          label: c.name,
          sub: '${c.articleCount}篇文章',
          onTap: () async {
            Navigator.pop(context);
            final r = await api.post(
              '/auth/columns/${c.id}/articles',
              data: {'tutorialId': t.id},
            );
            if (!mounted) return;
            _toast(
              r.success ? '已添加到「${c.name}」' : (r.message ?? '添加失败'),
              ok: r.success,
            );
          },
        );
      }).toList(),
    );
  }

  // ============ 删除 / 发布 确认 ============
  Future<void> _confirmDelete(TutorialModel t) async {
    final ok = await showCreatorConfirmSheet(
      context,
      title: '删除文章',
      message: '删除后无法恢复，文章的全部数据（点赞、收藏、评论）将永久清除。',
      confirmLabel: '确认删除',
      isDanger: true,
    );
    if (!ok || !mounted) return;
    final res = await ref
        .read(apiClientProvider)
        .delete('/auth/tutorials/${t.id}');
    if (!mounted) return;
    if (res.success) {
      await _loadAll();
      _toast('文章已删除', ok: true);
    } else {
      _toast(res.message ?? '删除失败');
    }
  }

  Future<void> _confirmPublish(TutorialModel t) async {
    final ok = await showCreatorConfirmSheet(
      context,
      title: '发布文章',
      message: '发布后所有人可见，你可以随时回来编辑或设为私密。',
      confirmLabel: '立即发布',
    );
    if (!ok || !mounted) return;
    await _runStatus(t.id, 'published', '文章已发布');
  }

  // ============ 更多操作（排序 / 导出全部）============
  void _showMoreSheet() {
    showCreatorActionSheet(
      context,
      title: '更多操作',
      children: [
        CreatorSheetItem(
          icon: Icons.schedule,
          accent: _primary,
          label: '按时间排序',
          sub: '最新发布在前',
          onTap: () {
            Navigator.pop(context);
            setState(() => _sortBy = 'time');
          },
        ),
        CreatorSheetItem(
          icon: Icons.trending_up,
          accent: _primary,
          label: '按热度排序',
          sub: '获赞最多在前',
          onTap: () {
            Navigator.pop(context);
            setState(() => _sortBy = 'hot');
          },
        ),
        creatorSheetDivider(context),
        CreatorSheetItem(
          icon: Icons.download_outlined,
          accent: const Color(0xFF16A34A),
          label: '导出全部文章',
          sub: 'PDF 格式',
          onTap: () {
            Navigator.pop(context);
            _exportAllPdf();
          },
        ),
      ],
    );
  }

  // 逐篇生成 PDF 再一次性分享——没有多篇合并能力，公式走纯文本兜底
  // （批量导出不做离屏公式渲染，太重）。Pro 功能
  Future<void> _exportAllPdf() async {
    if (!requirePro(context, ref, feature: '导出全部 PDF')) return;
    final published = _lists[_WorkTab.published] ?? [];
    if (published.isEmpty) {
      _toast('没有已发布的文章');
      return;
    }
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
          decoration: BoxDecoration(
            color: _card,
            borderRadius: BorderRadius.circular(16),
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              SizedBox(width: 14),
              Text('正在生成 PDF...'),
            ],
          ),
        ),
      ),
    );
    try {
      final api = ref.read(apiClientProvider);
      final dir = await getTemporaryDirectory();
      final files = <XFile>[];
      for (final t in published) {
        final full = await api.get('/auth/tutorials/${t.id}');
        if (!full.success || full.data == null) continue;
        final data = Map<String, dynamic>.from(full.data as Map);
        final blocks = (data['blocks'] as List?) ?? [];
        final Uint8List bytes = await buildTutorialPdfBytes(
          tutorial: data,
          blocks: blocks,
          style: 'clean',
        );
        final safe = (t.title.isEmpty ? '未命名' : t.title).replaceAll(
          RegExp(r'[^\w一-龥]+'),
          '_',
        );
        final path = '${dir.path}/$safe.pdf';
        await File(path).writeAsBytes(bytes);
        files.add(XFile(path));
      }
      if (!mounted) return;
      Navigator.pop(context); // 关掉进度弹窗
      if (files.isEmpty) {
        _toast('导出失败，请重试');
        return;
      }
      await Share.shareXFiles(files, subject: '我的极梦文章合集');
    } catch (e) {
      if (!mounted) return;
      Navigator.pop(context);
      _toast('导出失败：$e');
    }
  }
}
