import 'dart:convert';
import '../../../core/theme/app_colors.dart';
import 'dart:ui' show ImageFilter;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/font_size_provider.dart';
import '../../../core/network/api_client.dart';
import '../../../core/widgets/aurora_badge.dart';
import '../../../core/widgets/founding_badge.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../../shared/utils/topic_badge.dart';
import '../../../shared/widgets/pro_badge.dart';
import '../../../shared/widgets/mention_input/mention_popup.dart';
import '../../../shared/widgets/mention_input/mention_query.dart';
import '../../../shared/widgets/tutorial_block_renderer.dart';
import '../../auth/auth_service.dart';
import '../../messages/utils/message_avatar.dart' show messageTimeAgo;
import '../providers/article_provider.dart';
import '../widgets/article_actions.dart';
import '../widgets/article_body_view.dart';

const _primary = AppColors.primary;

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
  // 会员档位——后端评论接口目前还没在 SELECT 里带 membership，这里先把
  // 解析+渲染逻辑接好（null 时 ProBadge 自动隐藏），字段一上线自动生效
  final String? membership;

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
    this.membership,
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
      membership: j['membership'] as String?,
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
  // 文章数据统一走 articleProvider（跟 HD 中间面板共用同一份，见 2a-1）。这里
  // 只留几个便捷 getter 供 chrome（沉浸头/作者卡/评论/关注/阅读时长）读；加载、
  // 目录、点赞/收藏、数据集注入全在 provider / ArticleBodyView 里，screen 不再重复
  Map<String, dynamic>? get _tutorial =>
      ref.read(articleProvider(widget.tutorialId)).tutorial;
  List<dynamic> get _blocks =>
      ref.read(articleProvider(widget.tutorialId)).blocks;
  // 正文体控制器——scroll-spy 的 activeHeading + jumpToHeading + 数据集注入态
  final _bodyController = ArticleBodyController();
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

  // 阅读进度 + 沉浸式 Header 折叠进度
  final ScrollController _scrollCtrl = ScrollController();
  final ValueNotifier<double> _progress = ValueNotifier(0);
  // 折叠进度 t：1=完全展开（封面+大标题铺满）、0=完全塌缩（48 slim 条+小标题）。
  // 由 _onScroll 按滚动量算，驱动大标题渐隐/小标题渐显/图标白↔主题色插值
  final ValueNotifier<double> _headerT = ValueNotifier(1);

  // 阅读停留时长上报（为推荐算法准备数据）：进页记时刻，离开(dispose)算秒数、
  // 超过 5 秒才上报（过滤误触/秒退）。api client 在 initState 捕获，dispose 里
  // 不再 ref.read（那时 ref 可能已失效）
  final DateTime _enterTime = DateTime.now();
  late final ApiClient _apiClient;

  // 塌缩后的 slim 条高度（不含底部 2px 进度条）
  static const double _collapsedHeaderH = 48;

  // 沉浸式 Header 展开高度：有封面更高（放视差封面+标题），无封面矮一点（话题
  // 渐变+标题）。_onScroll 和 build 都要读它，抽成 getter
  double get _headerExpandedH {
    final cover = _tutorial?['cover_image'] as String?;
    return (cover != null && cover.isNotEmpty) ? 240 : 150;
  }

  @override
  void initState() {
    super.initState();
    _apiClient = ref.read(apiClientProvider);
    _scrollCtrl.addListener(_onScroll);
    // 文章数据由 articleProvider 自动加载（首帧 watch 触发），不再 _load()
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
    // 折叠进度：顶栏从展开塌到 slim 条要消耗 (expanded - collapsed) 像素滚动，
    // 按已滚过的比例算 t（1→0）
    final range = _headerExpandedH - _collapsedHeaderH;
    final collapse = range > 0
        ? (_scrollCtrl.offset / range).clamp(0.0, 1.0)
        : 1.0;
    final tVal = 1.0 - collapse;
    if ((tVal - _headerT.value).abs() > 0.001) _headerT.value = tVal;
    // scroll-spy（heading 高亮）现在由 ArticleBodyView 内部按同一个 scrollCtrl 算
  }

  @override
  void dispose() {
    // 停留时长上报——超过 5 秒才发（过滤误触）。fire-and-forget：不 await、
    // 吞掉任何错误（后端 /view 端点若还没上线，404 也不影响退出）
    final duration = DateTime.now().difference(_enterTime).inSeconds;
    if (duration > 5) {
      _apiClient
          .post(
            '/auth/tutorials/${widget.tutorialId}/view',
            data: {'duration': duration},
          )
          .then((_) {}, onError: (_) {});
    }
    _scrollCtrl.dispose();
    _progress.dispose();
    _headerT.dispose();
    _bodyController.dispose();
    _commentCtrl.dispose();
    _commentFocusNode.dispose();
    super.dispose();
  }

  // 目录 Bottom Sheet：从底部滑出，H1 顶格 / H2 缩进一层 / H3 缩进两层（按
  // level-1），当前所在标题高亮紫色，点击跳转并自动关闭
  void _showTocSheet() {
    final toc = ref.read(articleProvider(widget.tutorialId)).toc;
    if (toc.isEmpty) return;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final isDark = Theme.of(ctx).brightness == Brightness.dark;
        final ink = isDark ? Colors.white : const Color(0xFF1A1A1A);
        final muted = isDark ? Colors.white54 : const Color(0xFF999999);
        return Container(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(ctx).size.height * 0.7,
          ),
          decoration: BoxDecoration(
            color: Theme.of(ctx).cardColor,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
          ),
          padding: const EdgeInsets.only(top: 10, bottom: 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey[400],
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 12, 8),
                child: Row(
                  children: [
                    Text(
                      '目录',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: ink,
                      ),
                    ),
                    const Spacer(),
                    GestureDetector(
                      onTap: () => Navigator.pop(ctx),
                      behavior: HitTestBehavior.opaque,
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        child: Icon(Icons.close, size: 20, color: muted),
                      ),
                    ),
                  ],
                ),
              ),
              Flexible(
                child: ValueListenableBuilder<int>(
                  valueListenable: _bodyController.activeHeadingIndex,
                  builder: (context, active, _) => ListView.builder(
                    padding: const EdgeInsets.only(bottom: 8),
                    itemCount: toc.length,
                    itemBuilder: (context, k) =>
                        _tocRow(ctx, toc[k], k, k == active, ink, muted),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _tocRow(
    BuildContext sheetCtx,
    Map<String, dynamic> item,
    int tocIndex,
    bool isActive,
    Color ink,
    Color muted,
  ) {
    final level = (item['level'] as num).toInt();
    final indent = ((level - 1).clamp(0, 3)) * 16.0;
    return InkWell(
      onTap: () {
        Navigator.pop(sheetCtx);
        _bodyController.jumpToHeading(tocIndex);
      },
      child: Container(
        color: isActive ? _primary.withValues(alpha: 0.10) : Colors.transparent,
        padding: EdgeInsets.fromLTRB(20 + indent, 13, 16, 13),
        child: Row(
          children: [
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isActive
                    ? _primary
                    : (level <= 2
                          ? const Color(0xFF9AA0AE)
                          : const Color(0xFFCBD0DA)),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                item['text'] as String,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: level <= 2 ? 15 : 14,
                  fontWeight: isActive
                      ? FontWeight.w600
                      : (level <= 2 ? FontWeight.w500 : FontWeight.w400),
                  color: isActive ? _primary : ink,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Text('H$level', style: TextStyle(fontSize: 11, color: muted)),
          ],
        ),
      ),
    );
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

  // 关注状态——原来在 _load 尾部拉；现在文章数据由 articleProvider 加载，
  // build 里 ref.listen 在 tutorial 首次到手时调这个单独拉一次。数据集静默注入
  // 已迁进 ArticleBodyView，这里不再管
  Future<void> _maybeLoadFollowStatus(Map<String, dynamic> t) async {
    final authorId = t['user_id'] as String?;
    final currentUserId = ref.read(currentUserProvider)?.id;
    if (authorId != null && authorId.isNotEmpty && authorId != currentUserId) {
      final followRes = await ref
          .read(apiClientProvider)
          .get('/auth/users/$authorId/follow-status');
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
    // 点赞/收藏状态与乐观更新都在 articleProvider.notifier 里（跟 HD 共用一套）；
    // 失败返回 false，这里保持原来的错误提示
    final ok = await ref
        .read(articleProvider(widget.tutorialId).notifier)
        .toggleSave();
    if (!ok && mounted) {
      final l10n = AppLocalizations.of(context)!;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.actionFailedWithReason('收藏失败'))),
      );
    }
  }

  // 作者是否允许转载——后端 allow_repost（int 0/1，默认 1）。关闭时详情页
  // 隐藏「导出 PDF」和「分享」入口。拿不到数据/字段缺失时默认 true：安全
  // 降级，宁可照常显示也不误伤正常文章
  bool get _allowRepost {
    final v = _tutorial?['allow_repost'];
    if (v == null) return true;
    if (v is bool) return v;
    if (v is num) return v != 0;
    final s = v.toString().toLowerCase();
    return s != '0' && s != 'false';
  }

  // 顶部/底部两处"分享"图标之前都是占位 toast，现在都指向同一个真实的
  // 分享 Sheet
  void _showShare() {
    final tutorial = _tutorial;
    if (tutorial == null) return;
    showArticleShareSheet(context, tutorial);
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
    openArticleExportSheet(context, ref, tutorial, _blocks);
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
    final ok = await ref
        .read(articleProvider(widget.tutorialId).notifier)
        .toggleLike();
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            AppLocalizations.of(context)!.actionFailedWithReason('点赞失败'),
          ),
        ),
      );
    }
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
                      if (c.membership == 'pro' ||
                          c.membership == 'pro_max') ...[
                        const SizedBox(width: 4),
                        ProBadge(membership: c.membership),
                      ],
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
    final state = ref.watch(articleProvider(widget.tutorialId));
    // 文章首次到手时拉一次关注状态（原来在 _load 尾部）
    ref.listen<ArticleState>(articleProvider(widget.tutorialId), (prev, next) {
      if ((prev == null || prev.tutorial == null) && next.tutorial != null) {
        _maybeLoadFollowStatus(next.tutorial!);
      }
    });

    if (state.loading) {
      final isDark = Theme.of(context).brightness == Brightness.dark;
      return Scaffold(
        // 加载态背景也统一成首页米白 #FAFAF8（浅色），不再是默认的偏冷灰白
        backgroundColor: isDark
            ? Theme.of(context).scaffoldBackgroundColor
            : const Color(0xFFFAFAF8),
        body: const Center(child: CircularProgressIndicator(color: _primary)),
      );
    }

    if (state.tutorial == null) {
      final l10n = AppLocalizations.of(context)!;
      return Scaffold(
        appBar: AppBar(title: Text(l10n.tutorial)),
        body: Center(child: Text(l10n.tutorialNotFound)),
      );
    }

    final l10n = AppLocalizations.of(context)!;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    // 浅色统一首页米白 #FAFAF8（不再偏冷 #F7F7FB）；顶栏/正文/底部操作栏
    // 都用它，一整块连贯。深色不变
    // 阅读页深色底单独用更沉的 #0E1015（数字出版物观感），比全局 #0A0A0F 略提
    // 一点、跟毛玻璃底栏呼应；只这一页覆写，其余页仍是全局深色底
    final bg = isDark ? const Color(0xFF0E1015) : const Color(0xFFFAFAF8);
    final t = state.tutorial!;
    final title = t['title'] as String? ?? '';
    final username = t['username'] as String? ?? '';
    final avatar = t['avatar'] as String?;
    final authorIsFoundingCreator =
        t['is_founding_creator'] == true || t['is_founding_creator'] == 1;
    final authorIsAuroraCreator =
        t['is_aurora_creator'] == true || t['is_aurora_creator'] == 1;
    // 点赞/收藏数走 provider 的实时字段（toggle 后即时反映），不读 map 里的旧值
    final likes = state.likes;
    final saveCount = state.saveCount;
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
    final toc = state.toc;

    return Scaffold(
      backgroundColor: bg,
      // 右下角浮动目录入口已删除——顶栏已有目录图标（同一个 Sheet），
      // 底部再浮一个是冗余，还会挡住正文/分享按钮
      // 正文体统一走 ArticleBodyView（跟 HD 中间面板共用）：它负责渲染 blocks +
      // 公式编号 + heading keys + scroll-spy + 数据集注入，并用我们传进去的
      // _scrollCtrl（沉浸头/进度条也挂它）+ _bodyController（目录联动）。
      // 沉浸式 Header/封面/标题/作者行作 leadingSlivers，专栏卡/标签/作者卡/
      // 评论预览作 trailingSlivers，正文块由 ArticleBodyView 夹在中间注入
      body: ArticleBodyView(
        tutorialId: widget.tutorialId,
        scrollController: _scrollCtrl,
        controller: _bodyController,
        leadingSlivers: [
          // 沉浸式 Header：展开态铺满视差封面（无封面走话题渐变）+ 下半 60%
          // 黑色遮罩 + 大标题白字；往上滚 t:1→0，大标题渐隐、封面渐隐塌成 48
          // slim 条、slim 小标题渐显接管，返回/操作图标白↔主题色插值。折叠进度
          // t 由 _onScroll 按滚动量算，同一个 t 同时驱动 flexibleSpace 和图标色
          ValueListenableBuilder<double>(
            valueListenable: _headerT,
            builder: (context, t, _) {
              final hasCover = coverImage != null && coverImage.isNotEmpty;
              final barInk = Theme.of(context).textTheme.bodyLarge?.color;
              // 展开时叠在封面上要白、塌缩后在页面背景上要主题文字色
              final iconColor = Color.lerp(barInk, Colors.white, t)!;
              return SliverAppBar(
                expandedHeight: _headerExpandedH,
                collapsedHeight: _collapsedHeaderH,
                toolbarHeight: _collapsedHeaderH,
                pinned: true,
                elevation: 0,
                scrolledUnderElevation: 0,
                backgroundColor: bg,
                surfaceTintColor: Colors.transparent,
                foregroundColor: iconColor,
                titleSpacing: 0,
                centerTitle: false,
                leading: IconButton(
                  icon: Icon(Icons.arrow_back_ios, size: 18, color: iconColor),
                  onPressed: () => context.pop(),
                ),
                // 塌缩时（1-t→1）淡入接管标题
                title: Opacity(
                  opacity: (1 - t).clamp(0.0, 1.0),
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: barInk,
                    ),
                  ),
                ),
                actions: [
                  if (toc.isNotEmpty)
                    IconButton(
                      icon: Icon(Icons.list, color: iconColor),
                      tooltip: '目录',
                      onPressed: _showTocSheet,
                    ),
                  IconButton(
                    icon: Icon(Icons.format_size, color: iconColor),
                    onPressed: _showFontSheet,
                  ),
                  if (_allowRepost)
                    IconButton(
                      icon: Icon(
                        Icons.picture_as_pdf_outlined,
                        color: iconColor,
                      ),
                      tooltip: '导出 PDF',
                      onPressed: _openExportSheet,
                    ),
                ],
                flexibleSpace: FlexibleSpaceBar(
                  collapseMode: CollapseMode.parallax,
                  background: Opacity(
                    // 整个封面区随折叠渐隐，塌到 0 时露出 slim 条的纯 bg
                    opacity: t.clamp(0.0, 1.0),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        // 封面纯装饰排除出语义树——避免图片异步加载 relayout 跟
                        // 转场抢语义树更新炸 !semantics.parentDataDirty 断言
                        ExcludeSemantics(
                          child: hasCover
                              ? CachedNetworkImage(
                                  imageUrl: coverImage,
                                  fit: BoxFit.cover,
                                  errorWidget: (context, url, error) =>
                                      _CoverGradient(rule: topicRule),
                                )
                              : _CoverGradient(rule: topicRule),
                        ),
                        // 下半 60% 渐变到 black87——保证白标题在浅色封面（白底
                        // 数学图）上也读得清，代价是浅色封面下半会被压暗一截
                        const DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment(0, -0.2),
                              end: Alignment.bottomCenter,
                              colors: [Colors.transparent, Color(0xDD000000)],
                            ),
                          ),
                        ),
                        // 大标题（白），左下
                        Positioned(
                          left: 16,
                          right: 16,
                          bottom: 16,
                          child: Text(
                            title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                              height: 1.3,
                              letterSpacing: -0.2,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                // 阅读进度条：透明 track，只有往下滚才见紫色进度
                bottom: PreferredSize(
                  preferredSize: const Size.fromHeight(2),
                  child: ValueListenableBuilder<double>(
                    valueListenable: _progress,
                    builder: (context, v, _) => LinearProgressIndicator(
                      value: v,
                      minHeight: 2,
                      backgroundColor: Colors.transparent,
                      valueColor: const AlwaysStoppedAnimation(_primary),
                    ),
                  ),
                ),
              );
            },
          ),
          // 数据集加载提示条——静默注入内核期间显示，完成后消失。注入态现在由
          // ArticleBodyView 写进 _bodyController.datasetLoading
          SliverToBoxAdapter(
            child: ValueListenableBuilder<bool>(
              valueListenable: _bodyController.datasetLoading,
              builder: (context, datasetLoading, _) => datasetLoading
                  ? Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      color: isDark
                          ? const Color(0xFF0EA5E9).withValues(alpha: 0.10)
                          : const Color(0xFFF0F9FF),
                      child: Row(
                        children: [
                          const SizedBox(
                            width: 12,
                            height: 12,
                            child: CircularProgressIndicator(
                              strokeWidth: 1.6,
                              valueColor: AlwaysStoppedAnimation(
                                Color(0xFF0EA5E9),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            '本文包含数据集，正在加载…',
                            style: TextStyle(
                              fontSize: 12,
                              color: isDark
                                  ? const Color(0xFF7DD3FC)
                                  : const Color(0xFF0369A1),
                            ),
                          ),
                        ],
                      ),
                    )
                  : const SizedBox.shrink(),
            ),
          ),
          // 封面区：16:9 封面图 + 底部渐变遮罩 + 标签浮层
          // 封面/大标题已上移进沉浸式 Header（flexibleSpace），这里不再重复渲染
          // 独立封面块；正文首行改为承载从封面迁下来的 tags/series，标题不重复
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // tags/series 从封面迁到正文首行——正文底色上不用白字，改用
                  // 品牌紫 series pill + 浅紫 tag chip
                  if ((seriesTag != null && seriesTag.isNotEmpty) ||
                      tags.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          if (seriesTag != null && seriesTag.isNotEmpty)
                            Container(
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
                          ...tags
                              .take(2)
                              .map(
                                (tg) => Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: isDark
                                        ? _primary.withValues(alpha: 0.16)
                                        : AppColors.primaryLight,
                                    borderRadius: BorderRadius.circular(99),
                                  ),
                                  child: Text(
                                    tg,
                                    style: const TextStyle(
                                      fontSize: 11,
                                      color: _primary,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ),
                              ),
                        ],
                      ),
                    ),
                  if (subtitle != null && subtitle.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Text(
                        subtitle,
                        style: const TextStyle(fontSize: 12, color: _primary),
                      ),
                    ),
                  if (summary != null && summary.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    // 摘要跟卡片/预览抽屉一样走 inlineLatexText，$...$ 行内
                    // 公式才能渲染，不再显示原始源码
                    inlineLatexText(
                      summary,
                      TextStyle(
                        fontSize: 14,
                        // 次级文字：深色页用 #A1A1A1（比 #888 更亮、在 #0E1015 上
                        // 更清晰），浅色沿用 #888888
                        color: isDark
                            ? const Color(0xFFA1A1A1)
                            : const Color(0xFF888888),
                        height: 1.65,
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  // 作者行上方原来是满宽的 Divider，颜色浅但满宽+1px描边
                  // 在这么淡的米白页面上还是显得很"重"。改成居中的短横线，
                  // 更轻、也不是一整条"完整"的分割线
                  Center(
                    child: Container(
                      width: 32,
                      height: 1,
                      color: isDark
                          ? Colors.white.withValues(alpha: 0.08)
                          : const Color(0xFFE5E5E5),
                    ),
                  ),
                  const SizedBox(height: 16),
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
          // ── leadingSlivers 到此结束；正文 blocks 由 ArticleBodyView 注入 ──
        ],
        trailingSlivers: [
          SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
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
                                : AppColors.primaryLight,
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
      bottomNavigationBar: ClipRect(
        // 毛玻璃底栏：半透明底色 + 20px 高斯模糊，正文从底栏后隐约透出，
        // 数字出版物观感（原来是实心背景）
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: Container(
            decoration: BoxDecoration(
              // 底栏跟页面背景对齐：浅色用米白 #FAFAF8（原来是纯白，跟米白页面
              // 之间有一条明显的色差缝），深色用 #0E1015，都取自同一个 bg
              color: bg.withValues(alpha: 0.85),
              border: Border(
                top: BorderSide(
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.08)
                      : Colors.black.withValues(alpha: 0.06),
                  width: 0.5,
                ),
              ),
            ),
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                child: Row(
                  children: [
                    _bottomAction(
                      icon: state.liked
                          ? Icons.favorite
                          : Icons.favorite_border,
                      color: state.liked
                          ? const Color(0xFFEF4444)
                          : Colors.grey[400]!,
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
                      icon: state.saved
                          ? Icons.bookmark
                          : Icons.bookmark_border,
                      color: state.saved ? _primary : Colors.grey[400]!,
                      label: '$saveCount',
                      onTap: _toggleSave,
                    ),
                    const Spacer(),
                    // 分享——大小/形状/填色全部对齐顶部「关注」按钮：实心品牌紫
                    // #6366F1、padding h14/v6、圆角 8、字号 12/w600，无渐变无投影，
                    // 只多一个分享图标做身份区分。作者关闭转载时整颗按钮隐藏
                    // （Spacer 保留，其余按钮仍靠左）
                    if (_allowRepost)
                      GestureDetector(
                        onTap: _showShare,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: _primary,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.ios_share_rounded,
                                size: 14,
                                color: Colors.white,
                              ),
                              SizedBox(width: 5),
                              Text(
                                '分享',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
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
    // 去掉卡片边框/底色，改成跟正文头部作者行完全同款：上方一条居中的
    // 32px 短横线（不是满宽分割线，在米白页面上更轻），下面直接是作者行
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 16),
        Center(
          child: Container(
            width: 32,
            height: 1,
            color: isDark
                ? Colors.white.withValues(alpha: 0.08)
                : const Color(0xFFE5E5E5),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(16),
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
        ),
      ],
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
                    : AppColors.primaryLight)
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
                    : AppColors.primaryLight,
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
