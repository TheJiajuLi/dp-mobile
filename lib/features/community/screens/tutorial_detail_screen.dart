import 'dart:convert';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_client.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../../shared/widgets/tutorial_block_renderer.dart';
import '../../auth/auth_service.dart';
import '../../messages/screens/messages_screen.dart' show timeAgo;

const _primary = Color(0xFF6366F1);

String _initial(String? name) {
  if (name == null || name.isEmpty) return '?';
  return name.substring(0, 1).toUpperCase();
}

class TutorialComment {
  final String id;
  final String userId;
  final String username;
  final String? avatar;
  final String? handle;
  final String content;
  final int createdAt;
  final List<TutorialComment> replies;

  TutorialComment({
    required this.id,
    required this.userId,
    required this.username,
    this.avatar,
    this.handle,
    required this.content,
    required this.createdAt,
    this.replies = const [],
  });

  factory TutorialComment.fromJson(Map<String, dynamic> j) {
    final repliesRaw = j['replies'] as List? ?? [];
    return TutorialComment(
      id: j['id'] as String? ?? '',
      userId: j['user_id'] as String? ?? '',
      username: j['username'] as String? ?? '用户',
      avatar: j['avatar'] as String?,
      handle: j['handle'] as String?,
      content: j['content'] as String? ?? '',
      createdAt: (j['created_at'] as num?)?.toInt() ?? 0,
      replies: repliesRaw
          .map(
            (r) =>
                TutorialComment.fromJson(Map<String, dynamic>.from(r as Map)),
          )
          .toList(),
    );
  }
}

class TutorialDetailScreen extends ConsumerStatefulWidget {
  final String tutorialId;
  const TutorialDetailScreen({super.key, required this.tutorialId});

  @override
  ConsumerState<TutorialDetailScreen> createState() =>
      _TutorialDetailScreenState();
}

class _TutorialDetailScreenState extends ConsumerState<TutorialDetailScreen> {
  Map<String, dynamic>? _tutorial;
  List<dynamic> _blocks = [];
  bool _loading = true;
  bool _liked = false;

  List<TutorialComment> _comments = [];
  bool _loadingComments = false;
  bool _submitting = false;
  final _commentCtrl = TextEditingController();
  final _commentFocusNode = FocusNode();
  String? _replyToId;
  String? _replyToUsername;

  @override
  void initState() {
    super.initState();
    _load();
    _loadComments();
  }

  @override
  void dispose() {
    _commentCtrl.dispose();
    _commentFocusNode.dispose();
    super.dispose();
  }

  Future<void> _loadComments() async {
    setState(() => _loadingComments = true);
    final res = await ref
        .read(apiClientProvider)
        .get('/auth/tutorials/${widget.tutorialId}/comments');
    if (!mounted) return;
    if (res.success && res.data != null) {
      final list = ((res.data as Map)['comments'] as List? ?? [])
          .map(
            (j) =>
                TutorialComment.fromJson(Map<String, dynamic>.from(j as Map)),
          )
          .toList();
      setState(() {
        _comments = list;
        _loadingComments = false;
      });
    } else {
      setState(() => _loadingComments = false);
    }
  }

  Future<void> _submitComment() async {
    final content = _commentCtrl.text.trim();
    if (content.isEmpty) return;

    setState(() => _submitting = true);
    final res = await ref
        .read(apiClientProvider)
        .post(
          '/auth/tutorials/${widget.tutorialId}/comments',
          data: {
            'content': content,
            if (_replyToId != null) 'parentId': _replyToId,
          },
        );
    if (!mounted) return;

    if (res.success) {
      _commentCtrl.clear();
      _replyToId = null;
      _replyToUsername = null;
      _commentFocusNode.unfocus();
      await _loadComments();
    } else {
      final l10n = AppLocalizations.of(context)!;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.actionFailedWithReason('${res.message}'))),
      );
    }
    if (mounted) setState(() => _submitting = false);
  }

  Future<void> _confirmDeleteComment(String commentId) async {
    final l10n = AppLocalizations.of(context)!;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.deleteCommentTitle),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.confirmDeleteCommentMessage),
            const SizedBox(height: 4),
            Text(
              l10n.actionCannotBeUndone,
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(
              l10n.cancel,
              style: const TextStyle(color: Colors.grey),
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFDC2626),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              l10n.deleteAction,
              style: const TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    final res = await ref
        .read(apiClientProvider)
        .delete('/auth/comments/$commentId');
    if (!mounted) return;
    if (res.success) {
      await _loadComments();
    } else {
      final l10n = AppLocalizations.of(context)!;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.actionFailedWithReason('${res.message}'))),
      );
    }
  }

  Future<void> _load() async {
    final api = ref.read(apiClientProvider);
    final res = await api.get('/auth/tutorials/${widget.tutorialId}');
    if (!res.success || res.data == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    final t = res.data as Map<String, dynamic>;

    // 解析 blocks
    var blocks = <dynamic>[];
    final rawBlocks = t['blocks'];
    if (rawBlocks is String && rawBlocks.isNotEmpty) {
      try {
        final decoded = jsonDecode(rawBlocks);
        if (decoded is List) blocks = decoded;
      } catch (_) {}
    } else if (rawBlocks is List) {
      blocks = rawBlocks;
    }

    if (!mounted) return;
    setState(() {
      _tutorial = t;
      _blocks = blocks;
      // 后端字段名未确认，兼容 is_liked / liked 两种可能，同时兼容 0/1 和 bool
      _liked =
          t['is_liked'] == 1 || t['is_liked'] == true || t['liked'] == true;
      _loading = false;
    });
  }

  Future<void> _toggleLike() async {
    final api = ref.read(apiClientProvider);
    final res = _liked
        ? await api.delete('/auth/tutorials/${widget.tutorialId}/like')
        : await api.post('/auth/tutorials/${widget.tutorialId}/like');

    if (!res.success) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            AppLocalizations.of(
              context,
            )!.actionFailedWithReason('${res.message}'),
          ),
        ),
      );
      return;
    }
    setState(() {
      _liked = !_liked;
      final likes = (_tutorial!['likes'] as num?)?.toInt() ?? 0;
      _tutorial!['likes'] = _liked ? likes + 1 : (likes > 0 ? likes - 1 : 0);
    });
  }

  Widget _buildAuthorAvatar(
    String? avatar,
    String username, {
    double radius = 18,
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

  Widget _buildComment(TutorialComment c, {bool isReply = false}) {
    final l10n = AppLocalizations.of(context)!;
    final currentUserId = ref.watch(currentUserProvider)?.id;
    final isOwn = c.userId.isNotEmpty && c.userId == currentUserId;

    return Padding(
      padding: EdgeInsets.only(left: isReply ? 52 : 16, right: 16, bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            onTap: c.username.isEmpty
                ? null
                : () => context.push('/users/${c.username}'),
            child: _buildAuthorAvatar(
              c.avatar,
              c.username,
              radius: isReply ? 14 : 18,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      c.username,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (c.handle != null) ...[
                      const SizedBox(width: 4),
                      Text(
                        '@${c.handle}',
                        style: const TextStyle(
                          fontSize: 11,
                          color: Colors.grey,
                        ),
                      ),
                    ],
                    const Spacer(),
                    Text(
                      timeAgo(l10n, c.createdAt * 1000),
                      style: const TextStyle(fontSize: 11, color: Colors.grey),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  c.content,
                  style: const TextStyle(fontSize: 14, height: 1.5),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    GestureDetector(
                      onTap: () {
                        setState(() {
                          _replyToId = c.id;
                          _replyToUsername = c.username;
                        });
                        _commentFocusNode.requestFocus();
                      },
                      child: Row(
                        children: [
                          const Icon(
                            Icons.reply_outlined,
                            size: 14,
                            color: Colors.grey,
                          ),
                          const SizedBox(width: 3),
                          Text(
                            l10n.replyAction,
                            style: const TextStyle(
                              fontSize: 12,
                              color: Colors.grey,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (isOwn) ...[
                      const SizedBox(width: 16),
                      GestureDetector(
                        onTap: () => _confirmDeleteComment(c.id),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.delete_outline,
                              size: 14,
                              color: Color(0xFFDC2626),
                            ),
                            const SizedBox(width: 3),
                            Text(
                              l10n.deleteAction,
                              style: const TextStyle(
                                fontSize: 12,
                                color: Color(0xFFDC2626),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
                if (c.replies.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  ...c.replies.map((r) => _buildComment(r, isReply: true)),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (_tutorial == null) {
      final l10n = AppLocalizations.of(context)!;
      return Scaffold(
        appBar: AppBar(title: Text(l10n.tutorial)),
        body: Center(child: Text(l10n.tutorialNotFound)),
      );
    }

    final l10n = AppLocalizations.of(context)!;
    final t = _tutorial!;
    final title = t['title'] as String? ?? '';
    final username = t['username'] as String? ?? '';
    final avatar = t['avatar'] as String?;
    final likes = (t['likes'] as num?)?.toInt() ?? 0;
    final views = (t['views'] as num?)?.toInt() ?? 0;
    final coverImage = t['cover_image'] as String?;
    final createdAt = (t['created_at'] as num?)?.toInt() ?? 0;

    // 格式化时间（后端时间戳是秒级）
    final dt = DateTime.fromMillisecondsSinceEpoch(createdAt * 1000);
    final dateStr =
        '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';

    // 解析 tags：可能是 List 或 JSON 字符串
    var tags = <String>[];
    final rawTags = t['tags'];
    if (rawTags is List) {
      tags = rawTags.map((e) => e.toString()).toList();
    } else if (rawTags is String && rawTags.isNotEmpty) {
      try {
        final decoded = jsonDecode(rawTags);
        if (decoded is List) tags = decoded.map((e) => e.toString()).toList();
      } catch (_) {}
    }

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: coverImage?.isNotEmpty == true ? 220 : 0,
            pinned: true,
            backgroundColor: Theme.of(context).cardColor,
            foregroundColor: Theme.of(context).textTheme.bodyLarge?.color,
            elevation: 0,
            flexibleSpace: coverImage?.isNotEmpty == true
                ? FlexibleSpaceBar(
                    background: CachedNetworkImage(
                      imageUrl: coverImage!,
                      fit: BoxFit.cover,
                      errorWidget: (context, url, error) =>
                          Container(color: const Color(0xFFEEF0FF)),
                    ),
                  )
                : null,
          ),
          SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                  child: Text(
                    title,
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      height: 1.3,
                    ),
                  ),
                ),
                if (tags.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                    child: Wrap(
                      spacing: 6,
                      children: tags
                          .map(
                            (tag) => Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 3,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0xFFEEF0FF),
                                borderRadius: BorderRadius.circular(99),
                              ),
                              child: Text(
                                tag,
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: Color(0xFF4F46E5),
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          )
                          .toList(),
                    ),
                  ),
                GestureDetector(
                  onTap: username.isEmpty
                      ? null
                      : () => context.push('/users/$username'),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    child: Row(
                      children: [
                        _buildAuthorAvatar(avatar, username),
                        const SizedBox(width: 10),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              username,
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            Text(
                              dateStr,
                              style: const TextStyle(
                                fontSize: 12,
                                color: Colors.grey,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                const Divider(height: 1),
                ..._blocks.map(
                  (b) => buildTutorialBlockWidget(
                    context,
                    l10n,
                    Map<String, dynamic>.from(b as Map),
                  ),
                ),
              ],
            ),
          ),
          SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Divider(height: 1),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                  child: Text(
                    l10n.commentsCountLabel(_comments.length),
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                if (_loadingComments)
                  const Center(
                    child: Padding(
                      padding: EdgeInsets.all(20),
                      child: CircularProgressIndicator(),
                    ),
                  )
                else if (_comments.isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(24),
                    child: Center(
                      child: Text(
                        l10n.noCommentsYetPrompt,
                        style: const TextStyle(
                          color: Colors.grey,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  )
                else
                  ..._comments.map((c) => _buildComment(c)),
                const SizedBox(height: 80),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            decoration: BoxDecoration(
              color: Theme.of(context).cardColor,
              border: Border(
                top: BorderSide(color: Theme.of(context).dividerColor),
              ),
            ),
            child: Row(
              children: [
                GestureDetector(
                  onTap: _toggleLike,
                  child: Row(
                    children: [
                      Icon(
                        _liked ? Icons.favorite : Icons.favorite_outline,
                        color: _liked ? Colors.red : Colors.grey,
                        size: 22,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '$likes',
                        style: const TextStyle(
                          fontSize: 14,
                          color: Colors.grey,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 20),
                Row(
                  children: [
                    const Icon(
                      Icons.visibility_outlined,
                      color: Colors.grey,
                      size: 22,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '$views',
                      style: const TextStyle(fontSize: 14, color: Colors.grey),
                    ),
                  ],
                ),
                const SizedBox(width: 20),
                Row(
                  children: [
                    const Icon(
                      Icons.chat_bubble_outline,
                      color: Colors.grey,
                      size: 20,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '${_comments.length}',
                      style: const TextStyle(fontSize: 14, color: Colors.grey),
                    ),
                  ],
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.share_outlined),
                  onPressed: () {},
                ),
              ],
            ),
          ),
          Container(
            color: Theme.of(context).cardColor,
            padding: EdgeInsets.fromLTRB(
              12,
              8,
              12,
              MediaQuery.of(context).viewInsets.bottom + 8,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_replyToUsername != null)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    margin: const EdgeInsets.only(bottom: 6),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEEF0FF),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Row(
                      children: [
                        Text(
                          AppLocalizations.of(
                            context,
                          )!.replyingToLabel(_replyToUsername!),
                          style: const TextStyle(fontSize: 12, color: _primary),
                        ),
                        const Spacer(),
                        GestureDetector(
                          onTap: () => setState(() {
                            _replyToId = null;
                            _replyToUsername = null;
                          }),
                          child: const Icon(
                            Icons.close,
                            size: 14,
                            color: Colors.grey,
                          ),
                        ),
                      ],
                    ),
                  ),
                Row(
                  children: [
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: Theme.of(
                            context,
                          ).inputDecorationTheme.fillColor,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: TextField(
                          controller: _commentCtrl,
                          focusNode: _commentFocusNode,
                          decoration: InputDecoration(
                            hintText: AppLocalizations.of(
                              context,
                            )!.writeCommentHint,
                            hintStyle: const TextStyle(
                              color: Colors.grey,
                              fontSize: 14,
                            ),
                            border: InputBorder.none,
                            filled: false,
                            isDense: true,
                            contentPadding: EdgeInsets.zero,
                          ),
                          style: const TextStyle(fontSize: 14),
                          maxLines: null,
                          textInputAction: TextInputAction.send,
                          onSubmitted: (_) => _submitComment(),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    GestureDetector(
                      onTap: _submitting ? null : _submitComment,
                      child: Container(
                        width: 36,
                        height: 36,
                        decoration: const BoxDecoration(
                          color: _primary,
                          shape: BoxShape.circle,
                        ),
                        child: _submitting
                            ? const Padding(
                                padding: EdgeInsets.all(10),
                                child: CircularProgressIndicator(
                                  color: Colors.white,
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(
                                Icons.send,
                                color: Colors.white,
                                size: 16,
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
}
