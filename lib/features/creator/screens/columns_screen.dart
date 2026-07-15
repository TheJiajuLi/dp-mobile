import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_client.dart';
import '../../../core/theme/app_theme.dart';
import '../../column/models/column_model.dart';
import '../../profile/widgets/create_column_sheet.dart';

const _primary = Color(0xFF6366F1);

const _gradients = [
  [Color(0xFF6366F1), Color(0xFF8B5CF6)],
  [Color(0xFFF59E0B), Color(0xFFEA580C)],
  [Color(0xFF059669), Color(0xFF34D399)],
  [Color(0xFFDC2626), Color(0xFFF87171)],
];

enum _ColumnSort { newest, mostSubscribed, mostViewed }

extension on _ColumnSort {
  String get label => switch (this) {
    _ColumnSort.newest => '最新创建',
    _ColumnSort.mostSubscribed => '订阅最多',
    _ColumnSort.mostViewed => '阅读最多',
  };
}

class ColumnsScreen extends ConsumerStatefulWidget {
  const ColumnsScreen({super.key});
  @override
  ConsumerState<ColumnsScreen> createState() => _ColumnsScreenState();
}

class _ColumnsScreenState extends ConsumerState<ColumnsScreen> {
  bool _loading = true;
  List<ColumnModel> _columns = [];
  // 0 = 我的专栏，1 = 收藏的专栏——后端目前只有 POST /columns/:id/subscribe
  // 这个订阅开关接口，没有"我订阅了哪些专栏"的列表接口，收藏的专栏这个
  // tab 先占位展示，不接真数据也不假造一份
  int _tab = 0;
  _ColumnSort _sort = _ColumnSort.newest;
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
    _load();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final res = await ref.read(apiClientProvider).get('/auth/columns/mine');
    if (!mounted) return;
    setState(() {
      _columns = res.success && res.data != null
          ? ((res.data['columns'] as List?) ?? [])
                .map(
                  (j) =>
                      ColumnModel.fromJson(Map<String, dynamic>.from(j as Map)),
                )
                .toList()
          : [];
      _loading = false;
    });
  }

  void _createColumn() {
    // 复用「我的」页那套现代化的新建专栏底部弹层（封面/颜色/领域选择 +
    // 黑色主按钮），跟产品视觉语言统一，不再用系统 AlertDialog。弹层内部
    // 自己 POST /auth/columns 并广播刷新信号，这里创建成功后重拉本页列表
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => CreateColumnSheet(
        profileId: null,
        onCreated: (_) async {
          if (mounted) _load();
        },
      ),
    );
  }

  List<ColumnModel> get _filteredSorted {
    var list = _query.isEmpty
        ? _columns
        : _columns
              .where((c) => c.name.toLowerCase().contains(_query.toLowerCase()))
              .toList();
    list = [...list];
    switch (_sort) {
      case _ColumnSort.newest:
        list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      case _ColumnSort.mostSubscribed:
        list.sort((a, b) => b.subscriberCount.compareTo(a.subscriberCount));
      case _ColumnSort.mostViewed:
        list.sort((a, b) => b.viewCount.compareTo(a.viewCount));
    }
    return list;
  }

  int get _totalViews => _columns.fold(0, (s, c) => s + c.viewCount);

  String _formatCount(int n) {
    if (n >= 10000) return '${(n / 1000).toStringAsFixed(1)}k';
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
            _tabBar(),
            Expanded(
              // 点空白处收起键盘
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => FocusScope.of(context).unfocus(),
                child: _tab == 0 ? _myColumnsBody() : _subscribedPlaceholder(),
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
              '专栏管理',
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
        ],
      ),
    );
  }

  Widget _tabBar() {
    Widget tab(String label, int index) {
      final active = _tab == index;
      return GestureDetector(
        onTap: () => setState(() => _tab = index),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          margin: const EdgeInsets.only(right: 24),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: active ? _primary : Colors.transparent,
                width: 2,
              ),
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 14,
              fontWeight: active ? FontWeight.w700 : FontWeight.w400,
              color: active ? _primary : _muted,
            ),
          ),
        ),
      );
    }

    return Container(
      color: _bg,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(children: [tab('我的专栏', 0), tab('收藏的专栏', 1)]),
    );
  }

  Widget _myColumnsBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    final list = _filteredSorted;
    final hasData = _columns.isNotEmpty;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 40),
      children: [
        if (_searching) ...[
          TextField(
            controller: _searchCtrl,
            autofocus: true,
            onChanged: (v) => setState(() => _query = v),
            decoration: InputDecoration(
              hintText: '搜索专栏名称',
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
          const SizedBox(height: 16),
        ],
        // Hero 标题区——大标题 + 一句概览，把「专栏管理」从后台报表拉回
        // 内容产品的编辑感
        _heroBlock(hasData),
        const SizedBox(height: 18),
        // 主 CTA——紫色轻渐变大按钮（Apple Card 质感），不描边
        _gradientCta(hasData),
        const SizedBox(height: 24),
        if (!hasData)
          // 全 0 的统计卡没有信息量，直接删掉；换成有插图/引导文案的编辑态
          _emptyState()
        else ...[
          _listHeader(),
          const SizedBox(height: 12),
          if (list.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 40),
              child: Center(
                child: Text(
                  '没有匹配的专栏',
                  style: TextStyle(fontSize: 13, color: _muted),
                ),
              ),
            )
          else
            ...list.asMap().entries.map(
              (e) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _columnCard(e.value, e.key),
              ),
            ),
        ],
      ],
    );
  }

  Widget _heroBlock(bool hasData) {
    final sub = hasData
        ? '你拥有 ${_columns.length} 个专栏 · 累计 ${_formatCount(_totalViews)} 阅读'
        : '把文章、教程、研究整理成系列，开始构建属于你的知识世界';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '创建你的知识世界',
          style: TextStyle(
            fontSize: 26,
            fontWeight: FontWeight.w800,
            height: 1.15,
            letterSpacing: -0.5,
            color: _ink,
          ),
        ),
        const SizedBox(height: 8),
        Text(sub, style: TextStyle(fontSize: 13.5, height: 1.4, color: _muted)),
      ],
    );
  }

  Widget _gradientCta(bool hasData) {
    return GestureDetector(
      onTap: _createColumn,
      child: Container(
        height: 72,
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF6D6AFF), Color(0xFF7A6CFF)],
          ),
          borderRadius: BorderRadius.circular(28),
          boxShadow: _isDark
              ? null
              : [
                  BoxShadow(
                    color: const Color(0xFF6D6AFF).withValues(alpha: 0.35),
                    blurRadius: 24,
                    offset: const Offset(0, 10),
                  ),
                ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.add, size: 22, color: Colors.white),
            const SizedBox(width: 8),
            Text(
              hasData ? '新建专栏' : '创建第一个专栏',
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.3,
                color: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _listHeader() {
    return Row(
      children: [
        Text(
          '全部专栏 (${_columns.length})',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: _ink,
          ),
        ),
        const Spacer(),
        GestureDetector(
          onTap: () => setState(() {
            _sort = _ColumnSort
                .values[(_sort.index + 1) % _ColumnSort.values.length];
          }),
          child: Row(
            children: [
              Icon(Icons.swap_vert, size: 15, color: _muted),
              const SizedBox(width: 3),
              Text(_sort.label, style: TextStyle(fontSize: 12, color: _muted)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _emptyState() {
    const examples = ['教程', '数据分析', '动漫系列', '科研笔记', '读书笔记'];
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(24, 30, 24, 30),
      decoration: BoxDecoration(
        color: _isDark ? Colors.white.withValues(alpha: 0.03) : Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: _border, width: 0.5),
      ),
      child: Column(
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  _primary.withValues(alpha: _isDark ? 0.22 : 0.12),
                  const Color(
                    0xFF7A6CFF,
                  ).withValues(alpha: _isDark ? 0.22 : 0.1),
                ],
              ),
              borderRadius: BorderRadius.circular(20),
            ),
            alignment: Alignment.center,
            child: const Text('📚', style: TextStyle(fontSize: 30)),
          ),
          const SizedBox(height: 16),
          Text(
            '开始你的创作旅程',
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w700,
              color: _ink,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '把文章、教程、研究整理成系列，\n让知识在这里持续沉淀。',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, height: 1.5, color: _muted),
          ),
          const SizedBox(height: 20),
          Text(
            '可以整理为',
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              color: _muted,
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.center,
            children: examples.map(_exampleChip).toList(),
          ),
        ],
      ),
    );
  }

  Widget _exampleChip(String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: _primary.withValues(alpha: _isDark ? 0.14 : 0.07),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w500,
          color: _isDark ? const Color(0xFF9B9EF8) : _primary,
        ),
      ),
    );
  }

  Widget _columnCard(ColumnModel c, int index) {
    final gradient = _gradients[index % _gradients.length];
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _border, width: 0.5),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: SizedBox(
              width: 52,
              height: 52,
              child: (c.coverImage ?? '').isNotEmpty
                  ? CachedNetworkImage(
                      imageUrl: c.coverImage!,
                      fit: BoxFit.cover,
                    )
                  : Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: gradient,
                        ),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        c.name.isNotEmpty ? c.name.substring(0, 1) : '专',
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                    ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  c.name,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: _ink,
                  ),
                ),
                if ((c.description ?? '').isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(
                    c.description!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12.5, color: _muted),
                  ),
                ],
                const SizedBox(height: 8),
                Row(
                  children: [
                    Text(
                      '${c.articleCount}篇文章 · ${_formatCount(c.viewCount)}阅读 · ${c.subscriberCount}订阅',
                      style: TextStyle(fontSize: 11.5, color: _muted),
                    ),
                    const Spacer(),
                    GestureDetector(
                      // 进「专栏管理」详情页可能会删除专栏，push 返回后重拉
                      // 本页列表——不然删掉了这里还留着旧卡片，得退出再进才更新
                      onTap: () async {
                        await context.push('/columns/${c.id}');
                        if (mounted) _load();
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: _fill,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          '管理',
                          style: TextStyle(fontSize: 11.5, color: _ink),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _subscribedPlaceholder() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.bookmark_border,
            size: 44,
            color: _isDark ? Colors.white24 : Colors.grey[300],
          ),
          const SizedBox(height: 12),
          Text('收藏的专栏即将上线，敬请期待', style: TextStyle(fontSize: 13, color: _muted)),
        ],
      ),
    );
  }
}
