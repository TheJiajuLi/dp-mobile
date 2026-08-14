import 'dart:async';
import '../../../core/theme/app_colors.dart';
import 'dart:convert';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:dio/dio.dart';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:flutter_math_fork/flutter_math.dart';

import '../../../shared/utils/latex_utils.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/network/api_client.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../../shared/models/tutorial_model.dart';
import '../../../shared/utils/online_status.dart';
import '../../../shared/utils/pro_access.dart';
import '../../../shared/widgets/app_toast.dart';
import '../../../shared/widgets/confirm_dialog.dart';
import '../../../shared/widgets/formula_error.dart';
import '../../../shared/widgets/question_share_card.dart';
import '../../auth/auth_service.dart';
import '../models/conversation_model.dart';
import '../models/message_model.dart';
import '../providers/messages_provider.dart';

const _primary = AppColors.primary;

// 消息列表按天分组后拼出来的时间线——日期分隔条跟消息本体混在同一个
// 列表里渲染，用 sealed class 区分这一项到底是分隔条还是消息，比
// itemBuilder 里临时判断"这条是不是新的一天"更清楚
sealed class _TimelineItem {
  const _TimelineItem();
}

class _DateSeparator extends _TimelineItem {
  final DateTime day;
  const _DateSeparator(this.day);
}

class _MessageItem extends _TimelineItem {
  final ChatMessage message;
  const _MessageItem(this.message);
}

String _initial(String? name) {
  if (name == null || name.isEmpty) return '?';
  return name.substring(0, 1).toUpperCase();
}

// 跟全项目其它头像渲染的地方（user_profile_screen/edit_profile_screen/
// home_screen 等）保持同一套判断：data:image 开头是旧的 base64 头像，
// 否则是 COS 的图片 URL，用 CachedNetworkImageProvider 而不是 NetworkImage
// 才能吃到缓存
Widget _buildAvatar(
  String? avatar,
  String username,
  Color bgColor, {
  double radius = 16,
}) {
  if (avatar != null && avatar.isNotEmpty) {
    if (avatar.startsWith('data:image')) {
      try {
        return CircleAvatar(
          radius: radius,
          backgroundImage: MemoryImage(base64Decode(avatar.split(',').last)),
        );
      } catch (_) {
        // 解码失败落到下面的首字母占位
      }
    } else {
      return CircleAvatar(
        radius: radius,
        backgroundImage: CachedNetworkImageProvider(avatar),
      );
    }
  }
  return CircleAvatar(
    radius: radius,
    backgroundColor: bgColor,
    child: Text(
      _initial(username),
      style: TextStyle(
        color: Colors.white,
        fontSize: radius * 0.75,
        fontWeight: FontWeight.w700,
      ),
    ),
  );
}

class ChatScreen extends ConsumerStatefulWidget {
  final String conversationId;
  final Conversation? conversation;

  const ChatScreen({
    super.key,
    required this.conversationId,
    this.conversation,
  });

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final _ctrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  List<ChatMessage> _messages = [];
  bool _loading = true;
  bool _sendingImage = false;
  // 2026-07-06 起后端真的加上了陌生人消息限制（互相关注视为好友，完全
  // 不受限；非好友：对方从没回复过之前，我的第一条只能是文字，发过之后
  // 要等对方回复才能再发），不再是纯客户端猜的启发式。_isMutualFriend
  // 只在进入聊天时查一次 /auth/friends（不用每 5 秒轮询都查一遍，好友
  // 关系变化不频繁），后面两个每次收完新消息都本地重算，不用再打接口
  bool _isMutualFriend = false;
  // _loadMessages() 拉到消息后会立刻调一次 _updateStrangerFlags()，但这
  // 时 _checkStrangerStatus() 那个 /auth/friends 请求通常还没返回——
  // _isMutualFriend 还是初始值 false，会把互相关注的好友也误判成"还不是
  // 好友"，闪一下"你们还不是好友"提示再自己消失。加这个标记，好友关系
  // 没查完之前 _updateStrangerFlags() 先不算，避免这个误判的闪烁
  bool _friendStatusChecked = false;
  bool _isStrangerFirstMessage = false;
  bool _strangerLimitReached = false;
  Timer? _pollTimer;
  // 对方在线状态字符串（online/recently/offline）——顶栏状态行用它。
  // 后端 /auth/users/online-status 返回的就是状态字符串，不是 timestamp
  String? _otherUserStatus;
  Timer? _statusTimer;

  // 点对方头像跳去 ta 主页时踩过一次 `!semantics.parentDataDirty` 断言
  // 崩溃——根因是这个 5 秒一次的轮询定时器在页面被 push 出去的新路由盖住、
  // 正在做转场动画期间照样触发，setState 重建消息列表（ListView.builder）
  // 跟 Navigator 转场动画同一帧抢语义树更新，不是用户资料页那边
  // Sliver/GridView 嵌套或 GlobalKey 的问题（挨个查过，那些都没问题）。
  // mounted 只能判断"还在树上"，判断不了"当前是不是被盖住"，页面被 push
  // 覆盖后依然是 mounted——真正要挡的是这种情况，所以额外查
  // ModalRoute.isCurrent
  bool get _isRouteActive =>
      mounted && (ModalRoute.of(context)?.isCurrent ?? true);

  @override
  void initState() {
    super.initState();
    _loadMessages().then((_) => _checkStrangerStatus());
    // 微信式已读：进入聊天页就把这个会话的未读清零，不等下一次轮询——
    // 后端已经会在下面 _loadMessages() 那个 GET messages 接口里把这个
    // 会话标成已读（实测确认过），这里不需要额外调 API，只是不想让本地
    // 消息 tab 的角标在 15 秒轮询间隔里还显示旧的未读数。
    // 必须放进 addPostFrameCallback——直接在 initState 里同步调用会在
    // 第一帧构建过程中修改 conversationsProvider 的状态，Riverpod 判定
    // 为"在 widget 树构建期间修改 provider"直接抛异常（实测确认过这个
    // 崩溃），要等这一帧构建完再改
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _clearUnread();
    });
    // 每 5 秒拉新消息
    _pollTimer = Timer.periodic(
      const Duration(seconds: 5),
      (_) => _loadMessages(),
    );
    // 在线状态：先用会话带来的 last_seen 兜底一个初始状态，再每 60 秒
    // 用 /auth/users/online-status 的真实状态字符串覆盖
    _otherUserStatus = _statusFromLastSeen(
      widget.conversation?.otherLastSeenAt,
    );
    _refreshOtherUserStatus();
    _statusTimer = Timer.periodic(
      const Duration(seconds: 60),
      (_) => _refreshOtherUserStatus(),
    );
  }

  // 后端 /auth/users/online-status 直接返回 { id: "online"/"recently"/"offline" }
  Future<void> _refreshOtherUserStatus() async {
    final otherId = widget.conversation?.otherUserId ?? '';
    if (otherId.isEmpty) return;
    final res = await ref
        .read(apiClientProvider)
        .get('/auth/users/online-status', queryParameters: {'ids': otherId});
    if (!res.success || res.data is! Map || !mounted) return;
    setState(() {
      _otherUserStatus = (res.data as Map)[otherId] as String? ?? 'offline';
    });
  }

  // 首屏兜底：把会话带来的 last_seen_at 映射成同一套状态字符串
  String _statusFromLastSeen(int? lastSeenAt) {
    switch (OnlineStatusHelper.fromLastSeen(lastSeenAt)) {
      case OnlineStatus.online:
        return 'online';
      case OnlineStatus.recently:
        return 'recently';
      case OnlineStatus.offline:
        return 'offline';
    }
  }

  String _statusLabel(String? status) {
    switch (status) {
      case 'online':
        return '在线';
      case 'recently':
        return '最近活跃';
      default:
        return '';
    }
  }

  Color _statusColor(String? status) {
    switch (status) {
      case 'online':
        return const Color(0xFF22C55E);
      case 'recently':
        return const Color(0xFFF59E0B);
      default:
        return Colors.transparent;
    }
  }

  void _clearUnread() {
    final convs = ref.read(conversationsProvider);
    final idx = convs.indexWhere((c) => c.id == widget.conversationId);
    if (idx != -1 && convs[idx].unreadCount > 0) {
      ref
          .read(conversationsProvider.notifier)
          .clearUnread(widget.conversationId);
    }
  }

  Future<void> _loadMessages() async {
    final res = await ref
        .read(apiClientProvider)
        .get('/auth/conversations/${widget.conversationId}/messages');
    if (!res.success || res.data == null) {
      if (_isRouteActive) setState(() => _loading = false);
      return;
    }
    try {
      final list = (res.data['messages'] as List)
          .map((j) => ChatMessage.fromJson(j as Map<String, dynamic>))
          .toList();
      // 5秒轮询期间这个页面完全可能已经被 push 出去的用户主页盖住了——
      // 这时候还去重建消息列表会跟盖上来那个路由的转场动画抢语义树更新，
      // 之前"点头像跳资料页"崩的 `!semantics.parentDataDirty` 断言就是
      // 这么来的。被盖住时就不更新，等这个路由重新变成当前路由（用户
      // 返回）下一次轮询自然会刷新
      if (!_isRouteActive) return;
      setState(() {
        _messages = list;
        _loading = false;
      });
      _updateStrangerFlags();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrollCtrl.hasClients) {
          _scrollCtrl.animateTo(
            _scrollCtrl.position.maxScrollExtent,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
          );
        }
      });
    } catch (_) {
      if (_isRouteActive) setState(() => _loading = false);
    }
  }

  // 互相关注视为好友——跟后端 POST /auth/messages 判断限制用的同一个
  // 定义（f1 join f2 双向 follows）。/auth/users/:id/follow-status 只能
  // 查"我是否关注了对方"这一个方向，查不出"互相"，所以用 /auth/friends
  // 这份好友名单本身来判断在不在里面，这才是跟后端口径一致的"互关"来源
  Future<void> _checkStrangerStatus() async {
    final otherId = widget.conversation?.otherUserId ?? '';
    if (otherId.isEmpty) return;

    final res = await ref.read(apiClientProvider).get('/auth/friends');
    if (!_isRouteActive) return;
    final friends = (res.data?['friends'] as List?) ?? [];
    _isMutualFriend = friends.any(
      (f) => (f as Map)['id']?.toString() == otherId,
    );
    _friendStatusChecked = true;
    _updateStrangerFlags();
  }

  // 纯本地计算：_messages 按时间正序排列（最新的在最后），"对方有没有
  // 回复过""我有没有发过"只需要看本地已有数据就能判断，不需要额外打
  // 接口——每次收完新消息（5秒轮询一次）都会重算一遍
  void _updateStrangerFlags() {
    // 好友关系还没查完，不知道对方是不是互关好友，先不算——避免用
    // 默认值 false 误判成陌生人，闪一下提示再消失
    if (!_friendStatusChecked) return;
    if (_isMutualFriend) {
      setState(() {
        _isStrangerFirstMessage = false;
        _strangerLimitReached = false;
      });
      return;
    }

    final otherId = widget.conversation?.otherUserId ?? '';
    final currentUserId = ref.read(currentUserProvider)?.id ?? '';
    final otherReplied = _messages.any((m) => m.senderId == otherId);
    final iSent = _messages.any((m) => m.senderId == currentUserId);

    setState(() {
      _isStrangerFirstMessage = !otherReplied && !iSent;
      _strangerLimitReached = !otherReplied && iSent;
    });
  }

  bool get _hasStrangerHint => _strangerLimitReached || _isStrangerFirstMessage;

  // 陌生人提示不放在输入框上方常驻一条横栏，改成跟网易云一样，当成
  // "第一条消息"的占位插进消息列表顶部——居中的小胶囊，不是通栏，视觉上
  // 更像一条系统提示而不是一直杵在那里的警告条
  Widget _buildStrangerHint() {
    final isLimit = _strangerLimitReached;
    final color = isLimit ? const Color(0xFFD97706) : Colors.grey;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: isLimit ? const Color(0xFFFFF7E6) : const Color(0xFFF5F5F2),
            borderRadius: BorderRadius.circular(99),
          ),
          child: Text(
            isLimit ? '对方尚未回复，回复后你们就可以自由聊天' : '你们还不是好友，可以先发一条文字消息',
            style: TextStyle(fontSize: 11, color: color),
          ),
        ),
      ),
    );
  }

  Future<void> _send({
    String? text,
    String type = 'text',
    Map<String, dynamic>? metadata,
  }) async {
    debugPrint('[Chat] _send调用');
    final content = text ?? _ctrl.text.trim();
    debugPrint('[Chat] content: "$content"');
    if (content.isEmpty) {
      debugPrint('[Chat] ❌ content为空');
      return;
    }

    final otherId = widget.conversation?.otherUserId ?? '';
    debugPrint('[Chat] conversationId: ${widget.conversationId}');
    debugPrint('[Chat] conversation: ${widget.conversation}');
    debugPrint('[Chat] otherId: "$otherId"');
    if (otherId.isEmpty) {
      debugPrint('[Chat] ❌ otherId为空，无法发送');
      return;
    }

    debugPrint('[Chat] 准备发送到 /auth/messages');
    _ctrl.clear();
    final res = await ref
        .read(apiClientProvider)
        .post(
          '/auth/messages',
          data: {
            'toUserId': otherId,
            'content': content,
            'type': type,
            if (metadata != null) 'metadata': metadata,
          },
        );
    if (!res.success) {
      if (!mounted) return;
      // 2026-07-06 起 ApiResponse.error 会把原始错误响应体透传进 data，
      // 不用再靠匹配 message 文案这种脆弱办法识别错误类型了
      final code = res.data?['code'];
      if (code == 'STRANGER_LIMIT') {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(res.message ?? '对方尚未回复，回复后你们就可以自由聊天'),
            backgroundColor: const Color(0xFFD97706),
          ),
        );
        setState(() {
          _isStrangerFirstMessage = false;
          _strangerLimitReached = true;
        });
        return;
      }
      if (code == 'TEXT_ONLY_LIMIT') {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('首次发送只能是文字消息'),
            backgroundColor: Color(0xFFD97706),
          ),
        );
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            AppLocalizations.of(
              context,
            )!.sendFailedWithReason('${res.message}'),
          ),
        ),
      );
      return;
    }
    await _loadMessages();
  }

  Future<void> _sendImage({ImageSource source = ImageSource.gallery}) async {
    if (_sendingImage) return;
    final picker = ImagePicker();
    final file = await picker.pickImage(
      source: source,
      maxWidth: 1920,
      maxHeight: 1920,
      imageQuality: 80,
    );
    if (file == null) return;

    final bytes = await file.readAsBytes();
    if (!mounted) return;

    setState(() => _sendingImage = true);
    try {
      final formData = FormData.fromMap({
        'file': MultipartFile.fromBytes(
          bytes,
          filename: 'img_${DateTime.now().millisecondsSinceEpoch}.jpg',
          contentType: DioMediaType('image', 'jpeg'),
        ),
      });

      // ApiClient.post 内部吞掉了 DioException，不会抛异常——失败与否要看
      // res.success，不能只靠 try/catch
      final l10n = AppLocalizations.of(context)!;
      final uploadRes = await ref
          .read(apiClientProvider)
          .post('/auth/files/upload', data: formData);
      if (!uploadRes.success) {
        throw Exception(uploadRes.message ?? l10n.uploadFailedRetry);
      }

      final imageUrl = (uploadRes.data as Map)['url'] as String?;
      if (imageUrl == null) {
        throw Exception(l10n.uploadFailedRetry);
      }

      await _send(text: imageUrl, type: 'image');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              AppLocalizations.of(context)!.sendImageFailedWithReason(
                e.toString().replaceAll('Exception: ', ''),
              ),
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _sendingImage = false);
    }
  }

  // 通用文件——复用图片走的同一个 /auth/files/upload（notebook 编辑页导入
  // 数据文件也是这个接口），只是这次上传结果的用途是发一条 type='file'
  // 的消息，metadata 里存文件名/字节数给气泡展示用
  Future<void> _sendFile() async {
    // 防重复发送：guard 置位提前到选择器之前（原来在选择器返回后才置位，
    // 两次快速触发会重复发）。取消/异常在 finally 复位
    if (_sendingImage) return;
    setState(() => _sendingImage = true);
    try {
      final result = await FilePicker.platform.pickFiles(withData: true);
      if (result == null || result.files.isEmpty) return;
      final picked = result.files.first;
      // withData 没填 bytes 就从路径兜底读
      var bytes = picked.bytes;
      if (bytes == null && picked.path != null) {
        bytes = await File(picked.path!).readAsBytes();
      }
      // 防 0B：空 Uint8List 也要拦，否则上传一个 0 字节坏文件
      if (bytes == null || bytes.isEmpty || !mounted) return;

      final l10n = AppLocalizations.of(context)!;
      final formData = FormData.fromMap({
        'file': MultipartFile.fromBytes(bytes, filename: picked.name),
      });
      final uploadRes = await ref
          .read(apiClientProvider)
          .post('/auth/files/upload', data: formData);
      if (!uploadRes.success) {
        throw Exception(uploadRes.message ?? l10n.uploadFailedRetry);
      }
      final fileUrl = (uploadRes.data as Map)['url'] as String?;
      if (fileUrl == null) throw Exception(l10n.uploadFailedRetry);

      await _send(
        text: fileUrl,
        type: 'file',
        metadata: {'filename': picked.name, 'size': bytes.length},
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              AppLocalizations.of(context)!.sendImageFailedWithReason(
                e.toString().replaceAll('Exception: ', ''),
              ),
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _sendingImage = false);
    }
  }

  // 分享教程——挑自己已发布的教程，接通 message_model.dart 注释里早就写了
  // 但从来没真正用过的 type='tutorial'。标题/封面都是这一条真实教程的
  // 数据，不是编的
  Future<void> _showTutorialPicker() async {
    final l10n = AppLocalizations.of(context)!;
    final currentUser = ref.read(currentUserProvider);
    if (currentUser == null) return;

    final res = await ref
        .read(apiClientProvider)
        .get(
          '/auth/tutorials',
          queryParameters: {
            'author': currentUser.username,
            'status': 'published',
          },
        );
    if (!mounted) return;
    final tutorials = (res.success && res.data != null)
        ? ((res.data['tutorials'] as List?) ?? [])
              .map((j) => TutorialModel.fromJson(j as Map<String, dynamic>))
              .where((t) => t.userId == currentUser.id)
              .toList()
        : <TutorialModel>[];

    if (tutorials.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l10n.noTutorialsPublished)));
      return;
    }

    if (!mounted) return;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(ctx).size.height * 0.6,
        ),
        decoration: BoxDecoration(
          color: Theme.of(ctx).cardColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                '文章',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
              ),
            ),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: tutorials.length,
                itemBuilder: (ctx, i) {
                  final t = tutorials[i];
                  return ListTile(
                    leading: t.coverImage?.isNotEmpty == true
                        ? ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: CachedNetworkImage(
                              imageUrl: t.coverImage!,
                              width: 44,
                              height: 44,
                              fit: BoxFit.cover,
                            ),
                          )
                        : Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              color: _primary.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Icon(
                              Icons.article_outlined,
                              color: _primary,
                            ),
                          ),
                    title: Text(
                      t.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    onTap: () {
                      Navigator.pop(ctx);
                      _send(
                        text: t.id,
                        type: 'tutorial',
                        metadata: {'title': t.title, 'cover': t.coverImage},
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showImagePreview(BuildContext context, String url) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => Scaffold(
          backgroundColor: Colors.black,
          appBar: AppBar(
            backgroundColor: Colors.black,
            foregroundColor: Colors.white,
            elevation: 0,
          ),
          body: Center(
            child: InteractiveViewer(child: CachedNetworkImage(imageUrl: url)),
          ),
        ),
      ),
    );
  }

  Future<void> _toggleMute(bool currentlyMuted) async {
    final res = await ref
        .read(apiClientProvider)
        .put(
          '/auth/conversations/${widget.conversationId}/mute',
          data: {'muted': !currentlyMuted},
        );
    if (!mounted) return;
    if (res.success) {
      ref
          .read(conversationsProvider.notifier)
          .setMuted(widget.conversationId, !currentlyMuted);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(res.message ?? (currentlyMuted ? '已关闭免打扰' : '已开启免打扰')),
        ),
      );
    } else {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('操作失败：${res.message}')));
    }
  }

  // 清空历史消息——DELETE /auth/conversations/:id/messages 是硬删除，双方
  // 视角都会清空，不是软删除/单向隐藏，删前必须二次确认
  Future<void> _confirmClearHistory() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('清空历史消息'),
        content: const Text('清空后，双方都将无法查看这段聊天记录，且无法恢复。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消', style: TextStyle(color: Colors.grey)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('清空', style: TextStyle(color: Color(0xFFDC2626))),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final res = await ref
        .read(apiClientProvider)
        .delete('/auth/conversations/${widget.conversationId}/messages');
    if (!mounted) return;
    if (res.success) {
      setState(() => _messages = []);
      ref
          .read(conversationsProvider.notifier)
          .clearLastMessage(widget.conversationId);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(res.message ?? '对话已清空')));
    } else {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('操作失败：${res.message}')));
    }
  }

  // 头顶"..."菜单——参考截图里这个位置紧挨着语音/视频通话按钮，但那两个
  // 按钮这次明确不加（没有实时通话能力）
  void _showChatMenu() {
    final l10n = AppLocalizations.of(context)!;
    final otherUsername = widget.conversation?.otherUsername ?? '';
    final convs = ref.read(conversationsProvider);
    final idx = convs.indexWhere((c) => c.id == widget.conversationId);
    final isMuted = idx != -1
        ? convs[idx].isMuted
        : (widget.conversation?.isMuted ?? false);
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: BoxDecoration(
          color: Theme.of(ctx).cardColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.person_outline),
              title: Text(l10n.viewProfileAction),
              onTap: () {
                Navigator.pop(ctx);
                // 用 otherUsername 不是 otherUserId——/users/:identifier
                // 这条路由期望的是 username/handle，传原始用户 id 进去，
                // 后端按 username 匹配不到人，页面直接显示"用户不存在"
                if (otherUsername.isNotEmpty) {
                  context.push('/users/$otherUsername');
                }
              },
            ),
            ListTile(
              leading: Icon(
                isMuted
                    ? Icons.notifications_off
                    : Icons.notifications_off_outlined,
              ),
              title: const Text('消息免打扰'),
              trailing: isMuted
                  ? const Icon(Icons.check, color: _primary, size: 18)
                  : null,
              onTap: () {
                Navigator.pop(ctx);
                _toggleMute(isMuted);
              },
            ),
            ListTile(
              leading: const Icon(
                Icons.delete_sweep_outlined,
                color: Color(0xFFDC2626),
              ),
              title: const Text(
                '清空聊天记录',
                style: TextStyle(color: Color(0xFFDC2626)),
              ),
              onTap: () {
                Navigator.pop(ctx);
                _confirmClearHistory();
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showAttachMenu() {
    final l10n = AppLocalizations.of(context)!;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: BoxDecoration(
          color: Theme.of(ctx).cardColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _attachBtn(Icons.image, l10n.attachImage, () {
                  Navigator.pop(ctx);
                  _sendImage();
                }),
                _attachBtn(Icons.camera_alt_outlined, l10n.attachCamera, () {
                  Navigator.pop(ctx);
                  _sendImage(source: ImageSource.camera);
                }),
                _attachBtn(
                  Icons.insert_drive_file_outlined,
                  l10n.attachFile,
                  () {
                    Navigator.pop(ctx);
                    // 发送文件（含音视频媒体）是 Pro 权益
                    if (!requirePro(context, ref, feature: '发送文件')) return;
                    _sendFile();
                  },
                ),
                _attachBtn(Icons.code, l10n.attachCode, () {
                  Navigator.pop(ctx);
                  // 发送代码片段是 Pro 权益
                  if (!requirePro(context, ref, feature: '发送代码')) return;
                  _showCodeInput();
                }),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _attachBtn(Icons.functions, l10n.attachFormula, () {
                  Navigator.pop(ctx);
                  // 发送 LaTeX 公式是 Pro 权益
                  if (!requirePro(context, ref, feature: '发送公式')) return;
                  _showLatexInput();
                }),
                _attachBtn(Icons.article_outlined, '文章', () {
                  Navigator.pop(ctx);
                  _showTutorialPicker();
                }),
                // 消息模板——参考截图有这个入口，但后端/前端都还没有"消息
                // 模板"这个概念，点了给"即将上线"反馈，不是编一套假模板
                _attachBtn(
                  Icons.dashboard_customize_outlined,
                  l10n.attachTemplate,
                  () {
                    Navigator.pop(ctx);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(l10n.comingSoonStayTuned)),
                    );
                  },
                ),
                _attachBtn(Icons.more_horiz, l10n.attachMore, () {
                  Navigator.pop(ctx);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(l10n.comingSoonStayTuned)),
                  );
                }),
              ],
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  static const _codeLanguages = ['Python', 'JavaScript', 'SQL', 'Text'];

  void _showCodeInput() {
    final l10n = AppLocalizations.of(context)!;
    final codeCtrl = TextEditingController();
    var selectedLanguage = _codeLanguages.first;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) => Container(
          decoration: BoxDecoration(
            color: Theme.of(ctx).cardColor,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          padding: EdgeInsets.fromLTRB(
            20,
            20,
            20,
            MediaQuery.of(ctx).viewInsets.bottom + 20,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l10n.sendCode,
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 6,
                children: _codeLanguages.map((lang) {
                  final selected = lang == selectedLanguage;
                  return ChoiceChip(
                    label: Text(lang, style: const TextStyle(fontSize: 12)),
                    selected: selected,
                    onSelected: (_) =>
                        setSheetState(() => selectedLanguage = lang),
                  );
                }).toList(),
              ),
              const SizedBox(height: 10),
              Container(
                decoration: BoxDecoration(
                  color: const Color(0xFF1C1C1E),
                  borderRadius: BorderRadius.circular(12),
                ),
                padding: const EdgeInsets.all(12),
                child: TextField(
                  controller: codeCtrl,
                  maxLines: 6,
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 13,
                    color: Colors.white,
                  ),
                  decoration: InputDecoration(
                    filled: false,
                    border: InputBorder.none,
                    hintText: l10n.codeInputHint,
                    hintStyle: const TextStyle(color: Colors.grey),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                height: 44,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _primary,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onPressed: () {
                    Navigator.pop(ctx);
                    _send(
                      text: codeCtrl.text.trim(),
                      type: 'code',
                      metadata: {'language': selectedLanguage},
                    );
                  },
                  child: Text(
                    l10n.send,
                    style: const TextStyle(color: Colors.white),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showLatexInput() {
    final l10n = AppLocalizations.of(context)!;
    final latexCtrl = TextEditingController();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: BoxDecoration(
          color: Theme.of(ctx).cardColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: EdgeInsets.fromLTRB(
          20,
          20,
          20,
          MediaQuery.of(ctx).viewInsets.bottom + 20,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.sendFormula,
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: latexCtrl,
              autofocus: true,
              decoration: InputDecoration(
                hintText: l10n.latexFormulaExample,
                filled: true,
                fillColor: Theme.of(ctx).inputDecorationTheme.fillColor,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              height: 44,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: _primary,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onPressed: () {
                  final latex = latexCtrl.text.trim();
                  // 之前这里不管输入框是不是空的都先 pop 再发，空输入时
                  // _send() 内部会因为 content.isEmpty 直接 return——弹窗
                  // 已经关了，但什么都没发出去，跟"点了没反应"一样
                  if (latex.isEmpty) return;
                  Navigator.pop(ctx);
                  // 用独立的 type='latex'，不是 type='code' + metadata。
                  // 实测两种后端都接受、都能正确存取，但依赖 metadata 里的
                  // language 字段才能认出这是公式，比直接用 type 多一层
                  // 容易失配的环节——type 字段是消息模型里保证一定有的
                  _send(text: latex, type: 'latex');
                },
                child: Text(
                  l10n.send,
                  style: const TextStyle(color: Colors.white),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _attachBtn(IconData icon, String label, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: AppColors.primaryLight,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: _primary, size: 24),
          ),
          const SizedBox(height: 6),
          Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _scrollCtrl.dispose();
    _pollTimer?.cancel();
    _statusTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final currentUserId = ref.watch(currentUserProvider)?.id ?? '';
    final otherName =
        widget.conversation?.otherUsername ?? l10n.defaultUserName;

    // 顶栏/消息区/输入栏全部统一到同一个米白背景——之前顶栏和输入栏用
    // cardColor（纯白），中间消息区用 scaffoldBackgroundColor（冷灰），
    // 三段拼出两条能看出来的接缝。深色模式保持原 scaffold 背景色
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark
        ? Theme.of(context).scaffoldBackgroundColor
        : const Color(0xFFFAFAF8);
    // 输入胶囊在米白栏上要浮出来，浅色下用纯白 + 细描边，不再跟背景糊在一起
    final capsuleFill = isDark
        ? Theme.of(context).inputDecorationTheme.fillColor
        : Colors.white;

    return Scaffold(
      backgroundColor: bg,
      // top/bottom 不在这层留白——顶栏和输入栏各自用 SafeArea 把自己的
      // 背景铺进状态栏/home indicator 那圈安全区，不然这里统一留白会露出
      // Scaffold 背景色，跟顶栏/输入栏刀切不连贯（跟 publish_screen.dart
      // 顶栏/底部工具栏是同一套处理）
      // 整块 body 包一层点击收键盘——顶栏/消息区/空白处点哪都能收，
      // 内部各按钮/输入框的手势 translucent 不拦
      body: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: () => FocusScope.of(context).unfocus(),
        child: SafeArea(
          top: false,
          bottom: false,
          child: Column(
            children: [
              // 顶部栏
              Container(
                color: bg,
                child: SafeArea(
                  bottom: false,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 10,
                    ),
                    child: Row(
                      children: [
                        IconButton(
                          icon: const Icon(Icons.arrow_back_ios, size: 18),
                          onPressed: () => context.pop(),
                        ),
                        _buildAvatar(
                          widget.conversation?.otherAvatar,
                          otherName,
                          _primary,
                          radius: 18,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                otherName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              // 只有 online/recently 才显示状态行；offline/未知不显示
                              if (_statusLabel(_otherUserStatus).isNotEmpty)
                                Text(
                                  _statusLabel(_otherUserStatus),
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: _statusColor(_otherUserStatus),
                                  ),
                                ),
                            ],
                          ),
                        ),
                        GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: _showChatMenu,
                          child: const Padding(
                            padding: EdgeInsets.all(4),
                            child: Icon(Icons.more_horiz, size: 22),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              // 消息列表——陌生人提示条不放在输入框上方（那样固定占一条横栏，
              // 每次进来都要看一眼），改成跟网易云一样，当成"第一条消息"的
              // 占位插在消息列表顶部，滚动上去才看得到，更不打扰。日期分隔条
              // 混在消息中间，先按天分组拼成一份 timeline 再渲染，不是每个
              // item 各自临时判断——分组结果每条消息只用算一次
              Expanded(
                // 点消息列表空白处收起键盘
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => FocusScope.of(context).unfocus(),
                  child: _loading
                      ? const Center(child: CircularProgressIndicator())
                      : Builder(
                          builder: (ctx) {
                            final timeline = _buildTimeline();
                            final hintOffset = _hasStrangerHint ? 1 : 0;
                            return ListView.builder(
                              controller: _scrollCtrl,
                              // 滚动消息时自动收起键盘（跟点空白处一致）
                              keyboardDismissBehavior:
                                  ScrollViewKeyboardDismissBehavior.onDrag,
                              padding: const EdgeInsets.all(12),
                              itemCount: timeline.length + hintOffset,
                              itemBuilder: (ctx, i) {
                                if (_hasStrangerHint && i == 0) {
                                  return _buildStrangerHint();
                                }
                                final item = timeline[i - hintOffset];
                                return switch (item) {
                                  _DateSeparator(:final day) =>
                                    _buildDateSeparator(day),
                                  _MessageItem(:final message) => _buildBubble(
                                    message,
                                    currentUserId,
                                  ),
                                };
                              },
                            );
                          },
                        ),
                ),
              ),

              // 图片发送中提示——上传/发消息接口都要走一次网络请求，
              // attach 菜单已经关掉了，不给点反馈会看起来跟点了没反应一样
              if (_sendingImage)
                Container(
                  width: double.infinity,
                  color: bg,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 6,
                  ),
                  child: Row(
                    children: [
                      const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: _primary,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        l10n.sendingImage,
                        style: TextStyle(
                          fontSize: 12,
                          color: Theme.of(context).textTheme.bodySmall?.color,
                        ),
                      ),
                    ],
                  ),
                ),

              // 输入栏
              Container(
                color: bg,
                child: SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 8,
                    ),
                    child: Row(
                      children: [
                        GestureDetector(
                          onTap: _showAttachMenu,
                          child: const Icon(
                            Icons.add_circle_outline,
                            size: 26,
                            color: Colors.grey,
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
                              color: capsuleFill,
                              borderRadius: BorderRadius.circular(20),
                              border: isDark
                                  ? null
                                  : Border.all(
                                      color: const Color(0xFFEAEAEA),
                                      width: 0.8,
                                    ),
                            ),
                            child: TextField(
                              controller: _ctrl,
                              decoration: InputDecoration(
                                border: InputBorder.none,
                                // filled:false 显式关掉——否则会吃全局
                                // InputDecorationTheme 的灰底，在白胶囊里夹出
                                // 一条灰色长条「夹心」
                                filled: false,
                                hintText: l10n.messageInputHint,
                                hintStyle: const TextStyle(color: Colors.grey),
                                isDense: true,
                                contentPadding: EdgeInsets.zero,
                              ),
                              onSubmitted: (_) => _send(),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        GestureDetector(
                          onTap: () {
                            debugPrint('[Chat] 发送按钮点击');
                            _send();
                          },
                          child: Container(
                            width: 36,
                            height: 36,
                            decoration: const BoxDecoration(
                              color: _primary,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.send,
                              color: Colors.white,
                              size: 18,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // _messages 本来就按时间正序排列（最新的在最后），这里只是按自然日
  // 分组插分隔条，不改变消息本身的顺序
  List<_TimelineItem> _buildTimeline() {
    final items = <_TimelineItem>[];
    DateTime? lastDay;
    for (final msg in _messages) {
      final dt = DateTime.fromMillisecondsSinceEpoch(msg.createdAt);
      final day = DateTime(dt.year, dt.month, dt.day);
      if (lastDay == null || day != lastDay) {
        items.add(_DateSeparator(day));
        lastDay = day;
      }
      items.add(_MessageItem(msg));
    }
    return items;
  }

  Widget _buildDateSeparator(DateTime day) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    String label;
    if (day == today) {
      label = AppLocalizations.of(context)!.today;
    } else if (day == yesterday) {
      label = AppLocalizations.of(context)!.yesterday;
    } else {
      const weekdays = ['一', '二', '三', '四', '五', '六', '日'];
      label = '${day.month}月${day.day}日 星期${weekdays[day.weekday - 1]}';
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Center(
        child: Text(
          label,
          style: const TextStyle(fontSize: 11, color: Colors.grey),
        ),
      ),
    );
  }

  // 长按消息 → 操作菜单：复制（文本/代码）/ 删除（全部消息，仅对自己不可见）。
  // 私信没有撤回（后端无接口），只有复制 + 删除
  void _showMessageMenu(ChatMessage msg) {
    final canCopy = msg.type == 'text' || msg.type == 'code';
    showModalBottomSheet(
      context: context,
      backgroundColor: Theme.of(context).cardColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            if (canCopy)
              ListTile(
                leading: const Icon(Icons.copy_outlined, size: 20),
                title: const Text('复制'),
                onTap: () {
                  Clipboard.setData(ClipboardData(text: msg.content));
                  Navigator.pop(ctx);
                },
              ),
            ListTile(
              leading: const Icon(
                Icons.delete_outline,
                size: 20,
                color: Color(0xFFEF4444),
              ),
              title: const Text(
                '删除',
                style: TextStyle(color: Color(0xFFEF4444)),
              ),
              onTap: () {
                Navigator.pop(ctx);
                _deleteMessage(msg);
              },
            ),
          ],
        ),
      ),
    );
  }

  // 删除（仅对自己不可见）——后端只标记当前用户删除，不物理删除、不影响对方。
  // 先弹品牌红色二次确认，成功才本地移除该条
  Future<void> _deleteMessage(ChatMessage msg) async {
    final ok = await showDangerConfirm(
      context,
      title: '删除消息',
      message: '删除后仅对你不可见，对方仍可看到。确认删除？',
      confirmText: '删除',
    );
    if (!ok || !mounted) return;
    try {
      final res = await ref
          .read(apiClientProvider)
          .delete('/auth/messages/${msg.id}', data: {'deleteForSelf': true});
      if (!mounted) return;
      if (res.success) {
        setState(() => _messages.removeWhere((m) => m.id == msg.id));
      } else {
        showAppToast(context, '删除失败，请重试');
      }
    } catch (e) {
      debugPrint('删除私信失败: $e');
      if (mounted) showAppToast(context, '删除失败，请重试');
    }
  }

  Widget _buildBubble(ChatMessage msg, String currentUserId) {
    final isMe = msg.senderId == currentUserId;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        mainAxisAlignment: isMe
            ? MainAxisAlignment.end
            : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!isMe) ...[
            GestureDetector(
              onTap: () => context.push('/users/${msg.senderUsername}'),
              child: _buildAvatar(
                msg.senderAvatar,
                msg.senderUsername,
                AppColors.success,
              ),
            ),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: Column(
              crossAxisAlignment: isMe
                  ? CrossAxisAlignment.end
                  : CrossAxisAlignment.start,
              children: [
                // 长按消息 → 操作菜单（复制 / 删除）
                GestureDetector(
                  onLongPress: () => _showMessageMenu(msg),
                  child: _buildBubbleContent(msg, isMe),
                ),
                const SizedBox(height: 3),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _formatTime(msg.createdAt),
                      style: const TextStyle(fontSize: 11, color: Colors.grey),
                    ),
                    // 已读回执——is_read 是真实字段（打开会话时后端会把对方
                    // 发来的消息标成已读），只在"我发的"这一侧显示，对方
                    // 发给我的消息没必要标"我有没有读对方的"
                    if (isMe) ...[
                      const SizedBox(width: 3),
                      Icon(
                        msg.isRead ? Icons.done_all : Icons.done,
                        size: 13,
                        color: msg.isRead ? _primary : Colors.grey,
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
          if (isMe) ...[
            const SizedBox(width: 8),
            _buildAvatar(msg.senderAvatar, msg.senderUsername, _primary),
          ],
        ],
      ),
    );
  }

  Widget _buildBubbleContent(ChatMessage msg, bool isMe) {
    final l10n = AppLocalizations.of(context)!;
    // 极梦社区问题分享卡片——旧的 type:'text'+链接消息不受影响，仍走文本渲染
    if (msg.type == 'question_share' && msg.metadata != null) {
      final meta = msg.metadata!;
      final qid = meta['questionId']?.toString() ?? '';
      // 详情页读的是 text/domain/answer_count 字段名，这里把卡片 metadata
      // 映射过去，详情页头部/写回答引用才有问题原文
      final q = {
        'id': qid,
        'text': meta['title'],
        'domain': meta['tag'],
        'answer_count': meta['answerCount'],
      };
      return QuestionShareCard(
        metadata: meta,
        onAnswerTap: () =>
            context.push('/questions/$qid', extra: {...q, 'openAnswer': true}),
        onDetailTap: () => context.push('/questions/$qid', extra: q),
      );
    }
    if (msg.type == 'image') {
      return GestureDetector(
        onTap: () => _showImagePreview(context, msg.content),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: CachedNetworkImage(
            imageUrl: msg.content,
            width: 200,
            fit: BoxFit.cover,
            placeholder: (ctx, url) => Container(
              width: 200,
              height: 150,
              color: Colors.grey[200],
              child: const Center(
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
            errorWidget: (ctx, url, error) => Container(
              width: 200,
              height: 100,
              color: Colors.grey[200],
              child: const Icon(Icons.broken_image, color: Colors.grey),
            ),
          ),
        ),
      );
    }

    // type=='latex' 是现在发公式走的路径；旧的 type=='code'+metadata.language
    // 这个组合以前也用来发过公式，两个都认，历史消息不会突然变回代码块
    final isLatex =
        msg.type == 'latex' ||
        (msg.type == 'code' && msg.metadata?['language'] == 'latex');
    if (isLatex) {
      final tex = msg.content
          .replaceAll(r'$$', '')
          .replaceAll(r'\[', '')
          .replaceAll(r'\]', '')
          .trim();
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isMe ? _primary : Theme.of(context).cardColor,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(18),
            topRight: const Radius.circular(18),
            bottomLeft: Radius.circular(isMe ? 18 : 4),
            bottomRight: Radius.circular(isMe ? 4 : 18),
          ),
          border: isMe
              ? null
              : Border.all(color: Theme.of(context).dividerColor),
        ),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Math.tex(
            preprocessLatex(tex),
            textStyle: TextStyle(
              fontSize: 16,
              color: isMe
                  ? Colors.white
                  : Theme.of(context).textTheme.bodyLarge?.color,
            ),
            onErrorFallback: (err) => const FormulaErrorPlaceholder(),
          ),
        ),
      );
    }

    if (msg.type == 'code') {
      final language = msg.metadata?['language'] as String? ?? 'text';
      final lines = msg.content.split('\n');
      final sizeLabel = _formatBytes(utf8.encode(msg.content).length);
      return Container(
        width: 240,
        decoration: BoxDecoration(
          color: const Color(0xFF1C1C1E),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
              child: Row(
                children: [
                  Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: _primary.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(
                      Icons.code_rounded,
                      size: 15,
                      color: _primary,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '$language · $sizeLabel',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Colors.white70,
                      ),
                    ),
                  ),
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => _showCodeMessageMenu(msg.content),
                    child: const Icon(
                      Icons.more_horiz,
                      size: 18,
                      color: Colors.white54,
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1, color: Colors.white12),
            Padding(
              padding: const EdgeInsets.all(12),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (var i = 0; i < lines.length; i++)
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox(
                            width: 18,
                            child: Text(
                              '${i + 1}',
                              style: const TextStyle(
                                fontFamily: 'monospace',
                                fontSize: 12,
                                color: Colors.white30,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            lines[i],
                            style: const TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 12,
                              color: Colors.white,
                              height: 1.5,
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
    }

    if (msg.type == 'file') {
      final filename = msg.metadata?['filename'] as String? ?? '文件';
      final size = (msg.metadata?['size'] as num?)?.toInt() ?? 0;
      return GestureDetector(
        onTap: () => _openLink(msg.content),
        child: Container(
          width: 220,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: isMe ? _primary : Theme.of(context).cardColor,
            borderRadius: BorderRadius.circular(14),
            border: isMe
                ? null
                : Border.all(color: Theme.of(context).dividerColor),
          ),
          child: Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: (isMe ? Colors.white : _primary).withValues(
                    alpha: 0.18,
                  ),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Icon(
                  Icons.insert_drive_file_outlined,
                  size: 18,
                  color: isMe ? Colors.white : _primary,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      filename,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: isMe
                            ? Colors.white
                            : Theme.of(context).textTheme.bodyLarge?.color,
                      ),
                    ),
                    Text(
                      _formatBytes(size),
                      style: TextStyle(
                        fontSize: 11,
                        color: isMe ? Colors.white70 : Colors.grey,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (msg.type == 'tutorial') {
      final title = msg.metadata?['title'] as String? ?? l10n.tutorial;
      final cover = msg.metadata?['cover'] as String?;
      return GestureDetector(
        onTap: () => context.push('/tutorial/${msg.content}'),
        child: Container(
          width: 220,
          decoration: BoxDecoration(
            color: isMe ? _primary : Theme.of(context).cardColor,
            borderRadius: BorderRadius.circular(14),
            border: isMe
                ? null
                : Border.all(color: Theme.of(context).dividerColor),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (cover?.isNotEmpty == true)
                CachedNetworkImage(
                  imageUrl: cover!,
                  height: 100,
                  width: double.infinity,
                  fit: BoxFit.cover,
                ),
              Padding(
                padding: const EdgeInsets.all(10),
                child: Row(
                  children: [
                    Icon(
                      Icons.article_outlined,
                      size: 14,
                      color: isMe ? Colors.white70 : _primary,
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: isMe
                              ? Colors.white
                              : Theme.of(context).textTheme.bodyLarge?.color,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }

    // 普通文字气泡
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: isMe ? _primary : Theme.of(context).cardColor,
        borderRadius: BorderRadius.only(
          topLeft: const Radius.circular(18),
          topRight: const Radius.circular(18),
          bottomLeft: Radius.circular(isMe ? 18 : 4),
          bottomRight: Radius.circular(isMe ? 4 : 18),
        ),
        border: isMe ? null : Border.all(color: Theme.of(context).dividerColor),
      ),
      child: Text(
        msg.content,
        style: TextStyle(
          fontSize: 15,
          color: isMe
              ? Colors.white
              : Theme.of(context).textTheme.bodyLarge?.color,
          height: 1.4,
        ),
      ),
    );
  }

  String _formatTime(int tsMs) {
    final dt = DateTime.fromMillisecondsSinceEpoch(tsMs);
    final now = DateTime.now();
    if (dt.day == now.day && dt.month == now.month && dt.year == now.year) {
      return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    }
    return '${dt.month}/${dt.day} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  void _showCodeMessageMenu(String code) {
    final l10n = AppLocalizations.of(context)!;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: BoxDecoration(
          color: Theme.of(ctx).cardColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.copy_outlined),
              title: Text(l10n.copyAction),
              onTap: () {
                Navigator.pop(ctx);
                Clipboard.setData(ClipboardData(text: code));
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(SnackBar(content: Text(l10n.copiedToClipboard)));
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openLink(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }
}
