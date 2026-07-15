import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_client.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/models/tutorial_model.dart';
import '../../auth/auth_service.dart';
import '../../column/models/column_model.dart';
import '../../profile/widgets/create_column_sheet.dart';
import '../widgets/creator_sheets.dart';

const _primary = Color(0xFF6366F1);

// 专栏封面条轮换调色板——ColumnModel 目前没有 domain 字段，就按专栏
// 顺序轮换上色（浅底色 + 同色系实心图标底），每个专栏一个稳定的颜色。
// 记录: (浅色封面条底色, 图标/强调色, 图标)
const _covers = <(Color, Color, IconData)>[
  (Color(0xFFEEF0FF), Color(0xFF6366F1), Icons.functions),
  (Color(0xFFEAF7EF), Color(0xFF16A34A), Icons.code),
  (Color(0xFFFEF3C7), Color(0xFFD97706), Icons.insights),
  (Color(0xFFF3E8FF), Color(0xFF8B5CF6), Icons.auto_stories),
  (Color(0xFFFFE9EC), Color(0xFFDC2626), Icons.science_outlined),
  (Color(0xFFE0F2FE), Color(0xFF2563EB), Icons.public),
];

class ColumnsScreen extends ConsumerStatefulWidget {
  const ColumnsScreen({super.key});
  @override
  ConsumerState<ColumnsScreen> createState() => _ColumnsScreenState();
}

class _ColumnsScreenState extends ConsumerState<ColumnsScreen> {
  bool _loading = true;
  List<ColumnModel> _columns = [];

  bool get _isDark => Theme.of(context).brightness == Brightness.dark;
  Color get _bg => _isDark ? AppColors.darkBg : const Color(0xFFFAFAF8);
  Color get _card => _isDark ? AppColors.darkCard : Colors.white;
  Color get _ink =>
      _isDark ? AppColors.darkTextPrimary : const Color(0xFF1A1A1A);
  Color get _muted =>
      _isDark ? AppColors.darkTextSecondary : const Color(0xFF888888);
  Color get _border => _isDark ? AppColors.darkBorder : const Color(0xFFEBEBEB);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final res = await ref.read(apiClientProvider).get('/auth/columns/mine');
    if (!mounted) return;
    setState(() {
      final list = res.success && res.data != null
          ? ((res.data['columns'] as List?) ?? [])
                .map(
                  (j) =>
                      ColumnModel.fromJson(Map<String, dynamic>.from(j as Map)),
                )
                .toList()
          : <ColumnModel>[];
      // 最新创建在前
      list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      _columns = list;
      _loading = false;
    });
  }

  void _createColumn() {
    // 复用「我的」页那套现代化的新建专栏底部弹层（封面/颜色/领域选择 +
    // 黑色主按钮）。弹层内部自己 POST /auth/columns 并广播刷新信号，
    // 这里创建成功后重拉本页列表
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

  int get _totalArticles => _columns.fold(0, (s, c) => s + c.articleCount);
  int get _totalSubscribers =>
      _columns.fold(0, (s, c) => s + c.subscriberCount);

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
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : ListView(
                      padding: const EdgeInsets.fromLTRB(10, 0, 10, 32),
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(4, 0, 4, 6),
                          child: _statsRow(),
                        ),
                        if (_columns.isEmpty)
                          _emptyState()
                        else ...[
                          Padding(
                            padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
                            child: Text(
                              '我的专栏',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: _muted,
                              ),
                            ),
                          ),
                          ..._columns.asMap().entries.map(
                            (e) => Padding(
                              padding: const EdgeInsets.fromLTRB(4, 0, 4, 10),
                              child: _columnCard(e.value, e.key),
                            ),
                          ),
                        ],
                      ],
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
              '专栏管理',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: _ink,
              ),
            ),
          ),
          // 右上角新建专栏
          GestureDetector(
            onTap: _createColumn,
            child: Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: _primary,
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.add, size: 20, color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  // 顶部三格总览——个专栏 / 篇文章 / 订阅者，左对齐大数值 + 灰色小标签
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
        statCard('${_columns.length}', '个专栏'),
        statCard('$_totalArticles', '篇文章'),
        statCard(_formatCount(_totalSubscribers), '订阅者'),
      ],
    );
  }

  Widget _columnCard(ColumnModel c, int index) {
    final (lightStrip, accent, icon) = _covers[index % _covers.length];
    // 深色模式下浅色封面条会太亮，改用强调色的低透明度当底
    final stripBg = _isDark ? accent.withValues(alpha: 0.16) : lightStrip;
    final stripText = _isDark ? Colors.white : const Color(0xFF1A1A1A);

    return Container(
      clipBehavior: Clip.hardEdge,
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _border, width: 0.5),
      ),
      child: Column(
        children: [
          // 彩色封面条：图标 + 名称 + 文章/订阅者数
          Container(
            height: 72,
            color: stripBg,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: accent,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, color: Colors.white, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        c.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: stripText,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${c.articleCount}篇文章 · ${c.subscriberCount} 订阅者',
                        style: TextStyle(
                          fontSize: 11,
                          color: stripText.withValues(alpha: 0.7),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          // 简介 + 操作
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if ((c.description ?? '').trim().isNotEmpty) ...[
                  Text(
                    c.description!.trim(),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, height: 1.6, color: _muted),
                  ),
                  const SizedBox(height: 10),
                ],
                Row(
                  children: [
                    Expanded(
                      child: _cardBtn(
                        '管理文章',
                        () => _showManageArticlesSheet(c),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(child: _cardBtn('编辑专栏', () => _editColumn(c))),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _cardBtn(String label, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: _border, width: 0.8),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: _ink,
          ),
        ),
      ),
    );
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

  // 编辑专栏名称/简介 + 删除专栏入口——PUT /auth/columns/:id 只发
  // name/description；删除走 DELETE /auth/columns/:id（文章不删，只解除归属）
  void _editColumn(ColumnModel c) {
    final nameCtrl = TextEditingController(text: c.name);
    final descCtrl = TextEditingController(text: c.description ?? '');
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: Container(
          decoration: BoxDecoration(
            color: _card,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
          ),
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _grabber(),
                Text(
                  '编辑专栏',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: _ink,
                  ),
                ),
                const SizedBox(height: 16),
                _sheetField(nameCtrl, '专栏名称'),
                const SizedBox(height: 12),
                _sheetField(descCtrl, '专栏简介（选填）', maxLines: 2),
                const SizedBox(height: 6),
                creatorSheetDivider(ctx),
                CreatorSheetItem(
                  icon: Icons.delete_outline,
                  accent: const Color(0xFFEF4444),
                  label: '删除专栏',
                  sub: '文章不会被删除',
                  isRed: true,
                  onTap: () {
                    Navigator.pop(ctx);
                    _confirmDeleteColumn(c);
                  },
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: TextButton(
                    onPressed: () async {
                      if (nameCtrl.text.trim().isEmpty) return;
                      final res = await ref
                          .read(apiClientProvider)
                          .put(
                            '/auth/columns/${c.id}',
                            data: {
                              'name': nameCtrl.text.trim(),
                              'description': descCtrl.text.trim(),
                            },
                          );
                      if (!ctx.mounted) return;
                      Navigator.pop(ctx);
                      if (res.success) {
                        if (mounted) _load();
                        _toast('专栏已更新', ok: true);
                      } else {
                        _toast(res.message ?? '保存失败，请稍后重试');
                      }
                    },
                    style: TextButton.styleFrom(
                      backgroundColor: const Color(0xFF1A1A1A),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text(
                      '保存更改',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    style: TextButton.styleFrom(
                      backgroundColor: _isDark
                          ? Colors.white.withValues(alpha: 0.06)
                          : const Color(0xFFF5F5F5),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: Text(
                      '取消',
                      style: TextStyle(fontSize: 15, color: _muted),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _grabber() => Center(
    child: Container(
      width: 36,
      height: 4,
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.grey.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(99),
      ),
    ),
  );

  Future<void> _confirmDeleteColumn(ColumnModel c) async {
    final ok = await showCreatorConfirmSheet(
      context,
      title: '删除专栏',
      message: '删除后专栏内的文章不会被删除，只会从专栏中移出。此操作无法撤销。',
      confirmLabel: '确认删除',
      isDanger: true,
    );
    if (!ok || !mounted) return;
    final res = await ref
        .read(apiClientProvider)
        .delete('/auth/columns/${c.id}');
    if (!mounted) return;
    if (res.success) {
      await _load();
      _toast('专栏已删除', ok: true);
    } else {
      _toast(res.message ?? '删除失败，请稍后重试');
    }
  }

  // ============ 管理文章 ============
  void _showManageArticlesSheet(ColumnModel c) {
    showCreatorActionSheet(
      context,
      title: '管理文章',
      children: [
        CreatorSheetItem(
          icon: Icons.add_circle_outline,
          accent: _primary,
          label: '添加文章到专栏',
          sub: '从已发布的文章中选择',
          onTap: () {
            Navigator.pop(context);
            _addArticleToColumn(c);
          },
        ),
        CreatorSheetItem(
          icon: Icons.format_list_numbered,
          accent: _primary,
          label: '调整文章顺序',
          sub: '拖拽排序专栏内文章',
          onTap: () {
            Navigator.pop(context);
            _reorderColumnArticles(c);
          },
        ),
        CreatorSheetItem(
          icon: Icons.remove_circle_outline,
          accent: const Color(0xFFD97706),
          label: '从专栏移除文章',
          sub: '文章不会被删除',
          onTap: () {
            Navigator.pop(context);
            _removeArticleFromColumn(c);
          },
        ),
      ],
    );
  }

  // 专栏当前文章（按 column_order 已排好序），返回 [{id,title}]
  Future<List<Map<String, dynamic>>> _fetchColumnArticles(String id) async {
    final res = await ref.read(apiClientProvider).get('/auth/columns/$id');
    if (!res.success || res.data == null) return [];
    final arts = ((res.data as Map)['articles'] as List?) ?? [];
    return arts.map((a) => Map<String, dynamic>.from(a as Map)).toList();
  }

  Future<void> _addArticleToColumn(ColumnModel c) async {
    final user = ref.read(currentUserProvider);
    if (user == null) return;
    final api = ref.read(apiClientProvider);
    // 我的已发布文章
    final res = await api.get(
      '/auth/tutorials',
      queryParameters: {
        'author': user.username,
        'status': 'published',
        'limit': 100,
      },
    );
    if (!mounted) return;
    final published = (res.success && res.data != null)
        ? ((res.data['tutorials'] as List?) ?? [])
              .map((j) => TutorialModel.fromJson(j as Map<String, dynamic>))
              .where((t) => t.userId == user.id)
              .toList()
        : <TutorialModel>[];
    // 排除已在该专栏里的
    final existing = (await _fetchColumnArticles(
      c.id,
    )).map((a) => a['id'].toString()).toSet();
    if (!mounted) return;
    final candidates = published
        .where((t) => !existing.contains(t.id))
        .toList();
    if (candidates.isEmpty) {
      _toast('没有可添加的已发布文章');
      return;
    }
    showCreatorActionSheet(
      context,
      title: '添加文章到专栏',
      children: candidates.map((t) {
        return CreatorSheetItem(
          icon: Icons.article_outlined,
          accent: _primary,
          label: t.title.isEmpty ? '无标题' : t.title,
          sub: '${t.likes} 赞 · ${_formatCount(t.views)} 浏览',
          onTap: () async {
            Navigator.pop(context);
            final r = await api.post(
              '/auth/columns/${c.id}/articles',
              data: {'tutorialId': t.id},
            );
            if (!mounted) return;
            if (r.success) {
              await _load();
              _toast('已添加到「${c.name}」', ok: true);
            } else {
              _toast(r.message ?? '添加失败');
            }
          },
        );
      }).toList(),
    );
  }

  Future<void> _removeArticleFromColumn(ColumnModel c) async {
    final arts = await _fetchColumnArticles(c.id);
    if (!mounted) return;
    if (arts.isEmpty) {
      _toast('这个专栏还没有文章');
      return;
    }
    showCreatorActionSheet(
      context,
      title: '从专栏移除文章',
      children: arts.map((a) {
        final id = a['id'].toString();
        final title = (a['title'] as String?) ?? '无标题';
        return CreatorSheetItem(
          icon: Icons.remove_circle_outline,
          accent: const Color(0xFFD97706),
          label: title.isEmpty ? '无标题' : title,
          sub: '从专栏移出，文章不会被删除',
          onTap: () async {
            Navigator.pop(context);
            final r = await ref
                .read(apiClientProvider)
                .delete('/auth/columns/${c.id}/articles/$id');
            if (!mounted) return;
            if (r.success) {
              await _load();
              _toast('已从「${c.name}」移出', ok: true);
            } else {
              _toast(r.message ?? '移除失败');
            }
          },
        );
      }).toList(),
    );
  }

  Future<void> _reorderColumnArticles(ColumnModel c) async {
    final arts = await _fetchColumnArticles(c.id);
    if (!mounted) return;
    if (arts.length < 2) {
      _toast(arts.isEmpty ? '这个专栏还没有文章' : '至少两篇文章才能排序');
      return;
    }
    final order = await showModalBottomSheet<List<String>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _ReorderArticlesSheet(articles: arts, isDark: _isDark),
    );
    if (order == null || !mounted) return;
    final r = await ref
        .read(apiClientProvider)
        .put('/auth/columns/${c.id}/articles/order', data: {'order': order});
    if (!mounted) return;
    if (r.success) {
      await _load();
      _toast('顺序已保存', ok: true);
    } else {
      _toast(r.message ?? '保存失败');
    }
  }

  Widget _sheetField(
    TextEditingController ctrl,
    String label, {
    int maxLines = 1,
  }) {
    return TextField(
      controller: ctrl,
      maxLines: maxLines,
      style: TextStyle(color: _ink),
      decoration: InputDecoration(
        labelText: label,
        filled: true,
        fillColor: _isDark
            ? Colors.white.withValues(alpha: 0.06)
            : const Color(0xFFF5F5F7),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: _primary),
        ),
      ),
    );
  }

  Widget _emptyState() {
    const examples = ['教程', '数据分析', '动漫系列', '科研笔记', '读书笔记'];
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(4, 12, 4, 0),
      padding: const EdgeInsets.fromLTRB(24, 30, 24, 30),
      decoration: BoxDecoration(
        color: _isDark ? Colors.white.withValues(alpha: 0.03) : Colors.white,
        borderRadius: BorderRadius.circular(20),
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
          const SizedBox(height: 18),
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
            children: examples.map((e) {
              return Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: _primary.withValues(alpha: _isDark ? 0.14 : 0.07),
                  borderRadius: BorderRadius.circular(99),
                ),
                child: Text(
                  e,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: _isDark ? const Color(0xFF9B9EF8) : _primary,
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 22),
          GestureDetector(
            onTap: _createColumn,
            child: Container(
              width: double.infinity,
              height: 48,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFF6D6AFF), Color(0xFF7A6CFF)],
                ),
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.add, size: 20, color: Colors.white),
                  SizedBox(width: 6),
                  Text(
                    '创建第一个专栏',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// 拖拽排序专栏内文章——本地重排，点「保存顺序」返回 id 数组给调用方
// 去 PUT /auth/columns/:id/articles/order
class _ReorderArticlesSheet extends StatefulWidget {
  final List<Map<String, dynamic>> articles;
  final bool isDark;
  const _ReorderArticlesSheet({required this.articles, required this.isDark});

  @override
  State<_ReorderArticlesSheet> createState() => _ReorderArticlesSheetState();
}

class _ReorderArticlesSheetState extends State<_ReorderArticlesSheet> {
  late List<Map<String, dynamic>> _items;

  @override
  void initState() {
    super.initState();
    _items = [...widget.articles];
  }

  @override
  Widget build(BuildContext context) {
    final isDark = widget.isDark;
    final card = isDark ? AppColors.darkCard : Colors.white;
    final ink = isDark ? const Color(0xFFF0F2F8) : const Color(0xFF1A1A1A);
    final muted = isDark ? const Color(0xFF7A80A0) : const Color(0xFF888888);
    final border = isDark ? AppColors.darkBorder : const Color(0xFFEBEBEB);
    final maxH = MediaQuery.of(context).size.height * 0.6;

    return Container(
      decoration: BoxDecoration(
        color: card,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
      ),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
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
              padding: const EdgeInsets.fromLTRB(4, 0, 4, 4),
              child: Text(
                '调整文章顺序',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: ink,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 0, 4, 10),
              child: Text(
                '长按右侧手柄拖动排序',
                style: TextStyle(fontSize: 12, color: muted),
              ),
            ),
            ConstrainedBox(
              constraints: BoxConstraints(maxHeight: maxH),
              child: ReorderableListView.builder(
                shrinkWrap: true,
                buildDefaultDragHandles: false,
                itemCount: _items.length,
                onReorder: (oldI, newI) {
                  setState(() {
                    if (newI > oldI) newI -= 1;
                    final it = _items.removeAt(oldI);
                    _items.insert(newI, it);
                  });
                },
                itemBuilder: (ctx, i) {
                  final a = _items[i];
                  final title = (a['title'] as String?) ?? '无标题';
                  return Container(
                    key: ValueKey(a['id'].toString()),
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
                    decoration: BoxDecoration(
                      color: isDark
                          ? Colors.white.withValues(alpha: 0.04)
                          : const Color(0xFFF7F7FA),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: border, width: 0.5),
                    ),
                    child: Row(
                      children: [
                        Text(
                          '${i + 1}',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: muted,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            title.isEmpty ? '无标题' : title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 14, color: ink),
                          ),
                        ),
                        ReorderableDragStartListener(
                          index: i,
                          child: Padding(
                            padding: const EdgeInsets.all(4),
                            child: Icon(
                              Icons.drag_handle,
                              size: 20,
                              color: muted,
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: TextButton(
                onPressed: () => Navigator.pop(
                  context,
                  _items.map((a) => a['id'].toString()).toList(),
                ),
                style: TextButton.styleFrom(
                  backgroundColor: const Color(0xFF1A1A1A),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text(
                  '保存顺序',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
