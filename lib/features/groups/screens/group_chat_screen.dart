import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_client.dart';
import '../../../shared/widgets/mention_input/mention_popup.dart';
import '../../../shared/widgets/mention_input/mention_query.dart';
import '../../auth/auth_service.dart';
import '../../home/providers/home_feed_provider.dart';
import '../models/group_message_model.dart';
import '../models/group_model.dart';

const _primary = Color(0xFF6366F1);

// 后端还没有 /auth/groups/:id/messages 这套接口（跟上一步建群流程的
// /auth/groups 一样，都是真实调用、真实等后端补上）——_loadMessages
// 失败时在本地种一批演示消息，方便先把气泡/分享卡片/@提及高亮这些
// 视觉效果过一遍；发消息/分享同理，真实接口失败就本地乐观追加一条。
// 这两处都有清楚的注释标出来，后端接口一旦真的存在，res.success 会
// 变成 true，走的就是真实分支，不需要再手动摘掉 mock 逻辑
class GroupChatScreen extends ConsumerStatefulWidget {
  final String groupId;
  final String? groupName;
  final int? initialMemberCount;

  const GroupChatScreen({
    super.key,
    required this.groupId,
    this.groupName,
    this.initialMemberCount,
  });

  @override
  ConsumerState<GroupChatScreen> createState() => _GroupChatScreenState();
}

class _GroupChatScreenState extends ConsumerState<GroupChatScreen>
    with WidgetsBindingObserver {
  final List<GroupMessage> _messages = [];
  final TextEditingController _inputCtrl = TextEditingController();
  final ScrollController _scrollCtrl = ScrollController();
  final FocusNode _focusNode = FocusNode();

  bool _loading = true;
  bool _sending = false;
  String? _lastMsgId;
  Timer? _pollTimer;

  late String _groupName;
  late int _memberCount;

  // @ 提及：群成员本地候选 + 纯逻辑对象（操作 _inputCtrl，不额外持有 controller）
  List<Map<String, dynamic>> _members = [];
  final _mention = MentionQuery();
  String? _mentionQuery;

  // 群详情 + 当前用户在群里的角色，用于「群设置」页
  late GroupModel _group;
  String _myRole = 'member';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _groupName = widget.groupName ?? '群组';
    _memberCount = widget.initialMemberCount ?? 0;
    // 先用上一页带过来的参数兜底，_loadGroupData 拿到真实/演示数据再覆盖
    _group = GroupModel(
      id: widget.groupId,
      name: _groupName,
      ownerId: '',
      isPublic: false,
      joinType: 'invite',
      memberCount: _memberCount,
      tags: const [],
      createdAt: 0,
    );
    _loadGroupData();
    _loadMessages();
    _pollTimer = Timer.periodic(
      const Duration(seconds: 3),
      (_) => _pollMessages(),
    );
    _inputCtrl.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _inputCtrl.dispose();
    _scrollCtrl.dispose();
    _focusNode.dispose();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _pollMessages();
  }

  String get _myId => ref.read(currentUserProvider)?.id ?? '';

  Future<void> _loadMessages() async {
    final res = await ref
        .read(apiClientProvider)
        .get(
          '/auth/groups/${widget.groupId}/messages',
          queryParameters: {'limit': 50},
        );
    if (!mounted) return;
    if (res.success && res.data != null) {
      final msgs = ((res.data['messages'] as List?) ?? [])
          .map(
            (m) => GroupMessage.fromJson(
              Map<String, dynamic>.from(m as Map),
              _myId,
            ),
          )
          .toList();
      setState(() {
        _messages.addAll(msgs);
        _loading = false;
        if (msgs.isNotEmpty) _lastMsgId = msgs.last.id;
      });
      _scrollToBottom(animated: false);
      await ref
          .read(apiClientProvider)
          .post('/auth/groups/${widget.groupId}/read');
      return;
    }
    // 后端接口还不存在——种一批本地演示消息，覆盖文字/分享文章卡/
    // 分享问题卡/@提及/系统消息这几种视觉样式，方便先看UI
    final mock = _mockMessages();
    setState(() {
      _messages.addAll(mock);
      _loading = false;
      _lastMsgId = mock.last.id;
    });
    _scrollToBottom(animated: false);
  }

  // 拉群详情主要是为了拿成员列表给 @ 选择器做本地候选（名字/成员数已经
  // 从上一页参数带过来了，这里拿到真实值就顺手覆盖）。跟 _loadMessages 一样，
  // 群详情接口 /auth/groups/:id 后端还没有——失败时本地种一批演示成员，
  // 保证 @ 选择器有东西可选；接口一旦真的存在，res.success 变 true 自动走真实分支
  Future<void> _loadGroupData() async {
    final res = await ref
        .read(apiClientProvider)
        .get('/auth/groups/${widget.groupId}');
    if (!mounted) return;
    if (res.success && res.data is Map) {
      final data = res.data as Map;
      final group = data['group'];
      final members = ((data['members'] as List?) ?? [])
          .map((m) => Map<String, dynamic>.from(m as Map))
          .toList();
      setState(() {
        if (group is Map) {
          _group = GroupModel.fromJson(Map<String, dynamic>.from(group));
          _groupName = _group.name;
          _memberCount = _group.memberCount;
        }
        if (members.isNotEmpty) {
          _members = members;
          _myRole = _roleOf(_myId, members, _group.ownerId);
        }
      });
      return;
    }
    // 群详情接口还不存在——演示数据里把自己当群主，方便先把群主管理界面过一遍
    setState(() {
      _members = _mockMembers();
      _myRole = 'owner';
    });
  }

  // 从成员列表里找当前用户的角色；找不到就看是不是群主，再兜底 member
  String _roleOf(
    String uid,
    List<Map<String, dynamic>> members,
    String ownerId,
  ) {
    for (final m in members) {
      if ((m['id'] ?? m['user_id'] ?? '').toString() == uid) {
        return '${m['role'] ?? 'member'}';
      }
    }
    return uid.isNotEmpty && uid == ownerId ? 'owner' : 'member';
  }

  // 演示成员——名字跟 _mockMessages 里的发言人一致，@ 起来更真实；
  // 顺带带上 role/头像，「群设置」页的角色标签才有东西显示
  List<Map<String, dynamic>> _mockMembers() {
    final me = ref.read(currentUserProvider);
    return [
      {
        'id': _myId,
        'username': me?.username ?? '我',
        'avatar': me?.avatar,
        'role': 'owner',
      },
      {'id': 'u1', 'username': '宇宙观测员', 'role': 'admin'},
      {'id': 'u2', 'username': '生科研究员', 'role': 'member'},
      {'id': 'u3', 'username': '小梦', 'role': 'member'},
      {'id': 'u4', 'username': '大兔兔', 'role': 'member'},
    ];
  }

  Future<void> _pollMessages() async {
    if (!mounted) return;
    final res = await ref
        .read(apiClientProvider)
        .get(
          '/auth/groups/${widget.groupId}/messages',
          queryParameters: {
            if (_lastMsgId != null) 'after': _lastMsgId,
            'limit': 20,
          },
        );
    if (!mounted || !res.success || res.data == null) return;
    final newMsgs = ((res.data['messages'] as List?) ?? [])
        .map(
          (m) =>
              GroupMessage.fromJson(Map<String, dynamic>.from(m as Map), _myId),
        )
        .toList();
    if (newMsgs.isEmpty) return;
    setState(() {
      _messages.addAll(newMsgs);
      _lastMsgId = newMsgs.last.id;
    });
    final pos = _scrollCtrl.hasClients ? _scrollCtrl.position : null;
    final nearBottom = pos == null || pos.maxScrollExtent - pos.pixels < 120;
    if (nearBottom) _scrollToBottom();
    await ref
        .read(apiClientProvider)
        .post('/auth/groups/${widget.groupId}/read');
  }

  Future<void> _sendText() async {
    final text = _inputCtrl.text.trim();
    if (text.isEmpty || _sending) return;
    _inputCtrl.clear();
    // clear() 不会触发 onChanged，若发送时 @ 浮层还开着要手动复位，否则残留不消
    _mention.reset();
    setState(() {
      _sending = true;
      _mentionQuery = null;
    });

    final res = await ref
        .read(apiClientProvider)
        .post(
          '/auth/groups/${widget.groupId}/messages',
          data: {'type': 'text', 'content': text},
        );
    if (!mounted) return;

    final msg = res.success && res.data?['message'] != null
        ? GroupMessage.fromJson(
            Map<String, dynamic>.from(res.data['message'] as Map),
            _myId,
          )
        : _localMessage(type: GroupMessageType.text, content: text);
    setState(() {
      _messages.add(msg);
      _lastMsgId = msg.id;
      _sending = false;
    });
    _scrollToBottom();
  }

  Future<void> _shareContent(String type) async {
    final picked = type == 'share_tutorial'
        ? await _pickTutorial()
        : await _pickQuestion();
    if (picked == null || !mounted) return;

    final res = await ref
        .read(apiClientProvider)
        .post(
          '/auth/groups/${widget.groupId}/messages',
          data: {
            'type': type,
            'content': picked['title'],
            'ref_id': picked['id'],
            'ref_title': picked['title'],
            'ref_meta': picked['meta'],
          },
        );
    if (!mounted) return;

    final msg = res.success && res.data?['message'] != null
        ? GroupMessage.fromJson(
            Map<String, dynamic>.from(res.data['message'] as Map),
            _myId,
          )
        : _localMessage(
            type: type == 'share_tutorial'
                ? GroupMessageType.shareTutorial
                : GroupMessageType.shareQuestion,
            content: picked['title'] ?? '',
            refId: picked['id'],
            refTitle: picked['title'],
            refMeta: picked['meta'],
          );
    setState(() {
      _messages.add(msg);
      _lastMsgId = msg.id;
    });
    _scrollToBottom();
  }

  // 分享文章——取跟极索首页共用的 homeFeedProvider（真实已发布教程，
  // 本来就一直保持热的，不用再单独拉一次接口）
  Future<Map<String, String>?> _pickTutorial() {
    final tutorials = ref.read(homeFeedProvider).tutorials;
    if (tutorials.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('暂无可分享的文章')));
      return Future.value(null);
    }
    return showModalBottomSheet<Map<String, String>>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => _PickerSheet(
        title: '分享极梦文章',
        items: tutorials
            .map(
              (t) => _PickerItem(
                id: t.id,
                title: t.title,
                meta: '${t.username} · ${t.views}浏览',
              ),
            )
            .toList(),
      ),
    );
  }

  // 分享问题——真实拉一批极索问题
  Future<Map<String, String>?> _pickQuestion() async {
    final res = await ref
        .read(apiClientProvider)
        .get('/auth/questions', queryParameters: {'limit': 20});
    if (!mounted) return null;
    if (!res.success || res.data == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('获取问题列表失败')));
      return null;
    }
    final questions = ((res.data['questions'] as List?) ?? [])
        .map((q) => Map<String, dynamic>.from(q as Map))
        .toList();
    if (questions.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('暂无可分享的问题')));
      return null;
    }
    return showModalBottomSheet<Map<String, String>>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => _PickerSheet(
        title: '分享极索问题',
        items: questions
            .map(
              (q) => _PickerItem(
                id: q['id'].toString(),
                title: q['text'] as String? ?? '',
                meta:
                    '${q['domain'] ?? ''} · ${(q['answer_count'] as num?)?.toInt() ?? 0} 个回答',
              ),
            )
            .toList(),
      ),
    );
  }

  GroupMessage _localMessage({
    required GroupMessageType type,
    required String content,
    String? refId,
    String? refTitle,
    String? refMeta,
  }) {
    final me = ref.read(currentUserProvider);
    return GroupMessage(
      id: 'local-${DateTime.now().microsecondsSinceEpoch}',
      groupId: widget.groupId,
      senderId: _myId,
      senderName: me?.username ?? '我',
      senderAvatar: me?.avatar,
      type: type,
      content: content,
      refId: refId,
      refTitle: refTitle,
      refMeta: refMeta,
      createdAt: DateTime.now().millisecondsSinceEpoch,
      isMe: true,
    );
  }

  List<GroupMessage> _mockMessages() {
    final now = DateTime.now().millisecondsSinceEpoch;
    Map<String, dynamic> base(
      String id,
      String senderId,
      String senderName,
      String content, {
      String type = 'text',
      String? refId,
      String? refTitle,
      String? refMeta,
      int offsetMinutes = 0,
    }) => {
      'id': id,
      'group_id': widget.groupId,
      'sender_id': senderId,
      'sender_name': senderName,
      'type': type,
      'content': content,
      'ref_id': refId,
      'ref_title': refTitle,
      'ref_meta': refMeta,
      'created_at': (now / 1000).floor() + offsetMinutes * 60,
    };

    final raw = [
      base('m1', 'system', 'system', '$_groupName 创建成功', offsetMinutes: -30),
      base('m2', 'u1', '宇宙观测员', '大家好！终于有个地方可以一起讨论了 😄', offsetMinutes: -25),
      base('m3', 'u2', '生科研究员', '欢迎欢迎，我最近在研究这方面的问题', offsetMinutes: -20),
      base(
        'm4',
        'u1',
        '宇宙观测员',
        '推荐一篇文章给大家',
        type: 'share_tutorial',
        refId: '0',
        refTitle: '贝叶斯定理：用一个例子彻底理解「先验」和「后验」',
        refMeta: '小梦 · 1.2k 阅读',
        offsetMinutes: -15,
      ),
      base('m5', 'u2', '生科研究员', '@宇宙观测员 这篇文章里的方法部分我还有点困惑', offsetMinutes: -10),
      base(
        'm6',
        'u1',
        '宇宙观测员',
        '正好我也想分享一个极索里的问题',
        type: 'share_question',
        refId: '0',
        refTitle: '先验分布应该怎么选？有没有系统性的方法？',
        refMeta: '数学 · 2 个回答',
        offsetMinutes: -5,
      ),
    ];
    return raw.map((j) => GroupMessage.fromJson(j, _myId)).toList();
  }

  void _scrollToBottom({bool animated = true}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollCtrl.hasClients) return;
      if (animated) {
        _scrollCtrl.animateTo(
          _scrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      } else {
        _scrollCtrl.jumpTo(_scrollCtrl.position.maxScrollExtent);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: _buildAppBar(isDark),
      body: GestureDetector(
        onTap: _focusNode.unfocus,
        child: Column(
          children: [
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _buildMessageList(isDark),
            ),
            // @ 提及浮层——群成员本地过滤，选中后回填到 _inputCtrl
            if (_mentionQuery != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 0, 10, 4),
                child: MentionPopup(
                  query: _mentionQuery!,
                  candidates: _members,
                  onSelect: (username) {
                    _mention.insert(_inputCtrl, username);
                    setState(() => _mentionQuery = null);
                  },
                ),
              ),
            _buildInputBar(isDark),
          ],
        ),
      ),
    );
  }

  void _comingSoon(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  PreferredSizeWidget _buildAppBar(bool isDark) {
    return AppBar(
      backgroundColor: isDark
          ? const Color(0xFF0A0A1A).withValues(alpha: 0.95)
          : Colors.white.withValues(alpha: 0.95),
      elevation: 0,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back_ios, size: 18),
        onPressed: () => context.pop(),
      ),
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _groupName,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
          ),
          if (_memberCount > 0)
            Text(
              '$_memberCount 名成员',
              style: TextStyle(
                fontSize: 11,
                color: isDark
                    ? Colors.white.withValues(alpha: 0.4)
                    : Colors.grey[500],
              ),
            ),
        ],
      ),
      actions: [
        IconButton(
          icon: const Icon(Icons.search, size: 20),
          onPressed: () => _comingSoon('搜索消息即将上线'),
        ),
        IconButton(
          icon: const Icon(Icons.settings_outlined, size: 20),
          onPressed: () => context.push(
            '/group/${widget.groupId}/settings',
            extra: {'group': _group, 'members': _members, 'myRole': _myRole},
          ),
        ),
      ],
    );
  }

  Widget _buildMessageList(bool isDark) {
    return ListView.builder(
      controller: _scrollCtrl,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      itemCount: _messages.length,
      itemBuilder: (ctx, i) {
        final msg = _messages[i];
        final prev = i > 0 ? _messages[i - 1] : null;
        final showDate =
            prev == null || !_isSameDay(prev.createdAt, msg.createdAt);
        final showSender =
            !msg.isMe &&
            (prev == null || prev.senderId != msg.senderId || showDate);

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (showDate) _buildDateDivider(msg.createdAt, isDark),
            _buildMsgRow(msg, showSender, isDark),
          ],
        );
      },
    );
  }

  Widget _buildDateDivider(int ts, bool isDark) {
    final now = DateTime.now().millisecondsSinceEpoch;
    String label;
    if (_isSameDay(ts, now)) {
      label = '今天';
    } else if (_isSameDay(ts, now - const Duration(days: 1).inMilliseconds)) {
      label = '昨天';
    } else {
      final d = DateTime.fromMillisecondsSinceEpoch(ts);
      label = '${d.month}月${d.day}日';
    }
    final lineColor = isDark
        ? Colors.white.withValues(alpha: 0.1)
        : Colors.black.withValues(alpha: 0.1);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          Expanded(child: Container(height: 0.5, color: lineColor)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text(
              label,
              style: TextStyle(
                fontSize: 10,
                color: isDark
                    ? Colors.white.withValues(alpha: 0.3)
                    : Colors.black.withValues(alpha: 0.3),
              ),
            ),
          ),
          Expanded(child: Container(height: 0.5, color: lineColor)),
        ],
      ),
    );
  }

  Widget _buildMsgRow(GroupMessage msg, bool showSender, bool isDark) {
    if (msg.senderId == 'system') {
      return Center(
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 6),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          decoration: BoxDecoration(
            color: isDark
                ? Colors.white.withValues(alpha: 0.08)
                : Colors.black.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(99),
          ),
          child: Text(
            msg.content,
            style: TextStyle(
              fontSize: 11,
              color: isDark
                  ? Colors.white.withValues(alpha: 0.4)
                  : Colors.black.withValues(alpha: 0.4),
            ),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        mainAxisAlignment: msg.isMe
            ? MainAxisAlignment.end
            : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: msg.isMe
            ? [
                _buildMsgContent(msg, showSender, isDark),
                const SizedBox(width: 8),
                _buildAvatar(msg, isDark),
              ]
            : [
                _buildAvatar(msg, isDark),
                const SizedBox(width: 8),
                _buildMsgContent(msg, showSender, isDark),
              ],
      ),
    );
  }

  // 群聊里要能一眼分清不同成员，跟私信/通知列表统一用 kMessagesPrimary
  // 单色兜底的 buildMessageAvatar 不是同一个需求——真实头像走同一套
  // 图片渲染逻辑，没有头像时按 senderId 哈希取一个稳定的颜色区分成员
  Widget _buildAvatar(GroupMessage msg, bool isDark) {
    final avatar = msg.senderAvatar;
    if (avatar != null && avatar.isNotEmpty) {
      return Container(
        width: 30,
        height: 30,
        margin: const EdgeInsets.only(bottom: 16),
        decoration: const BoxDecoration(shape: BoxShape.circle),
        clipBehavior: Clip.antiAlias,
        child: Image.network(
          avatar,
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) => _initialAvatar(msg),
        ),
      );
    }
    return _initialAvatar(msg);
  }

  Widget _initialAvatar(GroupMessage msg) {
    return Container(
      width: 30,
      height: 30,
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: _colorForUser(msg.senderId),
        shape: BoxShape.circle,
      ),
      child: Center(
        child: Text(
          msg.senderName.isNotEmpty ? msg.senderName.substring(0, 1) : 'U',
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: Colors.white,
          ),
        ),
      ),
    );
  }

  Widget _buildMsgContent(GroupMessage msg, bool showSender, bool isDark) {
    return Column(
      crossAxisAlignment: msg.isMe
          ? CrossAxisAlignment.end
          : CrossAxisAlignment.start,
      children: [
        if (showSender && !msg.isMe)
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 3),
            child: Text(
              msg.senderName,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w500,
                color: isDark
                    ? Colors.white.withValues(alpha: 0.4)
                    : Colors.black.withValues(alpha: 0.4),
              ),
            ),
          ),
        ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.68,
          ),
          child: msg.type == GroupMessageType.text
              ? _buildTextBubble(msg, isDark)
              : _buildShareCard(msg, isDark),
        ),
        Padding(
          padding: EdgeInsets.only(
            top: 3,
            left: msg.isMe ? 0 : 4,
            right: msg.isMe ? 4 : 0,
          ),
          child: Text(
            _formatTime(msg.createdAt),
            style: TextStyle(
              fontSize: 9,
              color: isDark
                  ? Colors.white.withValues(alpha: 0.25)
                  : Colors.black.withValues(alpha: 0.25),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTextBubble(GroupMessage msg, bool isDark) {
    final isMe = msg.isMe;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: isMe
            ? _primary
            : isDark
            ? Colors.white.withValues(alpha: 0.1)
            : Colors.white,
        borderRadius: BorderRadius.only(
          topLeft: const Radius.circular(14),
          topRight: const Radius.circular(14),
          bottomLeft: isMe
              ? const Radius.circular(14)
              : const Radius.circular(4),
          bottomRight: isMe
              ? const Radius.circular(4)
              : const Radius.circular(14),
        ),
        boxShadow: isMe
            ? null
            : [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 4,
                  offset: const Offset(0, 1),
                ),
              ],
      ),
      child: _buildRichText(msg.content, isMe, isDark),
    );
  }

  Widget _buildRichText(String text, bool isMe, bool isDark) {
    final spans = <InlineSpan>[];
    final regex = RegExp(r'@([一-龥\w]+)');
    var last = 0;
    for (final m in regex.allMatches(text)) {
      if (m.start > last) {
        spans.add(TextSpan(text: text.substring(last, m.start)));
      }
      spans.add(
        TextSpan(
          text: m.group(0),
          style: TextStyle(
            fontWeight: FontWeight.w600,
            color: isMe ? Colors.white.withValues(alpha: 0.85) : _primary,
          ),
        ),
      );
      last = m.end;
    }
    if (last < text.length) spans.add(TextSpan(text: text.substring(last)));

    return RichText(
      text: TextSpan(
        style: TextStyle(
          fontSize: 13,
          height: 1.5,
          color: isMe
              ? Colors.white
              : isDark
              ? Colors.white.withValues(alpha: 0.9)
              : const Color(0xFF1A1A1A),
        ),
        children: spans,
      ),
    );
  }

  Widget _buildShareCard(GroupMessage msg, bool isDark) {
    final isMe = msg.isMe;
    final isTutorial = msg.type == GroupMessageType.shareTutorial;

    return GestureDetector(
      onTap: () {
        if (msg.refId == null) return;
        context.push(
          isTutorial ? '/tutorial/${msg.refId}' : '/questions/${msg.refId}',
        );
      },
      child: Container(
        width: 220,
        decoration: BoxDecoration(
          color: isMe
              ? Colors.white.withValues(alpha: 0.15)
              : isDark
              ? Colors.white.withValues(alpha: 0.06)
              : const Color(0xFFF9F9FB),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isMe
                ? Colors.white.withValues(alpha: 0.2)
                : isDark
                ? Colors.white.withValues(alpha: 0.08)
                : const Color(0xFFE0E0E8),
            width: 0.5,
          ),
        ),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(
                    color: isMe
                        ? Colors.white.withValues(alpha: 0.15)
                        : isDark
                        ? Colors.white.withValues(alpha: 0.06)
                        : const Color(0xFFEBEBEB),
                    width: 0.5,
                  ),
                ),
              ),
              child: Row(
                children: [
                  Container(
                    width: 20,
                    height: 20,
                    decoration: BoxDecoration(
                      color: isMe
                          ? Colors.white.withValues(alpha: 0.15)
                          : isTutorial
                          ? const Color(0xFFEEF0FF)
                          : const Color(0xFFF3E8FF),
                      borderRadius: BorderRadius.circular(5),
                    ),
                    child: Icon(
                      isTutorial ? Icons.article_outlined : Icons.help_outline,
                      size: 12,
                      color: isMe
                          ? Colors.white.withValues(alpha: 0.8)
                          : isTutorial
                          ? _primary
                          : const Color(0xFF8B5CF6),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    isTutorial ? '极梦文章' : '极索问题',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      letterSpacing: .04,
                      color: isMe
                          ? Colors.white.withValues(alpha: 0.7)
                          : isTutorial
                          ? _primary
                          : const Color(0xFF8B5CF6),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    msg.refTitle ?? '',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      height: 1.4,
                      color: isMe
                          ? Colors.white.withValues(alpha: 0.95)
                          : isDark
                          ? Colors.white.withValues(alpha: 0.9)
                          : const Color(0xFF1A1A1A),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    msg.refMeta ?? '',
                    style: TextStyle(
                      fontSize: 10,
                      color: isMe
                          ? Colors.white.withValues(alpha: 0.55)
                          : isDark
                          ? Colors.white.withValues(alpha: 0.4)
                          : Colors.grey[500],
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

  // "+"菜单——跟私信页 chat_screen.dart 的 _showAttachMenu 同一套视觉
  // 语言：真正的 showModalBottomSheet（不是内嵌在 Column 里临时插一块），
  // 拖拽把手+cardColor+圆角+图标格子横排，不是自己另起一套卡片/边框风格
  void _showPlusMenu() {
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
                _attachBtn(Icons.article_outlined, '分享极梦文章', () {
                  Navigator.pop(ctx);
                  _shareContent('share_tutorial');
                }),
                _attachBtn(Icons.help_outline, '分享极索问题', () {
                  Navigator.pop(ctx);
                  _shareContent('share_question');
                }),
              ],
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
              color: const Color(0xFFEEF0FF),
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

  Widget _buildInputBar(bool isDark) {
    final hasText = _inputCtrl.text.trim().isNotEmpty;

    return Container(
      color: Theme.of(context).cardColor,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              GestureDetector(
                onTap: _showPlusMenu,
                child: const Padding(
                  padding: EdgeInsets.only(bottom: 5),
                  child: Icon(
                    Icons.add_circle_outline,
                    size: 26,
                    color: Colors.grey,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Container(
                  constraints: const BoxConstraints(maxHeight: 100),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: Theme.of(context).inputDecorationTheme.fillColor,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: TextField(
                    controller: _inputCtrl,
                    focusNode: _focusNode,
                    maxLines: null,
                    textInputAction: TextInputAction.newline,
                    onChanged: (_) => setState(
                      () => _mentionQuery = _mention.detect(_inputCtrl),
                    ),
                    decoration: const InputDecoration(
                      border: InputBorder.none,
                      hintText: '发消息...',
                      hintStyle: TextStyle(color: Colors.grey),
                      isDense: true,
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: hasText && !_sending ? _sendText : null,
                child: Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: hasText ? _primary : Theme.of(context).disabledColor,
                    shape: BoxShape.circle,
                  ),
                  child: _sending
                      ? const Padding(
                          padding: EdgeInsets.all(9),
                          child: CircularProgressIndicator(
                            strokeWidth: 1.5,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.send, color: Colors.white, size: 18),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  bool _isSameDay(int ts1, int ts2) {
    final d1 = DateTime.fromMillisecondsSinceEpoch(ts1);
    final d2 = DateTime.fromMillisecondsSinceEpoch(ts2);
    return d1.year == d2.year && d1.month == d2.month && d1.day == d2.day;
  }

  String _formatTime(int ts) {
    final d = DateTime.fromMillisecondsSinceEpoch(ts);
    return '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  }

  Color _colorForUser(String userId) {
    const colors = [
      _primary,
      Color(0xFF8B5CF6),
      Color(0xFF16A34A),
      Color(0xFFD97706),
      Color(0xFFEC4899),
      Color(0xFF0891B2),
    ];
    return colors[userId.hashCode.abs() % colors.length];
  }
}

class _PickerItem {
  final String id;
  final String title;
  final String meta;
  const _PickerItem({
    required this.id,
    required this.title,
    required this.meta,
  });
}

class _PickerSheet extends StatelessWidget {
  final String title;
  final List<_PickerItem> items;
  const _PickerSheet({required this.title, required this.items});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return FractionallySizedBox(
      heightFactor: 0.6,
      child: Container(
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
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
              padding: const EdgeInsets.symmetric(vertical: 14),
              child: Text(
                title,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: items.length,
                separatorBuilder: (_, _) =>
                    Divider(height: 1, color: Theme.of(context).dividerColor),
                itemBuilder: (ctx, i) {
                  final item = items[i];
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      item.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    subtitle: Text(
                      item.meta,
                      style: TextStyle(
                        fontSize: 11,
                        color: isDark
                            ? Colors.white.withValues(alpha: 0.4)
                            : Colors.grey[500],
                      ),
                    ),
                    onTap: () => Navigator.pop(ctx, {
                      'id': item.id,
                      'title': item.title,
                      'meta': item.meta,
                    }),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
