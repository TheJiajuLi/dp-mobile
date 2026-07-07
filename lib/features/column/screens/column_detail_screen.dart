import 'dart:convert';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_client.dart';
import '../../../core/profile_refresh_signal.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../auth/auth_service.dart';
import '../models/column_model.dart';

const _primary = Color(0xFF6366F1);

String _initial(String? name) {
  if (name == null || name.isEmpty) return '?';
  return name.substring(0, 1).toUpperCase();
}

class ColumnDetailScreen extends ConsumerStatefulWidget {
  final String columnId;
  const ColumnDetailScreen({super.key, required this.columnId});

  @override
  ConsumerState<ColumnDetailScreen> createState() => _ColumnDetailScreenState();
}

class _ColumnDetailScreenState extends ConsumerState<ColumnDetailScreen> {
  ColumnModel? _column;
  List<dynamic> _articles = [];
  bool _loading = true;
  // 后端 GET /auth/columns/:id 是公开接口（不带认证），不会告诉客户端
  // "当前登录用户是否已订阅"——这里跟 tutorial_detail_screen.dart 里
  // _liked/_saved 的初始值处理是同一个坑：先假定未订阅，点一次订阅按钮后
  // 用响应里的真实 subscribed 字段纠正，重进页面前这个假定可能是错的
  bool _subscribed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final res = await ref
        .read(apiClientProvider)
        .get('/auth/columns/${widget.columnId}');
    if (!mounted) return;
    if (res.success && res.data != null) {
      final data = res.data as Map;
      debugPrint('[column] ${data['column']}');
      setState(() {
        _column = ColumnModel.fromJson(
          Map<String, dynamic>.from(data['column'] as Map),
        );
        _articles = data['articles'] as List? ?? [];
        _loading = false;
      });
    } else {
      setState(() => _loading = false);
    }
  }

  Future<void> _toggleSubscribe() async {
    final res = await ref
        .read(apiClientProvider)
        .post('/auth/columns/${widget.columnId}/subscribe');
    if (!mounted) return;
    if (res.success && res.data != null) {
      setState(() => _subscribed = (res.data as Map)['subscribed'] == true);
    } else {
      final l10n = AppLocalizations.of(context)!;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.actionFailedWithReason('${res.message}'))),
      );
    }
  }

  Widget _buildAuthorAvatar(
    String? avatar,
    String username, {
    double radius = 19,
  }) {
    if (avatar != null && avatar.isNotEmpty) {
      if (avatar.startsWith('data:image')) {
        try {
          final raw = avatar.split(',').last;
          return CircleAvatar(
            radius: radius,
            backgroundImage: MemoryImage(base64Decode(raw)),
          );
        } catch (_) {
          // 解码失败落到下面的首字母占位
        }
      } else {
        return CircleAvatar(
          radius: radius,
          backgroundColor: _primary,
          backgroundImage: CachedNetworkImageProvider(avatar),
        );
      }
    }
    return CircleAvatar(
      radius: radius,
      backgroundColor: _primary,
      child: Text(
        _initial(username),
        style: TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w700,
          fontSize: radius * 0.72,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final currentUserId = ref.watch(currentUserProvider)?.id;
    final isOwner = currentUserId != null && currentUserId == _column?.userId;

    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F7),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _column == null
          ? Center(child: Text(l10n.tutorialNotFound))
          : CustomScrollView(
              slivers: [
                SliverAppBar(
                  expandedHeight: 160,
                  pinned: true,
                  backgroundColor: _primary,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  actions: [
                    IconButton(
                      icon: const Icon(Icons.share_outlined),
                      onPressed: () =>
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text(l10n.comingSoonStayTuned)),
                          ),
                    ),
                  ],
                  flexibleSpace: FlexibleSpaceBar(
                    background: Stack(
                      fit: StackFit.expand,
                      children: [
                        // 封面图纯装饰，排除出语义树——不然图片异步加载完成
                        // 触发的 relayout 跟点作者头像 context.push 的转场
                        // 动画抢语义树更新，会炸出 `!semantics.parentDataDirty`
                        // 断言（tutorial_detail_screen.dart 同款封面图已经
                        // 踩过这个坑）
                        ExcludeSemantics(
                          child:
                              _column!.coverImage != null &&
                                  _column!.coverImage!.isNotEmpty
                              ? CachedNetworkImage(
                                  imageUrl: _column!.coverImage!,
                                  fit: BoxFit.cover,
                                  errorWidget: (context, url, error) =>
                                      Container(color: _primary),
                                )
                              : Container(
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      begin: Alignment.topLeft,
                                      end: Alignment.bottomRight,
                                      colors: [
                                        _primary,
                                        _primary.withValues(alpha: 0.7),
                                      ],
                                    ),
                                  ),
                                ),
                        ),
                        const DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [Colors.transparent, Colors.black54],
                            ),
                          ),
                        ),
                        Positioned(
                          bottom: 14,
                          left: 16,
                          right: 16,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _column!.name,
                                style: const TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.white,
                                ),
                              ),
                              Text(
                                l10n.columnContentCountLabel(
                                  _column!.articleCount,
                                ),
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: Colors.white70,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                SliverToBoxAdapter(
                  child: Column(
                    children: [
                      Container(
                        color: Colors.white,
                        padding: const EdgeInsets.all(14),
                        child: Row(
                          children: [
                            GestureDetector(
                              onTap: _column!.username == null
                                  ? null
                                  : () => context.push(
                                      '/users/${_column!.username}',
                                    ),
                              child: _buildAuthorAvatar(
                                _column!.avatar,
                                _column!.username ?? '',
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    _column!.username ?? '',
                                    style: const TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  if (_column!.handle != null)
                                    Text(
                                      '@${_column!.handle}',
                                      style: const TextStyle(
                                        fontSize: 11,
                                        color: Colors.grey,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                            if (!isOwner)
                              ElevatedButton(
                                onPressed: _toggleSubscribe,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: _subscribed
                                      ? Colors.grey[200]
                                      : _primary,
                                  foregroundColor: _subscribed
                                      ? Colors.black87
                                      : Colors.white,
                                  elevation: 0,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(99),
                                  ),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 8,
                                  ),
                                ),
                                child: Text(
                                  _subscribed
                                      ? l10n.subscribedLabel
                                      : l10n.subscribeColumnAction,
                                  style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                      Container(
                        color: const Color(0xFFFAFAFA),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        child: Row(
                          children: [
                            _statItem(
                              '${_column!.viewCount}',
                              l10n.columnViewsLabel,
                            ),
                            _vDivider(),
                            _statItem(
                              '${_column!.likeCount}',
                              l10n.likesCountLabel,
                            ),
                            _vDivider(),
                            _statItem(
                              '${_column!.saveCount}',
                              l10n.tabBookmarksLabel,
                            ),
                            _vDivider(),
                            _statItem(
                              '${_column!.subscriberCount}',
                              l10n.columnSubscribersLabel,
                            ),
                          ],
                        ),
                      ),
                      if (_column!.description?.isNotEmpty == true)
                        Container(
                          color: Colors.white,
                          padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                          margin: const EdgeInsets.only(top: 8),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                l10n.columnIntroLabel,
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.grey,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                _column!.description!,
                                style: const TextStyle(
                                  fontSize: 14,
                                  height: 1.65,
                                  color: Color(0xFF3C3C3C),
                                ),
                              ),
                            ],
                          ),
                        ),
                      Container(
                        margin: const EdgeInsets.only(top: 8),
                        color: Colors.white,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Padding(
                              padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
                              child: Text(
                                l10n.columnContentCountLabel(_articles.length),
                                style: const TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
                                  color: Color(0xFF1C1C1E),
                                ),
                              ),
                            ),
                            ..._articles.asMap().entries.map((e) {
                              final i = e.key;
                              final a = e.value as Map;
                              final coverImage = a['cover_image'] as String?;
                              return GestureDetector(
                                onTap: () =>
                                    context.push('/tutorial/${a['id']}'),
                                child: Container(
                                  padding: const EdgeInsets.fromLTRB(
                                    16,
                                    12,
                                    16,
                                    12,
                                  ),
                                  decoration: const BoxDecoration(
                                    border: Border(
                                      bottom: BorderSide(
                                        color: Color(0xFFF5F5F5),
                                      ),
                                    ),
                                  ),
                                  child: Row(
                                    children: [
                                      Container(
                                        width: 26,
                                        height: 26,
                                        decoration: BoxDecoration(
                                          color: i < 3
                                              ? _primary
                                              : const Color(0xFFEEF0FF),
                                          shape: BoxShape.circle,
                                        ),
                                        child: Center(
                                          child: Text(
                                            '${i + 1}',
                                            style: TextStyle(
                                              fontSize: 11,
                                              fontWeight: FontWeight.w700,
                                              color: i < 3
                                                  ? Colors.white
                                                  : _primary,
                                            ),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              a['title'] as String? ?? '',
                                              style: const TextStyle(
                                                fontSize: 14,
                                                fontWeight: FontWeight.w500,
                                                color: Color(0xFF1C1C1E),
                                              ),
                                              maxLines: 2,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                            const SizedBox(height: 4),
                                            Row(
                                              children: [
                                                const Icon(
                                                  Icons.remove_red_eye_outlined,
                                                  size: 11,
                                                  color: Colors.grey,
                                                ),
                                                const SizedBox(width: 2),
                                                Text(
                                                  '${a['views'] ?? 0}',
                                                  style: const TextStyle(
                                                    fontSize: 11,
                                                    color: Colors.grey,
                                                  ),
                                                ),
                                                const SizedBox(width: 8),
                                                const Icon(
                                                  Icons.favorite_outline,
                                                  size: 11,
                                                  color: Colors.grey,
                                                ),
                                                const SizedBox(width: 2),
                                                Text(
                                                  '${a['likes'] ?? 0}',
                                                  style: const TextStyle(
                                                    fontSize: 11,
                                                    color: Colors.grey,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                      coverImage != null &&
                                              coverImage.isNotEmpty
                                          ? ClipRRect(
                                              borderRadius:
                                                  BorderRadius.circular(8),
                                              child: CachedNetworkImage(
                                                imageUrl: coverImage,
                                                width: 60,
                                                height: 50,
                                                fit: BoxFit.cover,
                                                errorWidget:
                                                    (context, url, error) =>
                                                        _artThumb(),
                                              ),
                                            )
                                          : _artThumb(),
                                    ],
                                  ),
                                ),
                              );
                            }),
                            const SizedBox(height: 20),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),
                    ],
                  ),
                ),
              ],
            ),
      bottomNavigationBar: isOwner
          ? Container(
              decoration: const BoxDecoration(
                color: Colors.white,
                border: Border(top: BorderSide(color: Color(0xFFF0F0F0))),
              ),
              child: SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
                  child: Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: _showEditSheet,
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                            side: const BorderSide(color: Color(0xFFE5E5EA)),
                          ),
                          child: Text(
                            l10n.editColumnAction,
                            style: const TextStyle(
                              color: Color(0xFF1C1C1E),
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: _showAddArticleSheet,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _primary,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          child: Text(
                            l10n.collectContentAction,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            )
          : null,
    );
  }

  void _showEditSheet() {
    final l10n = AppLocalizations.of(context)!;
    final nameCtrl = TextEditingController(text: _column?.name);
    final descCtrl = TextEditingController(text: _column?.description);
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    l10n.editColumnAction,
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: () async {
                      if (nameCtrl.text.trim().isEmpty) return;
                      final res = await ref
                          .read(apiClientProvider)
                          .put(
                            '/auth/columns/${widget.columnId}',
                            data: {
                              'name': nameCtrl.text.trim(),
                              'description': descCtrl.text.trim(),
                            },
                          );
                      if (!ctx.mounted) return;
                      Navigator.pop(ctx);
                      if (res.success) {
                        notifyProfileShouldRefresh(ref);
                        await _load();
                      } else if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              l10n.actionFailedWithReason('${res.message}'),
                            ),
                          ),
                        );
                      }
                    },
                    child: Text(
                      l10n.save,
                      style: const TextStyle(
                        color: _primary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              TextField(
                controller: nameCtrl,
                decoration: InputDecoration(
                  labelText: l10n.columnNameLabel,
                  filled: true,
                  fillColor: Colors.grey[50],
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide.none,
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: _primary),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: descCtrl,
                maxLines: 3,
                decoration: InputDecoration(
                  labelText: l10n.columnDescOptionalLabel,
                  filled: true,
                  fillColor: Colors.grey[50],
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide.none,
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: _primary),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showAddArticleSheet() {
    final existingIds = _articles
        .map((a) => (a as Map)['id'] as String)
        .toSet();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _AddArticleSheet(
        columnId: widget.columnId,
        existingIds: existingIds,
        onAdded: () {
          Navigator.pop(ctx);
          _load();
        },
      ),
    );
  }

  Widget _statItem(String val, String label) => Expanded(
    child: Column(
      children: [
        Text(
          val,
          style: const TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w700,
            color: Color(0xFF1C1C1E),
          ),
        ),
        const SizedBox(height: 2),
        Text(label, style: const TextStyle(fontSize: 11, color: Colors.grey)),
      ],
    ),
  );

  Widget _vDivider() =>
      Container(width: 0.5, height: 32, color: Colors.grey.shade200);

  Widget _artThumb() => Container(
    width: 60,
    height: 50,
    decoration: BoxDecoration(
      color: const Color(0xFFEEF0FF),
      borderRadius: BorderRadius.circular(8),
    ),
    child: const Icon(
      Icons.article_outlined,
      color: Color(0xFFA5B4FC),
      size: 22,
    ),
  );
}

// 收录内容弹窗——从当前用户名下的教程列表里选一篇加入这个专栏。
// 后端 GET /auth/tutorials?author=xxx 不返回 status 字段（实测确认
// 2026-07-05），没法在这里标"已发布/草稿"，索性不显示这个不存在的信息
class _AddArticleSheet extends ConsumerStatefulWidget {
  final String columnId;
  final Set<String> existingIds;
  final VoidCallback onAdded;

  const _AddArticleSheet({
    required this.columnId,
    required this.existingIds,
    required this.onAdded,
  });

  @override
  ConsumerState<_AddArticleSheet> createState() => _AddArticleSheetState();
}

class _AddArticleSheetState extends ConsumerState<_AddArticleSheet> {
  List<dynamic> _myTutorials = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final userId = ref.read(currentUserProvider)?.id ?? '';
    final res = await ref
        .read(apiClientProvider)
        .get(
          '/auth/tutorials',
          queryParameters: {'author': userId, 'limit': '50'},
        );
    if (!mounted) return;
    if (res.success && res.data != null) {
      setState(() {
        _myTutorials = ((res.data as Map)['tutorials'] as List? ?? [])
            .where((t) => !widget.existingIds.contains((t as Map)['id']))
            .toList();
        _loading = false;
      });
    } else {
      setState(() => _loading = false);
    }
  }

  Future<void> _addTutorial(String tutorialId) async {
    final res = await ref
        .read(apiClientProvider)
        .post(
          '/auth/columns/${widget.columnId}/articles',
          data: {'tutorialId': tutorialId},
        );
    if (res.success) {
      notifyProfileShouldRefresh(ref);
      widget.onAdded();
    } else if (mounted) {
      final l10n = AppLocalizations.of(context)!;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.actionFailedWithReason('${res.message}'))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Container(
      height: MediaQuery.of(context).size.height * 0.7,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        children: [
          Container(
            width: 36,
            height: 4,
            margin: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(
              color: Colors.grey[300],
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Text(
            l10n.selectArticlesToCollectTitle,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _myTutorials.isEmpty
                ? Center(
                    child: Text(
                      l10n.noArticlesToCollectPrompt,
                      style: const TextStyle(color: Colors.grey),
                    ),
                  )
                : ListView.builder(
                    itemCount: _myTutorials.length,
                    itemBuilder: (ctx, i) {
                      final t = _myTutorials[i] as Map;
                      return ListTile(
                        title: Text(
                          t['title'] as String? ?? '',
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        trailing: ElevatedButton(
                          onPressed: () => _addTutorial(t['id'] as String),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _primary,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                          ),
                          child: Text(
                            l10n.collectAction,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
