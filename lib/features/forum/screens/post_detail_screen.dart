import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_client.dart';
import '../models/forum_post_model.dart';
import '../models/forum_reply_model.dart';
import '../widgets/post_card.dart' show forumTimeAgo;

const _primary = Color(0xFF6366F1);

class PostDetailScreen extends ConsumerStatefulWidget {
  final String postId;
  const PostDetailScreen({super.key, required this.postId});

  @override
  ConsumerState<PostDetailScreen> createState() => _PostDetailScreenState();
}

class _PostDetailScreenState extends ConsumerState<PostDetailScreen> {
  ForumPost? _post;
  List<ForumReply> _replies = [];
  bool _loading = true;
  bool _liked = false;
  int _likeCount = 0;
  String _replySort = 'floor';
  String? _quoteReplyId;
  String? _quoteContent;
  String? _quoteAuthor;
  final _replyCtrl = TextEditingController();
  final _replyFocus = FocusNode();
  final _scrollCtrl = ScrollController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _replyCtrl.dispose();
    _replyFocus.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final api = ref.read(apiClientProvider);
    final postRes = await api.get('/auth/forums/posts/${widget.postId}');
    final repliesRes = await api.get(
      '/auth/forums/posts/${widget.postId}/replies',
      queryParameters: {'sort': _replySort},
    );
    if (!mounted) return;
    if (postRes.success &&
        postRes.data is Map &&
        (postRes.data as Map)['post'] != null) {
      final post = ForumPost.fromJson(
        Map<String, dynamic>.from((postRes.data as Map)['post'] as Map),
      );
      final replies = (repliesRes.success && repliesRes.data is Map)
          ? (((repliesRes.data as Map)['replies'] as List?) ?? const [])
                .map(
                  (r) =>
                      ForumReply.fromJson(Map<String, dynamic>.from(r as Map)),
                )
                .toList()
          : <ForumReply>[];
      setState(() {
        _post = post;
        _replies = replies;
        _likeCount = post.likeCount;
        _loading = false;
      });
    } else {
      setState(() => _loading = false);
    }
  }

  Future<void> _toggleLike() async {
    if (_post == null) return;
    setState(() {
      _liked = !_liked;
      _likeCount += _liked ? 1 : -1;
    });
    // ApiClient 不抛异常，失败看 res.success；失败就把乐观改动回滚
    final res = await ref
        .read(apiClientProvider)
        .post('/auth/forums/likes/${_post!.id}', data: {'target_type': 'post'});
    if (!mounted) return;
    if (!res.success) {
      setState(() {
        _liked = !_liked;
        _likeCount += _liked ? 1 : -1;
      });
    }
  }

  Future<void> _submitReply() async {
    final text = _replyCtrl.text.trim();
    if (text.isEmpty) return;
    _replyCtrl.clear();

    final res = await ref
        .read(apiClientProvider)
        .post(
          '/auth/forums/posts/${widget.postId}/replies',
          data: {
            'content': text,
            if (_quoteReplyId != null) 'quote_reply_id': _quoteReplyId,
          },
        );
    if (!mounted) return;
    if (res.success && res.data is Map && (res.data as Map)['reply'] != null) {
      final reply = ForumReply.fromJson(
        Map<String, dynamic>.from((res.data as Map)['reply'] as Map),
      );
      setState(() {
        _replies.add(reply);
        _quoteReplyId = null;
        _quoteContent = null;
        _quoteAuthor = null;
        if (_post != null) {
          _post = ForumPost.fromJson({
            ..._post!.toJson(),
            'reply_count': _post!.replyCount + 1,
          });
        }
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrollCtrl.hasClients) {
          _scrollCtrl.animateTo(
            _scrollCtrl.position.maxScrollExtent,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
          );
        }
      });
    } else {
      // 失败：把清掉的文字还回去，方便重试
      _replyCtrl.text = text;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('回复失败：${res.message ?? '请稍后重试'}')));
    }
  }

  void _replyTo(ForumReply reply) {
    setState(() {
      _quoteReplyId = reply.id;
      _quoteContent = reply.content;
      _quoteAuthor = reply.authorName;
    });
    _replyFocus.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, size: 18),
          onPressed: () => context.pop(),
        ),
        title: const Text(
          '帖子详情',
          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _post == null
          ? _buildLoadError()
          : Column(
              children: [
                Expanded(
                  // 点空白处收起键盘
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => FocusScope.of(context).unfocus(),
                    child: ListView(
                      controller: _scrollCtrl,
                      children: [
                        _buildPostBody(isDark),
                        _buildRepliesHeader(isDark),
                        ..._replies.map(
                          (reply) => _ReplyItem(
                            reply: reply,
                            isDark: isDark,
                            onReply: () => _replyTo(reply),
                            onLike: () async {
                              await ref
                                  .read(apiClientProvider)
                                  .post(
                                    '/auth/forums/likes/${reply.id}',
                                    data: {'target_type': 'reply'},
                                  );
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                if (_quoteContent != null) _buildQuotePreview(isDark),
                _buildInputBar(isDark),
              ],
            ),
    );
  }

  Widget _buildLoadError() => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.error_outline, size: 40, color: Colors.grey[300]),
        const SizedBox(height: 12),
        Text('帖子加载失败', style: TextStyle(fontSize: 14, color: Colors.grey[400])),
        const SizedBox(height: 10),
        TextButton(onPressed: _load, child: const Text('重试')),
      ],
    ),
  );

  Widget _buildPostBody(bool isDark) {
    final post = _post!;
    return Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (post.isFeatured)
            Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(
                color: const Color(0xFFFEF3C7),
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.star, size: 10, color: Color(0xFFD97706)),
                  SizedBox(width: 3),
                  Text(
                    '精华',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w500,
                      color: Color(0xFFD97706),
                    ),
                  ),
                ],
              ),
            ),

          Text(
            post.title,
            style: TextStyle(
              fontSize: 19,
              fontWeight: FontWeight.w600,
              color: isDark
                  ? Colors.white.withValues(alpha: 0.9)
                  : const Color(0xFF1A1A1A),
              height: 1.4,
            ),
          ),
          const SizedBox(height: 10),

          Row(
            children: [
              CircleAvatar(
                radius: 16,
                backgroundColor: _primary,
                child: Text(
                  post.authorName.isNotEmpty ? post.authorName[0] : 'U',
                  style: const TextStyle(
                    fontSize: 12,
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    post.authorName,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: isDark
                          ? Colors.white.withValues(alpha: 0.9)
                          : const Color(0xFF1A1A1A),
                    ),
                  ),
                  Text(
                    forumTimeAgo(post.createdAt),
                    style: TextStyle(
                      fontSize: 11,
                      color: isDark
                          ? Colors.white.withValues(alpha: 0.3)
                          : Colors.grey[400],
                    ),
                  ),
                ],
              ),
              const Spacer(),
              if (post.isAuroraCreator)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1A0E2E),
                    borderRadius: BorderRadius.circular(3),
                  ),
                  child: const Text(
                    '★ 极光',
                    style: TextStyle(
                      fontSize: 9,
                      color: Color(0xFFF59E0B),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),

          Text(
            post.content,
            style: TextStyle(
              fontSize: 15,
              color: isDark
                  ? Colors.white.withValues(alpha: 0.75)
                  : const Color(0xFF444444),
              height: 1.8,
            ),
          ),
          const SizedBox(height: 14),

          Container(
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(
              border: Border.symmetric(
                horizontal: BorderSide(
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.06)
                      : const Color(0xFFEBEBEB),
                  width: 0.5,
                ),
              ),
            ),
            child: Row(
              children: [
                _ActionBtn(
                  icon: _liked ? Icons.favorite : Icons.favorite_border,
                  color: _liked ? const Color(0xFFEF4444) : null,
                  label: '$_likeCount',
                  onTap: _toggleLike,
                ),
                const SizedBox(width: 16),
                _ActionBtn(
                  icon: Icons.chat_bubble_outline,
                  label: '${post.replyCount}',
                  onTap: () => _replyFocus.requestFocus(),
                ),
                const SizedBox(width: 16),
                _ActionBtn(
                  icon: Icons.bookmark_border,
                  label: '收藏',
                  onTap: () {},
                ),
                const Spacer(),
                _ActionBtn(icon: Icons.share, label: '分享', onTap: () {}),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRepliesHeader(bool isDark) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: isDark
                ? Colors.white.withValues(alpha: 0.06)
                : const Color(0xFFEBEBEB),
            width: 0.5,
          ),
        ),
      ),
      child: Row(
        children: [
          Text(
            '${_replies.length} 条回复',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: isDark
                  ? Colors.white.withValues(alpha: 0.5)
                  : Colors.grey[500],
            ),
          ),
          const Spacer(),
          GestureDetector(
            onTap: () {
              setState(
                () => _replySort = _replySort == 'floor' ? 'hot' : 'floor',
              );
              _load();
            },
            child: Text(
              _replySort == 'floor' ? '按楼层' : '最热',
              style: const TextStyle(fontSize: 12, color: _primary),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuotePreview(bool isDark) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withValues(alpha: 0.04)
            : const Color(0xFFF5F5FF),
        border: const Border(
          top: BorderSide(color: Color(0x4D6366F1), width: 0.5),
          left: BorderSide(color: _primary, width: 2.5),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              '回复 @$_quoteAuthor：$_quoteContent',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                color: isDark
                    ? Colors.white.withValues(alpha: 0.5)
                    : Colors.grey[500],
              ),
            ),
          ),
          GestureDetector(
            onTap: () => setState(() {
              _quoteReplyId = null;
              _quoteContent = null;
              _quoteAuthor = null;
            }),
            child: Icon(Icons.close, size: 16, color: Colors.grey[400]),
          ),
        ],
      ),
    );
  }

  Widget _buildInputBar(bool isDark) {
    return Container(
      padding: EdgeInsets.fromLTRB(
        12,
        8,
        12,
        MediaQuery.of(context).padding.bottom + 8,
      ),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF0A0A1A) : Colors.white,
        border: Border(
          top: BorderSide(
            color: isDark
                ? Colors.white.withValues(alpha: 0.06)
                : const Color(0xFFEBEBEB),
            width: 0.5,
          ),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _replyCtrl,
              focusNode: _replyFocus,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => _submitReply(),
              decoration: InputDecoration(
                hintText: '说点什么...',
                hintStyle: TextStyle(
                  fontSize: 13,
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.3)
                      : Colors.grey[400],
                ),
                filled: true,
                fillColor: isDark
                    ? Colors.white.withValues(alpha: 0.05)
                    : const Color(0xFFF5F5F5),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(20),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 9,
                ),
              ),
              style: TextStyle(
                fontSize: 13,
                color: isDark
                    ? Colors.white.withValues(alpha: 0.9)
                    : const Color(0xFF1A1A1A),
              ),
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: _submitReply,
            child: Container(
              width: 34,
              height: 34,
              decoration: const BoxDecoration(
                color: _primary,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.send_rounded,
                size: 16,
                color: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionBtn extends StatelessWidget {
  final IconData icon;
  final Color? color;
  final String label;
  final VoidCallback onTap;

  const _ActionBtn({
    required this.icon,
    this.color,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    behavior: HitTestBehavior.opaque,
    child: Row(
      children: [
        Icon(icon, size: 18, color: color ?? Colors.grey[400]),
        const SizedBox(width: 4),
        Text(
          label,
          style: TextStyle(fontSize: 13, color: color ?? Colors.grey[400]),
        ),
      ],
    ),
  );
}

class _ReplyItem extends StatefulWidget {
  final ForumReply reply;
  final bool isDark;
  final VoidCallback onReply;
  final VoidCallback onLike;

  const _ReplyItem({
    required this.reply,
    required this.isDark,
    required this.onReply,
    required this.onLike,
  });

  @override
  State<_ReplyItem> createState() => _ReplyItemState();
}

class _ReplyItemState extends State<_ReplyItem> {
  bool _liked = false;
  late int _likeCount;

  @override
  void initState() {
    super.initState();
    _likeCount = widget.reply.likeCount;
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.reply;
    final isDark = widget.isDark;

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: isDark
                ? Colors.white.withValues(alpha: 0.06)
                : const Color(0xFFEBEBEB),
            width: 0.5,
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 作者行
          Row(
            children: [
              CircleAvatar(
                radius: 12,
                backgroundColor: _primary,
                child: Text(
                  r.authorName.isNotEmpty ? r.authorName[0] : 'U',
                  style: const TextStyle(
                    fontSize: 9,
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 7),
              Text(
                r.authorName,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.8)
                      : const Color(0xFF1A1A1A),
                ),
              ),
              const SizedBox(width: 6),
              Text(
                '${r.floorNumber}楼',
                style: TextStyle(
                  fontSize: 10,
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.3)
                      : Colors.grey[400],
                ),
              ),
              const Spacer(),
              Text(
                forumTimeAgo(r.createdAt),
                style: TextStyle(
                  fontSize: 10,
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.3)
                      : Colors.grey[400],
                ),
              ),
            ],
          ),

          // 引用块
          if (r.quoteContent != null) ...[
            const SizedBox(height: 7),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
              decoration: BoxDecoration(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.04)
                    : const Color(0xFFF5F5F5),
                borderRadius: BorderRadius.circular(6),
                border: Border(
                  left: BorderSide(
                    color: isDark
                        ? Colors.white.withValues(alpha: 0.2)
                        : const Color(0xFFDDDDDD),
                    width: 2,
                  ),
                ),
              ),
              child: Text(
                '@${r.quoteAuthor}：${r.quoteContent}',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11,
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.4)
                      : Colors.grey[500],
                ),
              ),
            ),
          ],

          // 内容
          Padding(
            padding: const EdgeInsets.only(top: 6, left: 31),
            child: Text(
              r.content,
              style: TextStyle(
                fontSize: 13,
                color: isDark
                    ? Colors.white.withValues(alpha: 0.7)
                    : const Color(0xFF444444),
                height: 1.7,
              ),
            ),
          ),

          // 操作
          Padding(
            padding: const EdgeInsets.only(top: 7, left: 31),
            child: Row(
              children: [
                GestureDetector(
                  onTap: () {
                    setState(() {
                      _liked = !_liked;
                      _likeCount += _liked ? 1 : -1;
                    });
                    widget.onLike();
                  },
                  child: Row(
                    children: [
                      Icon(
                        _liked ? Icons.favorite : Icons.favorite_border,
                        size: 14,
                        color: _liked
                            ? const Color(0xFFEF4444)
                            : Colors.grey[400],
                      ),
                      const SizedBox(width: 3),
                      Text(
                        '$_likeCount',
                        style: TextStyle(
                          fontSize: 12,
                          color: _liked
                              ? const Color(0xFFEF4444)
                              : Colors.grey[400],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                GestureDetector(
                  onTap: widget.onReply,
                  child: Row(
                    children: [
                      Icon(
                        Icons.chat_bubble_outline,
                        size: 14,
                        color: Colors.grey[400],
                      ),
                      const SizedBox(width: 3),
                      Text(
                        '回复',
                        style: TextStyle(fontSize: 12, color: Colors.grey[400]),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
