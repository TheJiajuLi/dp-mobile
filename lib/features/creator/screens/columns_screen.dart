import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/network/api_client.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/models/tutorial_model.dart';
import '../../auth/auth_service.dart';
import '../../column/models/column_model.dart';
import '../widgets/creator_sheets.dart';

const _primary = AppColors.primary;

// 专栏封面预设调色板——每个专栏用 coverIndex 选一组稳定配色（后端没存
// coverIndex 时按列表位置轮换）。记录: (浅色封面条底色, 强调/图标底色,
// 深色文字色, 图标)
const _covers = <(Color, Color, Color, IconData)>[
  (Color(0xFFEEF0FF), AppColors.primary, Color(0xFF4F46E5), Icons.functions),
  (Color(0xFFF0FFF5), AppColors.success, Color(0xFF15803D), Icons.code),
  (Color(0xFFFEF3C7), Color(0xFFD97706), Color(0xFFB45309), Icons.show_chart),
  (Color(0xFFF0F9FF), Color(0xFF0284C7), Color(0xFF0369A1), Icons.nights_stay),
  (Color(0xFFFDF2F8), Color(0xFFDB2777), Color(0xFFBE185D), Icons.science),
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
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _ColumnEditorSheet(
        covers: _covers,
        title: '新建专栏',
        submitLabel: '创建专栏',
        onSubmit: (name, desc, coverIdx, img) =>
            _doCreate(name: name, desc: desc, coverIdx: coverIdx, image: img),
      ),
    );
  }

  Future<void> _doCreate({
    required String name,
    required String desc,
    required int coverIdx,
    File? image,
  }) async {
    String? coverUrl;
    if (image != null) coverUrl = await _uploadCoverImage(image);
    final res = await ref
        .read(apiClientProvider)
        .post(
          '/auth/columns',
          data: {
            'name': name.trim(),
            'description': desc.trim(),
            if (coverUrl != null) 'coverImage': coverUrl,
            if (coverIdx >= 0) 'coverIndex': coverIdx,
          },
        );
    if (!mounted) return;
    if (res.success) {
      await _load();
      _toast('专栏已创建', ok: true);
    } else {
      _toast(res.message ?? '创建失败，请稍后重试');
    }
  }

  // 自定义封面上传——跟新建专栏弹层同一套 POST /auth/files/upload（dio
  // FormData），返回 { url }
  Future<String?> _uploadCoverImage(File file) async {
    try {
      final bytes = await file.readAsBytes();
      final form = FormData.fromMap({
        'file': MultipartFile.fromBytes(
          bytes,
          filename: 'column_cover.jpg',
          contentType: DioMediaType('image', 'jpeg'),
        ),
      });
      final up = await ref
          .read(apiClientProvider)
          .post('/auth/files/upload', data: form);
      if (up.success && up.data is Map) {
        return (up.data as Map)['url'] as String?;
      }
    } catch (_) {}
    return null;
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

  // coverIndex 优先（后端存了就用），没有就按列表位置轮换
  (Color, Color, Color, IconData) _coverFor(ColumnModel c, int index) {
    final idx = c.coverIndex ?? (index % _covers.length);
    return _covers[idx.clamp(0, _covers.length - 1)];
  }

  // 封面：有自定义封面图就用图，没有就用预设强调色 + 图标
  Widget _buildColumnCover(
    ColumnModel c,
    (Color, Color, Color, IconData) cover,
  ) {
    if ((c.coverImage ?? '').isNotEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Image.network(
          c.coverImage!,
          width: 46,
          height: 46,
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) => _coverIconBox(cover),
        ),
      );
    }
    return _coverIconBox(cover);
  }

  Widget _coverIconBox((Color, Color, Color, IconData) cover) => Container(
    width: 46,
    height: 46,
    decoration: BoxDecoration(
      color: cover.$2,
      borderRadius: BorderRadius.circular(10),
    ),
    child: Icon(cover.$4, color: Colors.white, size: 22),
  );

  Widget _columnCard(ColumnModel c, int index) {
    final cover = _coverFor(c, index);
    // 深色模式下浅色封面条会太亮，改用强调色的低透明度当底、白字
    final stripBg = _isDark ? cover.$2.withValues(alpha: 0.16) : cover.$1;
    final titleColor = _isDark ? Colors.white : cover.$3;
    final subColor = _isDark
        ? Colors.white.withValues(alpha: 0.7)
        : cover.$2.withValues(alpha: 0.85);

    return Container(
      clipBehavior: Clip.hardEdge,
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _border, width: 0.5),
      ),
      child: Column(
        children: [
          // 彩色封面条：封面(图/图标) + 名称 + 文章/订阅者数
          Container(
            height: 76,
            color: stripBg,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                _buildColumnCover(c, cover),
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
                          color: titleColor,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${c.articleCount}篇文章 · ${c.subscriberCount} 订阅者',
                        style: TextStyle(fontSize: 11, color: subColor),
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
                    Expanded(
                      child: _cardBtn(
                        '编辑专栏',
                        () => _showEditColumnSheet(c, cover),
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
    showCreatorToast(context, msg, ok: ok);
  }

  // 编辑专栏（名称/简介/封面）+ 删除入口——封面走 coverIndex/coverImage，
  // 保存 PUT /auth/columns/:id，删除 DELETE /auth/columns/:id
  void _showEditColumnSheet(
    ColumnModel col,
    (Color, Color, Color, IconData) cover,
  ) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _ColumnEditorSheet(
        covers: _covers,
        title: '编辑专栏',
        submitLabel: '保存更改',
        initialName: col.name,
        initialDesc: col.description ?? '',
        initialCoverIndex: col.coverIndex,
        initialCoverImage: col.coverImage,
        onSubmit: (name, desc, coverIdx, img) => _doUpdate(
          col: col,
          name: name,
          desc: desc,
          coverIdx: coverIdx,
          image: img,
        ),
        onDelete: () => _confirmDeleteColumn(col),
      ),
    );
  }

  Future<void> _doUpdate({
    required ColumnModel col,
    required String name,
    required String desc,
    required int coverIdx,
    File? image,
  }) async {
    String? coverUrl;
    if (image != null) {
      coverUrl = await _uploadCoverImage(image);
    } else if (coverIdx == -1) {
      // 没换图、仍是「自定义」态——保留原封面图
      coverUrl = col.coverImage;
    }
    // coverIdx >= 0 时选的是预设配色，coverUrl 留 null（清掉自定义封面）
    final res = await ref
        .read(apiClientProvider)
        .put(
          '/auth/columns/${col.id}',
          data: {
            'name': name.trim(),
            'description': desc.trim(),
            'coverImage': coverUrl,
            if (coverIdx >= 0) 'coverIndex': coverIdx,
          },
        );
    if (!mounted) return;
    if (res.success) {
      await _load();
      _toast('专栏已更新', ok: true);
    } else {
      _toast(res.message ?? '保存失败，请稍后重试');
    }
  }

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
                // 默认拖拽代理是不带圆角的矩形 Material，阴影跟卡片本身
                // 10px圆角对不上，拖起来卡片底下露出一个方形底座——换成
                // 透明背景+圆角跟卡片一致的 Material，阴影贴合卡片轮廓
                proxyDecorator: (child, index, animation) => Material(
                  color: Colors.transparent,
                  elevation: 6,
                  shadowColor: Colors.black.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                  child: child,
                ),
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

// 新建/编辑专栏共用的弹层——名称/简介 + 封面选择（自定义图片 or 预设配色）
// + （编辑态）删除入口。数据落地交给外面的 onSubmit/onDelete，本组件只管 UI
class _ColumnEditorSheet extends StatefulWidget {
  final List<(Color, Color, Color, IconData)> covers;
  final String title;
  final String submitLabel;
  final String initialName;
  final String initialDesc;
  final int? initialCoverIndex;
  final String? initialCoverImage;
  final Future<void> Function(
    String name,
    String desc,
    int coverIndex,
    File? image,
  )
  onSubmit;
  final VoidCallback? onDelete;

  const _ColumnEditorSheet({
    required this.covers,
    required this.title,
    required this.submitLabel,
    this.initialName = '',
    this.initialDesc = '',
    this.initialCoverIndex,
    this.initialCoverImage,
    required this.onSubmit,
    this.onDelete,
  });

  @override
  State<_ColumnEditorSheet> createState() => _ColumnEditorSheetState();
}

class _ColumnEditorSheetState extends State<_ColumnEditorSheet> {
  late final _nameCtrl = TextEditingController(text: widget.initialName);
  late final _descCtrl = TextEditingController(text: widget.initialDesc);
  late int _coverIdx;
  File? _image;

  bool get _hasInitialImage =>
      (widget.initialCoverImage ?? '').isNotEmpty && _image == null;

  @override
  void initState() {
    super.initState();
    // 有自定义封面图 → 初始为「自定义」态(-1)，否则用预设索引
    _coverIdx = (widget.initialCoverImage ?? '').isNotEmpty
        ? -1
        : (widget.initialCoverIndex ?? 0);
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  Future<void> _pick() async {
    final img = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 800,
    );
    if (img != null && mounted) {
      setState(() {
        _image = File(img.path);
        _coverIdx = -1;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final card = isDark ? AppColors.darkCard : Colors.white;
    final ink = isDark ? AppColors.darkTextPrimary : const Color(0xFF1A1A1A);
    final muted = isDark
        ? AppColors.darkTextSecondary
        : const Color(0xFF888888);
    final border = isDark ? AppColors.darkBorder : const Color(0xFFEBEBEB);
    final fieldFill = isDark
        ? const Color(0xFF17171F)
        : const Color(0xFFF5F5F5);

    Widget field(TextEditingController c, String hint, {int maxLines = 1}) {
      return TextField(
        controller: c,
        maxLines: maxLines,
        style: TextStyle(color: ink),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: TextStyle(color: muted),
          filled: true,
          fillColor: fieldFill,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: border, width: 0.5),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: border, width: 0.5),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: _primary),
          ),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 10,
          ),
        ),
      );
    }

    // 自定义封面按钮
    Widget customCover() {
      Widget inner;
      if (_image != null) {
        inner = ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: Image.file(_image!, width: 56, height: 56, fit: BoxFit.cover),
        );
      } else if (_hasInitialImage) {
        inner = ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: Image.network(
            widget.initialCoverImage!,
            width: 56,
            height: 56,
            fit: BoxFit.cover,
          ),
        );
      } else {
        inner = Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.add_photo_alternate_outlined, size: 22, color: muted),
            const SizedBox(height: 3),
            Text('自定义', style: TextStyle(fontSize: 10, color: muted)),
          ],
        );
      }
      final selected = _coverIdx == -1;
      return GestureDetector(
        onTap: _pick,
        child: Container(
          width: 56,
          height: 56,
          clipBehavior: Clip.hardEdge,
          decoration: BoxDecoration(
            color: fieldFill,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: selected ? _primary : border,
              width: selected ? 2 : 0.5,
            ),
          ),
          child: inner,
        ),
      );
    }

    // 预设配色格
    Widget presetTile(int i) {
      final c = widget.covers[i];
      final sel = _coverIdx == i && _image == null;
      return GestureDetector(
        onTap: () => setState(() {
          _coverIdx = i;
          _image = null;
        }),
        child: Container(
          width: 56,
          height: 56,
          margin: const EdgeInsets.only(right: 8),
          decoration: BoxDecoration(
            color: c.$1,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: sel ? c.$2 : border,
              width: sel ? 2 : 0.5,
            ),
          ),
          child: Stack(
            alignment: Alignment.center,
            children: [
              Icon(c.$4, color: c.$2, size: 26),
              if (sel)
                Positioned(
                  right: 4,
                  bottom: 4,
                  child: Container(
                    width: 16,
                    height: 16,
                    decoration: BoxDecoration(
                      color: c.$2,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.check,
                      size: 11,
                      color: Colors.white,
                    ),
                  ),
                ),
            ],
          ),
        ),
      );
    }

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Container(
        decoration: BoxDecoration(
          color: card,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
        ),
        child: SafeArea(
          top: false,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    margin: const EdgeInsets.symmetric(vertical: 12),
                    decoration: BoxDecoration(
                      color: Colors.grey.withValues(alpha: 0.4),
                      borderRadius: BorderRadius.circular(99),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
                  child: Text(
                    widget.title,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: ink,
                    ),
                  ),
                ),
                // 封面选择
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '专栏封面',
                        style: TextStyle(fontSize: 12, color: muted),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          customCover(),
                          const SizedBox(width: 8),
                          Expanded(
                            child: SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              child: Row(
                                children: List.generate(
                                  widget.covers.length,
                                  presetTile,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: field(_nameCtrl, '专栏名称（必填）'),
                ),
                Padding(
                  padding: EdgeInsets.fromLTRB(
                    16,
                    0,
                    16,
                    widget.onDelete != null ? 8 : 16,
                  ),
                  child: field(_descCtrl, '简介（选填）', maxLines: 2),
                ),
                if (widget.onDelete != null) ...[
                  Divider(height: 16, thickness: 0.5, color: border),
                  InkWell(
                    onTap: () {
                      Navigator.pop(context);
                      widget.onDelete!();
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        vertical: 8,
                        horizontal: 16,
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              color: isDark
                                  ? const Color(
                                      0xFFEF4444,
                                    ).withValues(alpha: 0.16)
                                  : const Color(0xFFFEF2F2),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Icon(
                              Icons.delete_outline,
                              color: Color(0xFFEF4444),
                              size: 18,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                '删除专栏',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: Color(0xFFEF4444),
                                ),
                              ),
                              const SizedBox(height: 1),
                              Text(
                                '专栏内文章不会被删除',
                                style: TextStyle(fontSize: 11, color: muted),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  Divider(height: 16, thickness: 0.5, color: border),
                ],
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 6, 16, 28),
                  child: Column(
                    children: [
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: () {
                            if (_nameCtrl.text.trim().isEmpty) return;
                            Navigator.pop(context);
                            widget.onSubmit(
                              _nameCtrl.text,
                              _descCtrl.text,
                              _coverIdx,
                              _image,
                            );
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF1A1A1A),
                            foregroundColor: Colors.white,
                            elevation: 0,
                            padding: const EdgeInsets.symmetric(vertical: 13),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          child: Text(
                            widget.submitLabel,
                            style: const TextStyle(fontWeight: FontWeight.w500),
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      SizedBox(
                        width: double.infinity,
                        child: TextButton(
                          onPressed: () => Navigator.pop(context),
                          style: TextButton.styleFrom(
                            backgroundColor: fieldFill,
                            padding: const EdgeInsets.symmetric(vertical: 13),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          child: Text('取消', style: TextStyle(color: muted)),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
