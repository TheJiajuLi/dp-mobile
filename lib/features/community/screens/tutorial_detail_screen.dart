import 'dart:convert';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/font_size_provider.dart';
import '../../../core/network/api_client.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/aurora_badge.dart';
import '../../../core/widgets/founding_badge.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../../shared/utils/pro_access.dart';
import '../../../shared/utils/topic_badge.dart';
import '../../../shared/widgets/mention_input/mention_popup.dart';
import '../../../shared/widgets/mention_input/mention_query.dart';
import '../../../shared/widgets/tutorial_block_renderer.dart';
import '../../auth/auth_service.dart';
import '../../messages/utils/message_avatar.dart' show messageTimeAgo;
import '../widgets/tutorial_export_sheet.dart';
import '../widgets/tutorial_share_sheet.dart';

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
  final int likes;
  final List<TutorialComment> replies;
  // 元老创作者标识——后端还没有这个字段，恒为 false，等后端在
  // 评论接口的 SELECT 里加上 is_founding_creator 直接生效
  final bool isFoundingCreator;
  // 极光创作者标识——评论接口的 SELECT 已经加上 is_aurora_creator 了
  final bool isAuroraCreator;

  TutorialComment({
    required this.id,
    required this.userId,
    required this.username,
    this.avatar,
    this.handle,
    required this.content,
    required this.createdAt,
    this.likes = 0,
    this.replies = const [],
    this.isFoundingCreator = false,
    this.isAuroraCreator = false,
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
      likes: (j['likes'] as num?)?.toInt() ?? 0,
      isFoundingCreator:
          j['is_founding_creator'] == true || j['is_founding_creator'] == 1,
      isAuroraCreator:
          j['is_aurora_creator'] == true || j['is_aurora_creator'] == 1,
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
  // 从"提及"通知点进来时带上，定位并高亮评论区里被 @ 的那条评论——
  // 评论目前是在底部弹出的 Sheet 里展示的（正文页只露 2 条预览），所以
  // 收到这个参数时会自动把 Sheet 打开再滚动定位，不是在正文页里找
  final String? scrollToCommentId;
  const TutorialDetailScreen({
    super.key,
    required this.tutorialId,
    this.scrollToCommentId,
  });

  @override
  ConsumerState<TutorialDetailScreen> createState() =>
      _TutorialDetailScreenState();
}

class _TutorialDetailScreenState extends ConsumerState<TutorialDetailScreen> {
  Map<String, dynamic>? _tutorial;
  List<dynamic> _blocks = [];
  bool _loading = true;
  bool _liked = false;
  bool _saved = false;
  // null = 还没查/不适用（比如在看自己的教程），不显示关注按钮
  bool? _isFollowing;

  List<TutorialComment> _comments = [];
  bool _loadingComments = false;
  bool _submitting = false;
  final _commentCtrl = TextEditingController();
  final _commentFocusNode = FocusNode();
  // @ 提及：纯逻辑对象，操作的是上面这份 _commentCtrl，不额外持有 controller。
  // _mentionQuery == null 表示当前不在 @ 输入态，浮层不显示。
  final _mention = MentionQuery();
  String? _mentionQuery;
  String? _replyToId;
  String? _replyToUsername;
  String _commentSort = 'hot';
  // 评论点赞：后端 tutorial_comments 表虽然有 likes 列，但目前没有任何
  // "点赞评论"的接口去真的+1——这里只做本地临时切换，纯UI态，不落库，
  // 刷新/重进页面就会丢失，等后端补上真实点赞接口后再换成真调用
  final Set<String> _locallyLikedCommentIds = {};

  final Map<String, GlobalKey> _commentKeys = {};
  String? _highlightedCommentId;

  GlobalKey _keyFor(String commentId) =>
      _commentKeys.putIfAbsent(commentId, () => GlobalKey());

  // 阅读进度 + 顶栏"滚过封面后显示标题/实底"的状态
  final ScrollController _scrollCtrl = ScrollController();
  final ValueNotifier<double> _progress = ValueNotifier(0);
  final ValueNotifier<bool> _barSolid = ValueNotifier(false);

  @override
  void initState() {
    super.initState();
    _scrollCtrl.addListener(_onScroll);
    _load();
    _loadComments().then((_) {
      if (widget.scrollToCommentId != null) {
        _openCommentSheetAndScrollTo(widget.scrollToCommentId!);
      }
    });
  }

  void _onScroll() {
    final max = _scrollCtrl.position.maxScrollExtent;
    if (max > 0) {
      _progress.value = (_scrollCtrl.offset / max).clamp(0.0, 1.0);
    }
    final solid = _scrollCtrl.offset >= 100;
    if (solid != _barSolid.value) _barSolid.value = solid;
  }

  @override
  void dispose() {
    _scrollCtrl.dispose();
    _progress.dispose();
    _barSolid.dispose();
    _commentCtrl.dispose();
    _commentFocusNode.dispose();
    super.dispose();
  }

  // 顶栏「A」字体大小调节——直接调全局 fontSizeProvider（main.dart 的
  // textScaler 消费它），阅读页和全 App 一致
  void _showFontSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: BoxDecoration(
          color: Theme.of(ctx).cardColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '字体大小',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
              ),
              Consumer(
                builder: (context, ref, _) {
                  final size = ref.watch(fontSizeProvider);
                  return Row(
                    children: [
                      const Text('A', style: TextStyle(fontSize: 13)),
                      Expanded(
                        child: Slider(
                          value: size.clamp(0.85, 1.35),
                          min: 0.85,
                          max: 1.35,
                          divisions: 5,
                          activeColor: _primary,
                          onChanged: (v) =>
                              ref.read(fontSizeProvider.notifier).setSize(v),
                        ),
                      ),
                      const Text('A', style: TextStyle(fontSize: 22)),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
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

  // 评论弹窗是 showModalBottomSheet 起的独立路由，不是父级 build() 的直接
  // 子树——父级 setState 刷新不到弹窗里已经画出来的内容，弹窗内的操作都要
  // 额外调一次 sheetSetState 才能让弹窗本身立刻看到最新数据
  Future<void> _submitComment({StateSetter? sheetSetState}) async {
    final content = _commentCtrl.text.trim();
    if (content.isEmpty) return;

    setState(() => _submitting = true);
    sheetSetState?.call(() {});
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
      // clear() 是程序化改文本，不会触发 onChanged，若发送时 @ 浮层还开着，
      // _mentionQuery 会残留导致浮层不消失——这里手动复位
      _mentionQuery = null;
      _mention.reset();
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
    sheetSetState?.call(() {});
  }

  // 输入变化时只做一件事：判断当前是否在 @ 输入态、更新浮层查询词。
  // 完全不碰 _commentCtrl 的文本，也不动提交/回复/焦点逻辑。
  void _onCommentChanged(StateSetter? sheetSetState) {
    final query = _mention.detect(_commentCtrl);
    if (query == _mentionQuery) return;
    setState(() => _mentionQuery = query);
    sheetSetState?.call(() {});
  }

  Future<void> _confirmDeleteComment(
    String commentId, {
    StateSetter? sheetSetState,
  }) async {
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
      sheetSetState?.call(() {});
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
      _saved =
          t['is_saved'] == 1 || t['is_saved'] == true || t['saved'] == true;
      _loading = false;
    });

    final authorId = t['user_id'] as String?;
    final currentUserId = ref.read(currentUserProvider)?.id;
    if (authorId != null && authorId.isNotEmpty && authorId != currentUserId) {
      final followRes = await api.get('/auth/users/$authorId/follow-status');
      if (!mounted) return;
      if (followRes.success && followRes.data != null) {
        setState(
          () => _isFollowing = (followRes.data as Map)['isFollowing'] == true,
        );
      }
    }
  }

  Future<void> _toggleFollow() async {
    final authorId = _tutorial?['user_id'] as String?;
    if (authorId == null || _isFollowing == null) return;
    final api = ref.read(apiClientProvider);
    final res = _isFollowing!
        ? await api.delete('/auth/users/$authorId/follow')
        : await api.post('/auth/users/$authorId/follow');
    if (!mounted) return;
    if (res.success) {
      setState(() => _isFollowing = !_isFollowing!);
    } else {
      final l10n = AppLocalizations.of(context)!;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.actionFailedWithReason('${res.message}'))),
      );
    }
  }

  Future<void> _toggleSave() async {
    final api = ref.read(apiClientProvider);
    final res = _saved
        ? await api.delete('/auth/tutorials/${widget.tutorialId}/save')
        : await api.post('/auth/tutorials/${widget.tutorialId}/save');
    if (!mounted) return;
    if (res.success) {
      setState(() => _saved = !_saved);
    } else {
      final l10n = AppLocalizations.of(context)!;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.actionFailedWithReason('${res.message}'))),
      );
    }
  }

  // 顶部/底部两处"分享"图标之前都是占位 toast，现在都指向同一个真实的
  // 分享 Sheet
  void _showShare() {
    final tutorial = _tutorial;
    if (tutorial == null) return;
    showTutorialShareSheet(context, tutorial);
  }

  // "···"之前是纯占位 toast——顶部这一排本来就已经有收藏（真实）/分享
  // （现在也真实了）两个独立按钮，这里不重复塞一遍，只加真正落地的
  // "导出 PDF"，不为了凑活截图 Demo 里的四项菜单去编一个不存在的
  // "举报"功能
  // 顶栏 PDF 图标直接打开导出面板（PDF/Markdown + 版面样式），不再套一层
  // 只有单个"导出 PDF"项的「...」浮层菜单
  void _openExportSheet() {
    final tutorial = _tutorial;
    if (tutorial == null) return;
    // 一键导出 PDF 是 Pro 权益——点了才校验，非 Pro 弹会员 Sheet 引导升级
    if (!requirePro(context, ref, feature: '一键导出 PDF')) return;
    showTutorialExportSheet(context, tutorial: tutorial, blocks: _blocks);
  }

  void _toggleCommentLike(String commentId, StateSetter? sheetSetState) {
    void update() {
      if (_locallyLikedCommentIds.contains(commentId)) {
        _locallyLikedCommentIds.remove(commentId);
      } else {
        _locallyLikedCommentIds.add(commentId);
      }
    }

    setState(update);
    sheetSetState?.call(() {});
  }

  List<TutorialComment> _sortedComments(String sort) {
    final list = [..._comments];
    if (sort == 'hot') {
      list.sort((a, b) => _displayLikes(b).compareTo(_displayLikes(a)));
    } else {
      list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    }
    return list;
  }

  int _displayLikes(TutorialComment c) =>
      c.likes + (_locallyLikedCommentIds.contains(c.id) ? 1 : 0);

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
    bool isFoundingCreator = false,
    bool isAuroraCreator = false,
  }) {
    return AuroraAvatarRing(
      isAuroraCreator: isAuroraCreator,
      size: radius * 2,
      child: FoundingAvatarRing(
        isFoundingCreator: isFoundingCreator,
        size: radius * 2,
        child: _plainAvatar(avatar, username, radius: radius),
      ),
    );
  }

  Widget _plainAvatar(String? avatar, String username, {double radius = 18}) {
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

  Widget _buildComment(
    TutorialComment c, {
    bool isReply = false,
    StateSetter? sheetSetState,
  }) {
    final l10n = AppLocalizations.of(context)!;
    final currentUserId = ref.watch(currentUserProvider)?.id;
    final isOwn = c.userId.isNotEmpty && c.userId == currentUserId;
    final isAuthor = c.userId.isNotEmpty && c.userId == _tutorial?['user_id'];
    final commentLiked = _locallyLikedCommentIds.contains(c.id);
    final isHighlighted = _highlightedCommentId == c.id;

    return Container(
      key: _keyFor(c.id),
      decoration: BoxDecoration(
        color: isHighlighted ? const Color(0xFFFFF8E6) : null,
        border: isHighlighted
            ? const Border(left: BorderSide(color: _primary, width: 3))
            : null,
      ),
      child: Padding(
        padding: EdgeInsets.only(
          left: isReply ? 52 : 16,
          right: 16,
          bottom: 12,
        ),
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
                isFoundingCreator: c.isFoundingCreator,
                isAuroraCreator: c.isAuroraCreator,
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
                      if (c.isFoundingCreator) const FoundingBadgeSmall(),
                      if (c.isAuroraCreator) const AuroraBadgeSmall(),
                      if (isAuthor) ...[
                        const SizedBox(width: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 5,
                            vertical: 1,
                          ),
                          decoration: BoxDecoration(
                            color: _primary.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            l10n.authorLabel,
                            style: const TextStyle(
                              fontSize: 10,
                              color: _primary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
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
                        messageTimeAgo(l10n, c.createdAt * 1000),
                        style: const TextStyle(
                          fontSize: 11,
                          color: Colors.grey,
                        ),
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
                        onTap: () => _toggleCommentLike(c.id, sheetSetState),
                        child: Row(
                          children: [
                            Icon(
                              commentLiked
                                  ? Icons.favorite
                                  : Icons.favorite_outline,
                              size: 14,
                              color: commentLiked ? Colors.red : Colors.grey,
                            ),
                            const SizedBox(width: 3),
                            Text(
                              '${_displayLikes(c)}',
                              style: const TextStyle(
                                fontSize: 12,
                                color: Colors.grey,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 16),
                      GestureDetector(
                        onTap: () {
                          setState(() {
                            _replyToId = c.id;
                            _replyToUsername = c.username;
                          });
                          sheetSetState?.call(() {});
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
                          onTap: () => _confirmDeleteComment(
                            c.id,
                            sheetSetState: sheetSetState,
                          ),
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
                    ...c.replies.map((r) {
                      final replyIsAuthor = r.userId == _tutorial?['user_id'];
                      final reply = _buildComment(
                        r,
                        isReply: true,
                        sheetSetState: sheetSetState,
                      );
                      if (!replyIsAuthor) return reply;
                      return Container(
                        margin: const EdgeInsets.only(bottom: 4),
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFAFAF8),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: reply,
                      );
                    }),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      final isDark = Theme.of(context).brightness == Brightness.dark;
      return Scaffold(
        // 加载态背景也统一成首页米白 #FAFAF8（浅色），不再是默认的偏冷灰白
        backgroundColor: isDark
            ? Theme.of(context).scaffoldBackgroundColor
            : const Color(0xFFFAFAF8),
        body: const Center(child: CircularProgressIndicator(color: _primary)),
      );
    }

    if (_tutorial == null) {
      final l10n = AppLocalizations.of(context)!;
      return Scaffold(
        appBar: AppBar(title: Text(l10n.tutorial)),
        body: Center(child: Text(l10n.tutorialNotFound)),
      );
    }

    final l10n = AppLocalizations.of(context)!;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final t = _tutorial!;
    final title = t['title'] as String? ?? '';
    final username = t['username'] as String? ?? '';
    final avatar = t['avatar'] as String?;
    final authorIsFoundingCreator =
        t['is_founding_creator'] == true || t['is_founding_creator'] == 1;
    final authorIsAuroraCreator =
        t['is_aurora_creator'] == true || t['is_aurora_creator'] == 1;
    final likes = (t['likes'] as num?)?.toInt() ?? 0;
    final coverImage = t['cover_image'] as String?;
    final createdAt = (t['created_at'] as num?)?.toInt() ?? 0;
    final summary = t['summary'] as String?;
    // subtitle/series_tag/column_id：发布页"标题植入/加入专栏"功能会提交
    // 这三个字段，但实测确认（2026-07-05）后端 tutorials 表压根没有这几列，
    // POST 时会被静默丢弃——GET 永远拿不到，这里仍按给的设计做非空判断，
    // 一旦后端补上这几列就能直接生效，不用等它已存在的原因是先把展示
    // 逻辑接好比事后再补更省事
    final subtitle = t['subtitle'] as String?;
    final seriesTag = t['series_tag'] as String?;
    final columnId = t['column_id'] as String?;

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

    final topicRule = matchedTopicRuleFor(tags);
    final previewComments = _comments.take(2).toList();

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: CustomScrollView(
        controller: _scrollCtrl,
        slivers: [
          // 顶栏（slim，常驻）：返回 + 滚过封面后浮现的标题 + 字体 + 更多；
          // 底边一条阅读进度条随滚动实时更新
          ValueListenableBuilder<bool>(
            valueListenable: _barSolid,
            builder: (context, solid, _) => SliverAppBar(
              toolbarHeight: 48,
              pinned: true,
              elevation: 0,
              scrolledUnderElevation: 0,
              backgroundColor: Theme.of(context).scaffoldBackgroundColor,
              surfaceTintColor: Colors.transparent,
              foregroundColor: Theme.of(context).textTheme.bodyLarge?.color,
              titleSpacing: 0,
              centerTitle: false,
              leading: IconButton(
                icon: const Icon(Icons.arrow_back_ios, size: 18),
                onPressed: () => context.pop(),
              ),
              title: AnimatedOpacity(
                opacity: solid ? 1 : 0,
                duration: const Duration(milliseconds: 180),
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              actions: [
                IconButton(
                  icon: const Icon(Icons.format_size),
                  onPressed: _showFontSheet,
                ),
                IconButton(
                  icon: const Icon(Icons.picture_as_pdf_outlined),
                  tooltip: '导出 PDF',
                  onPressed: _openExportSheet,
                ),
              ],
              bottom: PreferredSize(
                preferredSize: const Size.fromHeight(3),
                child: ValueListenableBuilder<double>(
                  valueListenable: _progress,
                  builder: (context, v, _) => LinearProgressIndicator(
                    value: v,
                    minHeight: 3,
                    backgroundColor: isDark
                        ? const Color(0xFF1E1E3A)
                        : const Color(0xFFEBEBEB),
                    valueColor: const AlwaysStoppedAnimation(_primary),
                  ),
                ),
              ),
            ),
          ),
          // 封面区：16:9 封面图 + 底部渐变遮罩 + 标签浮层
          SliverToBoxAdapter(
            child: ExcludeSemantics(
              // 封面图纯装饰、不承载信息，排除出语义树——不然图片异步加载完成
              // 触发的 relayout 会跟点头像 context.push 的转场抢语义树更新，
              // 炸出 `!semantics.parentDataDirty` 断言
              child: AspectRatio(
                aspectRatio: 16 / 9,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (coverImage?.isNotEmpty == true)
                      CachedNetworkImage(
                        imageUrl: coverImage!,
                        fit: BoxFit.cover,
                        errorWidget: (context, url, error) =>
                            _CoverGradient(rule: topicRule),
                      )
                    else
                      _CoverGradient(rule: topicRule),
                    // 底部渐变遮罩，让浮在封面上的标签更清晰
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      child: Container(
                        height: 80,
                        decoration: const BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [Colors.transparent, Color(0x99000000)],
                          ),
                        ),
                      ),
                    ),
                    if (tags.isNotEmpty)
                      Positioned(
                        left: 12,
                        bottom: 10,
                        child: Row(
                          children: tags
                              .take(2)
                              .map(
                                (tg) => Container(
                                  margin: const EdgeInsets.only(right: 6),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 9,
                                    vertical: 3,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(99),
                                  ),
                                  child: Text(
                                    tg,
                                    style: const TextStyle(
                                      fontSize: 10,
                                      color: Colors.white,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ),
                              )
                              .toList(),
                        ),
                      ),
                    if (seriesTag != null && seriesTag.isNotEmpty)
                      Positioned(
                        right: 12,
                        bottom: 10,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: _primary,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            seriesTag,
                            style: const TextStyle(
                              fontSize: 12,
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (subtitle != null && subtitle.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Text(
                        subtitle,
                        style: const TextStyle(fontSize: 12, color: _primary),
                      ),
                    ),
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w600,
                      color: isDark
                          ? const Color(0xFFF0F2F8)
                          : const Color(0xFF1A1A1A),
                      letterSpacing: -0.2,
                      height: 1.4,
                    ),
                  ),
                  if (summary != null && summary.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      summary,
                      style: const TextStyle(
                        fontSize: 14,
                        color: Color(0xFF888888),
                        height: 1.65,
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  const Divider(height: 1),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: GestureDetector(
                          onTap: username.isEmpty
                              ? null
                              : () => context.push('/users/$username'),
                          child: Row(
                            children: [
                              _buildAuthorAvatar(
                                avatar,
                                username,
                                radius: 18,
                                isFoundingCreator: authorIsFoundingCreator,
                                isAuroraCreator: authorIsAuroraCreator,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Text(
                                          username,
                                          style: const TextStyle(
                                            fontSize: 14,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                        if (authorIsFoundingCreator)
                                          const FoundingBadgeSmall(),
                                        if (authorIsAuroraCreator)
                                          const AuroraBadgeSmall(),
                                      ],
                                    ),
                                    Text(
                                      '$dateStr · ${l10n.estimatedReadMinutes(_readMinutes())}',
                                      style: const TextStyle(
                                        fontSize: 11,
                                        color: Color(0xFFBBBBBB),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      if (_isFollowing != null)
                        GestureDetector(
                          onTap: _toggleFollow,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: _isFollowing!
                                  ? Theme.of(context).scaffoldBackgroundColor
                                  : _primary,
                              borderRadius: BorderRadius.circular(8),
                              border: _isFollowing!
                                  ? Border.all(
                                      color: Theme.of(context).dividerColor,
                                    )
                                  : null,
                            ),
                            child: Text(
                              _isFollowing!
                                  ? l10n.followingAction
                                  : l10n.followAction,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: _isFollowing!
                                    ? Theme.of(
                                        context,
                                      ).textTheme.bodyLarge?.color
                                    : Colors.white,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ..._blocks.map(
                  (b) => buildTutorialBlockWidget(
                    context,
                    l10n,
                    Map<String, dynamic>.from(b as Map),
                    readingMode: true,
                  ),
                ),
                if (columnId != null && columnId.isNotEmpty)
                  _buildColumnCard(l10n, columnId),
                if (tags.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                    child: Wrap(
                      spacing: 6,
                      children: tags.map((tag) {
                        final isDark =
                            Theme.of(context).brightness == Brightness.dark;
                        return Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: isDark
                                ? Colors.white.withValues(alpha: 0.08)
                                : const Color(0xFFEEF0FF),
                            borderRadius: BorderRadius.circular(99),
                          ),
                          child: Text(
                            tag,
                            style: TextStyle(
                              fontSize: 12,
                              color: isDark
                                  ? const Color(0xFF9B9EF8)
                                  : const Color(0xFF4F46E5),
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
              ],
            ),
          ),
          SliverToBoxAdapter(child: _buildAuthorCard(isDark, l10n)),
          SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Divider(height: 1),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                  child: Row(
                    children: [
                      Text(
                        l10n.commentsCountLabel(_comments.length),
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const Spacer(),
                      if (_comments.length > 2)
                        GestureDetector(
                          onTap: _openCommentSheet,
                          child: Text(
                            l10n.viewAllCommentsAction,
                            style: const TextStyle(
                              fontSize: 13,
                              color: _primary,
                            ),
                          ),
                        ),
                    ],
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
                  ...previewComments.map((c) => _buildComment(c)),
                const SizedBox(height: 80),
              ],
            ),
          ),
        ],
      ),
      // Container 包 SafeArea，不是反过来——SafeArea 包 Container 只是把
      // padding 加在 Container 外面，白色背景到不了 home indicator 那圈
      // 安全区，露出 Scaffold 背景，跟之前设置页/Notebook页同一个坑
      bottomNavigationBar: Container(
        // 之前用 cardColor（浅色纯白/深色 darkCard），跟正文区域的
        // scaffoldBackgroundColor 不是同一个色阶，底部这条栏会跟上面
        // 内容拼出一条能看出来的接缝——统一改成跟正文同一个背景色，
        // 靠上面这条细描边分隔，不靠色差
        decoration: BoxDecoration(
          color: Theme.of(context).scaffoldBackgroundColor,
          border: Border(
            top: BorderSide(color: Theme.of(context).dividerColor),
          ),
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: Row(
              children: [
                _bottomAction(
                  icon: _liked ? Icons.favorite : Icons.favorite_border,
                  color: _liked ? const Color(0xFFEF4444) : Colors.grey[400]!,
                  label: '$likes',
                  onTap: _toggleLike,
                ),
                const SizedBox(width: 22),
                _bottomAction(
                  icon: Icons.chat_bubble_outline,
                  color: Colors.grey[400]!,
                  label: '${_comments.length}',
                  onTap: _openCommentSheet,
                ),
                const SizedBox(width: 22),
                _bottomAction(
                  icon: _saved ? Icons.bookmark : Icons.bookmark_border,
                  color: _saved ? _primary : Colors.grey[400]!,
                  label: '收藏',
                  onTap: _toggleSave,
                ),
                const Spacer(),
                // 分享——紫色突出
                GestureDetector(
                  onTap: _showShare,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: _primary,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.share_outlined,
                          size: 14,
                          color: Colors.white,
                        ),
                        SizedBox(width: 5),
                        Text(
                          '分享',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: Colors.white,
                          ),
                        ),
                      ],
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

  Widget _bottomAction({
    required IconData icon,
    required Color color,
    required String label,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 22, color: color),
          const SizedBox(height: 2),
          Text(label, style: TextStyle(fontSize: 11, color: Colors.grey[500])),
        ],
      ),
    );
  }

  int _readMinutes() {
    const wordsPerMinute = 300;
    final chars = _blocks
        .whereType<Map>()
        .where((b) => b['type'] == null || b['type'] == 'text')
        .fold<int>(0, (sum, b) => sum + ('${b['content'] ?? ''}'.length));
    return (chars / wordsPerMinute).ceil().clamp(1, 999);
  }

  // 文章末尾作者卡片。教程 payload 只带 username/avatar/徽章/user_id，没有
  // 简介/文章数/获赞/粉丝这些统计（要另拉作者主页接口，而那个接口实测
  // 不可靠），所以只展示手头真实有的字段，不编造数字凑 Demo
  Widget _buildAuthorCard(bool isDark, AppLocalizations l10n) {
    final t = _tutorial!;
    final username = t['username'] as String? ?? '';
    final avatar = t['avatar'] as String?;
    final founding =
        t['is_founding_creator'] == true || t['is_founding_creator'] == 1;
    final aurora =
        t['is_aurora_creator'] == true || t['is_aurora_creator'] == 1;
    final bio = t['bio'] as String?;
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkCard : const Color(0xFFF8F8FF),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark ? AppColors.darkBorder : const Color(0xFFE8E8FF),
          width: 0.5,
        ),
      ),
      child: Row(
        children: [
          GestureDetector(
            onTap: username.isEmpty
                ? null
                : () => context.push('/users/$username'),
            child: _buildAuthorAvatar(
              avatar,
              username,
              radius: 22,
              isFoundingCreator: founding,
              isAuroraCreator: aurora,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        username,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: isDark
                              ? const Color(0xFFF0F2F8)
                              : const Color(0xFF1A1A1A),
                        ),
                      ),
                    ),
                    if (founding) const FoundingBadgeSmall(),
                    if (aurora) const AuroraBadgeSmall(),
                  ],
                ),
                if (bio != null && bio.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(
                    bio,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, color: Colors.grey[500]),
                  ),
                ],
              ],
            ),
          ),
          if (_isFollowing != null) ...[
            const SizedBox(width: 10),
            ElevatedButton(
              onPressed: _toggleFollow,
              style: ElevatedButton.styleFrom(
                elevation: 0,
                backgroundColor: _isFollowing!
                    ? (isDark ? Colors.white10 : Colors.grey[200])
                    : _primary,
                foregroundColor: _isFollowing!
                    ? Colors.grey[600]
                    : Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 6,
                ),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
              ),
              child: Text(
                _isFollowing! ? l10n.followingAction : l10n.followAction,
                style: const TextStyle(fontSize: 12),
              ),
            ),
          ],
        ],
      ),
    );
  }

  // 专栏卡片：column_id 目前永远是 null（见 build() 里的说明），这里只做
  // 兜底渲染——一旦后端真的有专栏数据也不至于要再补一次UI
  Widget _buildColumnCard(AppLocalizations l10n, String columnId) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [_primary, Color(0xFFA855F7)],
              ),
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.partOfColumnLabel,
                  style: const TextStyle(fontSize: 11, color: _primary),
                ),
                Text(
                  _tutorial?['column_name'] as String? ??
                      l10n.untitledColumnLabel,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          const Icon(Icons.chevron_right, color: Colors.grey, size: 18),
        ],
      ),
    );
  }

  void _openCommentSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) => _buildCommentSheet(ctx, setModalState),
      ),
    );
  }

  // 从"提及"通知跳进来定位某条评论——评论只在这个 Sheet 里完整展示，
  // 所以先把 Sheet 打开，等它展开动画+首帧渲染完（GlobalKey 才有
  // currentContext）再滚动定位+高亮
  Future<void> _openCommentSheetAndScrollTo(String commentId) async {
    StateSetter? capturedSetModalState;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) {
          capturedSetModalState = setModalState;
          return _buildCommentSheet(ctx, setModalState);
        },
      ),
    );
    await Future.delayed(const Duration(milliseconds: 350));
    if (!mounted) return;
    _scrollToComment(commentId, sheetSetState: capturedSetModalState);
  }

  void _scrollToComment(String commentId, {StateSetter? sheetSetState}) {
    final targetContext = _commentKeys[commentId]?.currentContext;
    if (targetContext == null) return;
    Scrollable.ensureVisible(
      targetContext,
      duration: const Duration(milliseconds: 500),
      curve: Curves.easeInOut,
      alignment: 0.3,
    );
    setState(() => _highlightedCommentId = commentId);
    sheetSetState?.call(() {});
    Future.delayed(const Duration(seconds: 3), () {
      if (!mounted) return;
      setState(() => _highlightedCommentId = null);
      sheetSetState?.call(() {});
    });
  }

  Widget _buildCommentSheet(BuildContext ctx, StateSetter setModalState) {
    final l10n = AppLocalizations.of(ctx)!;
    final sorted = _sortedComments(_commentSort);
    return FractionallySizedBox(
      heightFactor: 0.75,
      child: Container(
        decoration: BoxDecoration(
          color: Theme.of(ctx).cardColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          children: [
            const SizedBox(height: 10),
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
              child: Row(
                children: [
                  Text(
                    l10n.allCommentsCountLabel(_comments.length),
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const Spacer(),
                  _sortToggleButton(l10n.sortHot, 'hot', setModalState),
                  const SizedBox(width: 8),
                  _sortToggleButton(l10n.sortNew, 'new', setModalState),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: _loadingComments
                  ? const Center(child: CircularProgressIndicator())
                  : sorted.isEmpty
                  ? Center(
                      child: Text(
                        l10n.noCommentsYetPrompt,
                        style: const TextStyle(
                          color: Colors.grey,
                          fontSize: 14,
                        ),
                      ),
                    )
                  : ListView(
                      padding: const EdgeInsets.only(top: 12),
                      children: sorted
                          .map(
                            (c) =>
                                _buildComment(c, sheetSetState: setModalState),
                          )
                          .toList(),
                    ),
            ),
            _buildCommentInputBar(sheetSetState: setModalState),
          ],
        ),
      ),
    );
  }

  Widget _sortToggleButton(
    String label,
    String value,
    StateSetter setModalState,
  ) {
    final selected = _commentSort == value;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return GestureDetector(
      onTap: () {
        setState(() => _commentSort = value);
        setModalState(() {});
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: selected
              ? (isDark
                    ? Colors.white.withValues(alpha: 0.08)
                    : const Color(0xFFEEF0FF))
              : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: selected
                ? (isDark ? const Color(0xFF9B9EF8) : _primary)
                : Colors.grey,
          ),
        ),
      ),
    );
  }

  Widget _buildCommentInputBar({StateSetter? sheetSetState}) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
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
          // @ 提及浮层——只在输入 @ 时出现，选中后回填到 _commentCtrl
          if (_mentionQuery != null)
            MentionPopup(
              query: _mentionQuery!,
              onSelect: (username) {
                _mention.insert(_commentCtrl, username);
                setState(() => _mentionQuery = null);
                sheetSetState?.call(() {});
              },
            ),
          if (_replyToUsername != null)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              margin: const EdgeInsets.only(bottom: 6),
              decoration: BoxDecoration(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.08)
                    : const Color(0xFFEEF0FF),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Row(
                children: [
                  Text(
                    AppLocalizations.of(
                      context,
                    )!.replyingToLabel(_replyToUsername!),
                    style: TextStyle(
                      fontSize: 12,
                      color: isDark ? const Color(0xFF9B9EF8) : _primary,
                    ),
                  ),
                  const Spacer(),
                  GestureDetector(
                    onTap: () {
                      setState(() {
                        _replyToId = null;
                        _replyToUsername = null;
                      });
                      sheetSetState?.call(() {});
                    },
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
              CircleAvatar(
                radius: 15,
                backgroundColor: _primary,
                child: Text(
                  _initial(ref.watch(currentUserProvider)?.username),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: Theme.of(context).inputDecorationTheme.fillColor,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: TextField(
                    controller: _commentCtrl,
                    focusNode: _commentFocusNode,
                    decoration: InputDecoration(
                      hintText: AppLocalizations.of(context)!.writeCommentHint,
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
                    onChanged: (_) => _onCommentChanged(sheetSetState),
                    onSubmitted: (_) =>
                        _submitComment(sheetSetState: sheetSetState),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: _submitting
                    ? null
                    : () => _submitComment(sheetSetState: sheetSetState),
                child: Container(
                  width: 36,
                  height: 36,
                  decoration: const BoxDecoration(
                    color: Color(0xFF1A1A1A),
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
                      : const Icon(Icons.send, color: Colors.white, size: 16),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// 无封面图时的话题色渐变占位——跟首页 Feed 卡片的 _CoverPlaceholder（按
// 标题首字符 hash 选色）不是一回事：这里按 CONTEXT.md 的领域配色表根据
// tags 决定颜色，更贴题
class _CoverGradient extends StatelessWidget {
  final TopicBadgeRule? rule;
  const _CoverGradient({required this.rule});

  @override
  Widget build(BuildContext context) {
    final fg = rule?.fg ?? topicBadgeDefault.fg;
    final bg = rule?.bg ?? topicBadgeDefault.bg;
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [bg, Color.lerp(bg, fg, 0.35) ?? bg],
        ),
      ),
      child: Center(
        child: Icon(
          Icons.auto_awesome,
          color: fg.withValues(alpha: 0.5),
          size: 56,
        ),
      ),
    );
  }
}
