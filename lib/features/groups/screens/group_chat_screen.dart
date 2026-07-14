import 'dart:async';
import 'dart:convert';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:dio/dio.dart';
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
import '../../../core/theme/app_theme.dart';
import '../../../shared/utils/pro_access.dart';
import '../../../shared/widgets/formula_error.dart';
import '../../../shared/widgets/mention_input/mention_popup.dart';
import '../../../shared/widgets/mention_input/mention_query.dart';
import '../../auth/auth_service.dart';
import '../../home/providers/home_feed_provider.dart';
import '../models/group_message_model.dart';
import '../models/group_model.dart';

const _primary = Color(0xFF6366F1);

// 群相关接口大部分已上线（GET /auth/groups 列表、GET /auth/groups/:id 详情、
// POST 建群等）；只有 GET /auth/groups/:id/messages 消息接口还没上线，拉取
// 失败时不再塞演示消息（否则真实群里会冒出不在群里的假人），改为显示空状态。
// 发消息/分享仍保留乐观更新：真实接口失败时本地先追加一条，等接口补齐后
// res.success 变 true 自动走真实分支
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
  bool _sendingMedia = false;
  // 代码/公式弹窗各自的发送按钮——跟正文的 _sending 分开，两个弹窗都是
  // showModalBottomSheet 独立的 BuildContext，共用一个标志位会导致其中
  // 一个弹窗还在发送时另一个弹窗的按钮却误判成"空闲"
  bool _sendingRich = false;
  bool _attachPanelOpen = false;
  String? _lastMsgId;
  Timer? _pollTimer;

  static const _codeLanguages = ['Python', 'JavaScript', 'SQL', 'Text'];

  late String _groupName;
  late int _memberCount;

  // @ 提及：群成员本地候选 + 纯逻辑对象（操作 _inputCtrl，不额外持有 controller）
  List<Map<String, dynamic>> _members = [];
  final _mention = MentionQuery();
  String? _mentionQuery;

  // 群详情 + 当前用户在群里的角色，用于「群设置」页
  late GroupModel _group;
  String _myRole = 'member';

  // 群内消息搜索
  bool _searchMode = false;
  String _searchQuery = '';
  final _searchCtrl = TextEditingController();
  List<int> _matchIndices = []; // 命中消息在 _messages 里的下标
  int _currentMatchIdx = 0; // 当前定位到第几条命中（_matchIndices 的下标）
  final Map<int, GlobalKey> _itemKeys = {}; // 每条消息一个 key，用于滚动定位

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
    _searchCtrl.dispose();
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
    // 消息接口拉取失败（比如 /auth/groups/:id/messages 还没上线）——不再兜底
    // 塞演示消息，否则真实群里会冒出不在群里的假人；直接结束 loading，
    // 交给空状态提示。接口上线后 res.success 为 true，自动走上面的真实分支
    if (mounted) setState(() => _loading = false);
  }

  // 拉群详情主要是为了拿成员列表给 @ 选择器做本地候选（名字/成员数已经
  // 从上一页参数带过来了，这里拿到真实值就顺手覆盖）。/auth/groups/:id 已上线；
  // 万一拉取失败就保持空成员列表，不再塞演示成员
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
    // 拉取失败就保持空成员列表 + 默认 member 角色，不再塞演示成员
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

  // 图片/文件/代码/公式共用的发送收尾——POST 真实接口，优先用响应里的
  // 真实消息对象，响应里没有（比如网络抖动但请求其实成功了）才退回本地
  // 构造的乐观消息，跟 _sendText/_shareContent 是同一套收尾逻辑
  Future<void> _sendGroupMessage({
    required GroupMessageType type,
    required String typeStr,
    required String content,
    String? refId,
    String? refTitle,
    String? refMeta,
    Map<String, dynamic>? metadata,
  }) async {
    final res = await ref
        .read(apiClientProvider)
        .post(
          '/auth/groups/${widget.groupId}/messages',
          data: {
            'type': typeStr,
            'content': content,
            if (refId != null) 'ref_id': refId,
            if (refTitle != null) 'ref_title': refTitle,
            if (refMeta != null) 'ref_meta': refMeta,
            if (metadata != null) 'metadata': metadata,
          },
        );
    if (!mounted) return;
    final msg = res.success && res.data?['message'] != null
        ? GroupMessage.fromJson(
            Map<String, dynamic>.from(res.data['message'] as Map),
            _myId,
          )
        : _localMessage(
            type: type,
            content: content,
            refId: refId,
            refTitle: refTitle,
            refMeta: refMeta,
            metadata: metadata,
          );
    setState(() {
      _messages.add(msg);
      _lastMsgId = msg.id;
    });
    _scrollToBottom();
  }

  Future<void> _sendImage({ImageSource source = ImageSource.gallery}) async {
    if (_sendingMedia) return;
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

    setState(() => _sendingMedia = true);
    try {
      final formData = FormData.fromMap({
        'file': MultipartFile.fromBytes(
          bytes,
          filename: 'img_${DateTime.now().millisecondsSinceEpoch}.jpg',
          contentType: DioMediaType('image', 'jpeg'),
        ),
      });
      final uploadRes = await ref
          .read(apiClientProvider)
          .post('/auth/files/upload', data: formData);
      if (!uploadRes.success) {
        throw Exception(uploadRes.message ?? '上传失败，请稍后重试');
      }
      final imageUrl = (uploadRes.data as Map)['url'] as String?;
      if (imageUrl == null) throw Exception('上传失败，请稍后重试');
      await _sendGroupMessage(
        type: GroupMessageType.image,
        typeStr: 'image',
        content: imageUrl,
        metadata: {'url': imageUrl},
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('发送失败：${e.toString().replaceAll('Exception: ', '')}'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _sendingMedia = false);
    }
  }

  // 通用文件——复用图片走的同一个 /auth/files/upload。group_messages 表
  // 没有私信 message_model.dart 那种通用 metadata JSON 列，只有
  // ref_id/ref_title/ref_meta 三个通用字符串字段（share_tutorial/
  // share_question 本来就在借用它们放标题/副标题）——这里借用同样的字段
  // 放文件名/字节数，不是照搬私信的 metadata 实现，但效果一致
  Future<void> _sendFile() async {
    if (_sendingMedia) return;
    final result = await FilePicker.platform.pickFiles(withData: true);
    if (result == null || result.files.isEmpty) return;
    final picked = result.files.first;
    final bytes = picked.bytes;
    if (bytes == null || !mounted) return;

    setState(() => _sendingMedia = true);
    try {
      final formData = FormData.fromMap({
        'file': MultipartFile.fromBytes(bytes, filename: picked.name),
      });
      final uploadRes = await ref
          .read(apiClientProvider)
          .post('/auth/files/upload', data: formData);
      if (!uploadRes.success) {
        throw Exception(uploadRes.message ?? '上传失败，请稍后重试');
      }
      final fileUrl = (uploadRes.data as Map)['url'] as String?;
      if (fileUrl == null) throw Exception('上传失败，请稍后重试');
      await _sendGroupMessage(
        type: GroupMessageType.file,
        typeStr: 'file',
        content: fileUrl,
        metadata: {
          'url': fileUrl,
          'filename': picked.name,
          'size': bytes.length,
        },
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('发送失败：${e.toString().replaceAll('Exception: ', '')}'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _sendingMedia = false);
    }
  }

  void _showCodeInput() {
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
              const Text(
                '发送代码',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
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
                  decoration: const InputDecoration(
                    filled: false,
                    border: InputBorder.none,
                    hintText: '# 输入代码...',
                    hintStyle: TextStyle(color: Colors.grey),
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
                  // setSheetState 让按钮在点下的一瞬间就变禁用，挡住手速快
                  // 造成的连续两次 onPressed；_sendingRich 是真正的守卫——
                  // 就算按钮视觉上没能立刻变灰，闭包一开头的判断也会拦住
                  // 第二次调用，不会真的发出两条重复消息
                  onPressed: _sendingRich
                      ? null
                      : () async {
                          final code = codeCtrl.text.trim();
                          if (code.isEmpty || _sendingRich) return;
                          setSheetState(() => _sendingRich = true);
                          Navigator.pop(ctx);
                          await _sendGroupMessage(
                            type: GroupMessageType.code,
                            typeStr: 'code',
                            content: code,
                            metadata: {'language': selectedLanguage},
                          );
                          if (mounted) setState(() => _sendingRich = false);
                        },
                  child: const Text(
                    '发送',
                    style: TextStyle(color: Colors.white),
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
    final latexCtrl = TextEditingController();
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
              const Text(
                '发送公式',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: latexCtrl,
                autofocus: true,
                decoration: InputDecoration(
                  hintText: '例如：E = mc^2',
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
                  onPressed: _sendingRich
                      ? null
                      : () async {
                          final latex = latexCtrl.text.trim();
                          if (latex.isEmpty || _sendingRich) return;
                          setSheetState(() => _sendingRich = true);
                          Navigator.pop(ctx);
                          await _sendGroupMessage(
                            type: GroupMessageType.formula,
                            typeStr: 'formula',
                            content: latex,
                          );
                          if (mounted) setState(() => _sendingRich = false);
                        },
                  child: const Text(
                    '发送',
                    style: TextStyle(color: Colors.white),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showImagePreview(String url) {
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

  void _showCodeMessageMenu(String code) {
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
              title: const Text('复制'),
              onTap: () {
                Navigator.pop(ctx);
                Clipboard.setData(ClipboardData(text: code));
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(const SnackBar(content: Text('已复制到剪贴板')));
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

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
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
    Map<String, dynamic>? metadata,
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
      metadata: metadata,
      createdAt: DateTime.now().millisecondsSinceEpoch,
      isMe: true,
    );
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
      backgroundColor: isDark ? AppColors.darkBg : const Color(0xFFFAFAF8),
      appBar: _searchMode ? _buildSearchBar(isDark) : _buildAppBar(isDark),
      body: GestureDetector(
        // 点空白处收起键盘——opaque 让整块正文（含消息间空隙）都接住 tap；
        // 用 FocusScope.unfocus 而不是只 unfocus 输入框那个 node，搜索态下
        // 也能把搜索框的键盘一起收起
        behavior: HitTestBehavior.opaque,
        onTap: () => FocusScope.of(context).unfocus(),
        child: Column(
          children: [
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _messages.isEmpty
                  ? _buildEmptyMessages(isDark)
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
            _buildAttachPanel(isDark),
          ],
        ),
      ),
    );
  }

  PreferredSizeWidget _buildAppBar(bool isDark) {
    return AppBar(
      // 顶栏跟正文（scaffold 米白 #FAFAF8）连成一块，不再是白色刀切；
      // 深色仍用 cardColor
      backgroundColor: isDark
          ? Theme.of(context).cardColor
          : const Color(0xFFFAFAF8),
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
          onPressed: () => setState(() => _searchMode = true),
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

  // 搜索栏跟这个 App 其它搜索框（search_screen.dart/conversation_list_
  // screen.dart）同一套视觉语言：灰色圆角胶囊+放大镜前缀+有内容才出现的
  // 清空按钮，不是自己另起一套没有图标、纯边框的输入框。命中数/翻页也
  // 包一个胶囊容器，不是三个元素干巴巴地散在 AppBar actions 里
  PreferredSizeWidget _buildSearchBar(bool isDark) {
    // 深色下去掉那层灰胶囊底——它在近黑 AppBar 上糊成一个突兀的深灰长方
    // 块，很影响观感；深色直接用透明底、放大镜+输入内联在 AppBar 上更干净。
    // 浅色保留浅灰胶囊（跟搜索页/私信列表的搜索框一套，且不是"深灰"）
    final pillBg = isDark ? Colors.transparent : const Color(0xFFF0F0F0);
    final muted = isDark
        ? Colors.white.withValues(alpha: 0.4)
        : Colors.grey[500];

    return AppBar(
      // 搜索栏跟正文米白连贯；深色仍用 cardColor
      backgroundColor: isDark
          ? Theme.of(context).cardColor
          : const Color(0xFFFAFAF8),
      elevation: 0,
      titleSpacing: 0,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back_ios, size: 18),
        onPressed: _exitSearch,
      ),
      title: Container(
        height: 36,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: pillBg,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Row(
          children: [
            Icon(Icons.search, size: 18, color: muted),
            const SizedBox(width: 6),
            Expanded(
              child: TextField(
                controller: _searchCtrl,
                autofocus: true,
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  hintText: '搜索消息',
                  hintStyle: TextStyle(fontSize: 14, color: muted),
                  // 不关掉全局 filled 会在灰色搜索胶囊里透出一层白色方块
                  // （踩坑#13）
                  filled: false,
                  border: InputBorder.none,
                  isDense: true,
                  contentPadding: EdgeInsets.zero,
                ),
                style: TextStyle(
                  fontSize: 14,
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.9)
                      : const Color(0xFF1A1A1A),
                ),
                onChanged: (v) {
                  setState(() {
                    _searchQuery = v.trim();
                    _updateMatches();
                  });
                },
              ),
            ),
            if (_searchQuery.isNotEmpty)
              GestureDetector(
                onTap: () {
                  _searchCtrl.clear();
                  setState(() {
                    _searchQuery = '';
                    _updateMatches();
                  });
                },
                child: Icon(Icons.cancel, size: 16, color: muted),
              ),
          ],
        ),
      ),
      actions: [
        if (_matchIndices.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              decoration: BoxDecoration(
                color: pillBg,
                borderRadius: BorderRadius.circular(18),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(width: 8),
                  Text(
                    '${_currentMatchIdx + 1}/${_matchIndices.length}',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: muted,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.keyboard_arrow_up, size: 20),
                    color: muted,
                    onPressed: _prevMatch,
                  ),
                  IconButton(
                    icon: const Icon(Icons.keyboard_arrow_down, size: 20),
                    color: muted,
                    onPressed: _nextMatch,
                  ),
                ],
              ),
            ),
          )
        else if (_searchQuery.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Center(
              child: Text('无结果', style: TextStyle(fontSize: 12, color: muted)),
            ),
          ),
      ],
    );
  }

  void _exitSearch() {
    setState(() {
      _searchMode = false;
      _searchQuery = '';
      _searchCtrl.clear();
      _matchIndices = [];
      _currentMatchIdx = 0;
    });
  }

  // 只算命中集合并定位到最后一条（最新），不自己 setState——调用方负责刷新
  void _updateMatches() {
    if (_searchQuery.isEmpty) {
      _matchIndices = [];
      _currentMatchIdx = 0;
      return;
    }
    final q = _searchQuery.toLowerCase();
    final indices = <int>[];
    for (var i = 0; i < _messages.length; i++) {
      if (_messages[i].content.toLowerCase().contains(q)) indices.add(i);
    }
    _matchIndices = indices;
    _currentMatchIdx = indices.isNotEmpty ? indices.length - 1 : 0;
    if (indices.isNotEmpty) _scrollToIndex(indices.last);
  }

  void _nextMatch() {
    if (_matchIndices.isEmpty) return;
    setState(() {
      _currentMatchIdx = (_currentMatchIdx + 1) % _matchIndices.length;
    });
    _scrollToIndex(_matchIndices[_currentMatchIdx]);
  }

  void _prevMatch() {
    if (_matchIndices.isEmpty) return;
    setState(() {
      _currentMatchIdx =
          (_currentMatchIdx - 1 + _matchIndices.length) % _matchIndices.length;
    });
    _scrollToIndex(_matchIndices[_currentMatchIdx]);
  }

  GlobalKey _keyForIndex(int index) =>
      _itemKeys.putIfAbsent(index, () => GlobalKey());

  // ensureVisible 只能定位已经 build 出来的 item（可见/临近可见），群聊消息
  // 不多时够用。放到下一帧执行，保证刚 setState 出来的 key 已经挂上 context
  void _scrollToIndex(int index) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = _itemKeys[index]?.currentContext;
      if (ctx == null) return;
      Scrollable.ensureVisible(
        ctx,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
        alignment: 0.3,
      );
    });
  }

  Widget _buildEmptyMessages(bool isDark) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.chat_bubble_outline,
            size: 48,
            color: isDark ? Colors.white24 : Colors.grey.shade300,
          ),
          const SizedBox(height: 12),
          Text(
            '还没有消息，快来说点什么吧',
            style: TextStyle(
              fontSize: 14,
              color: isDark ? Colors.white38 : Colors.grey.shade500,
            ),
          ),
        ],
      ),
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

        final isMatch = _searchQuery.isNotEmpty && _matchIndices.contains(i);
        final isCurrent =
            _matchIndices.isNotEmpty &&
            _currentMatchIdx < _matchIndices.length &&
            _matchIndices[_currentMatchIdx] == i;

        return Container(
          key: _keyForIndex(i),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (showDate) _buildDateDivider(msg.createdAt, isDark),
              _buildMsgRow(
                msg,
                showSender,
                isDark,
                isMatch: isMatch,
                isCurrent: isCurrent,
              ),
            ],
          ),
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

  Widget _buildMsgRow(
    GroupMessage msg,
    bool showSender,
    bool isDark, {
    bool isMatch = false,
    bool isCurrent = false,
  }) {
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
                _buildMsgContent(
                  msg,
                  showSender,
                  isDark,
                  isMatch: isMatch,
                  isCurrent: isCurrent,
                ),
                const SizedBox(width: 8),
                _buildAvatar(msg, isDark),
              ]
            : [
                _buildAvatar(msg, isDark),
                const SizedBox(width: 8),
                _buildMsgContent(
                  msg,
                  showSender,
                  isDark,
                  isMatch: isMatch,
                  isCurrent: isCurrent,
                ),
              ],
      ),
    );
  }

  // 群聊里要能一眼分清不同成员，跟私信/通知列表统一用 kMessagesPrimary
  // 单色兜底的 buildMessageAvatar 不是同一个需求——真实头像走同一套
  // 图片渲染逻辑，没有头像时按 senderId 哈希取一个稳定的颜色区分成员
  Widget _buildAvatar(GroupMessage msg, bool isDark) {
    final avatar = msg.senderAvatar;
    final Widget inner = (avatar != null && avatar.isNotEmpty)
        ? Container(
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
          )
        : _initialAvatar(msg);
    // 点头像进对方个人主页——跟私信/通知/文章流的头像交互一致，不然点了
    // 没反应会觉得断层。系统消息/无用户名的不是真实用户，不可点
    if (msg.senderId == 'system' || msg.senderName.isEmpty) return inner;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => context.push('/users/${msg.senderName}'),
      child: inner,
    );
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

  Widget _buildMsgContent(
    GroupMessage msg,
    bool showSender,
    bool isDark, {
    bool isMatch = false,
    bool isCurrent = false,
  }) {
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
          child: GestureDetector(
            // 长按自己发的、未撤回消息 → 复制/撤回菜单
            onLongPress: msg.isMe && !msg.isRecalled
                ? () => _showMessageMenu(msg)
                : null,
            child: msg.isRecalled
                ? _buildRecalledBubble(isDark)
                : switch (msg.type) {
                    GroupMessageType.text => _buildTextBubble(
                      msg,
                      isDark,
                      isMatch: isMatch,
                      isCurrent: isCurrent,
                    ),
                    GroupMessageType.image => _buildImageBubble(msg),
                    GroupMessageType.file => _buildFileBubble(msg, isDark),
                    GroupMessageType.code => _buildCodeBubble(msg),
                    GroupMessageType.formula => _buildFormulaBubble(
                      msg,
                      isDark,
                    ),
                    GroupMessageType.shareTutorial ||
                    GroupMessageType.shareQuestion => _buildShareCard(
                      msg,
                      isDark,
                    ),
                  },
          ),
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

  Widget _buildTextBubble(
    GroupMessage msg,
    bool isDark, {
    bool isMatch = false,
    bool isCurrent = false,
  }) {
    final isMe = msg.isMe;
    final radius = BorderRadius.only(
      topLeft: const Radius.circular(14),
      topRight: const Radius.circular(14),
      bottomLeft: isMe ? const Radius.circular(14) : const Radius.circular(4),
      bottomRight: isMe ? const Radius.circular(4) : const Radius.circular(14),
    );

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      // 当前定位到的命中气泡加一圈发光描边
      decoration: isCurrent
          ? BoxDecoration(
              borderRadius: radius,
              boxShadow: [
                BoxShadow(
                  color: _primary.withValues(alpha: 0.45),
                  blurRadius: 8,
                  spreadRadius: 1,
                ),
              ],
            )
          : null,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(
          color: isMe
              ? _primary
              : isDark
              ? Colors.white.withValues(alpha: 0.1)
              : Colors.white,
          borderRadius: radius,
          boxShadow: isMe || isCurrent
              ? null
              : [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
                    blurRadius: 4,
                    offset: const Offset(0, 1),
                  ),
                ],
        ),
        child: _searchQuery.isNotEmpty && isMatch
            ? _buildHighlightedText(msg.content, isMe, isDark)
            : _buildRichText(msg.content, isMe, isDark),
      ),
    );
  }

  // 把命中的关键词底色标出来；其余文字按普通气泡文字色走
  Widget _buildHighlightedText(String text, bool isMe, bool isDark) {
    final q = _searchQuery.toLowerCase();
    final lower = text.toLowerCase();
    final spans = <InlineSpan>[];
    var start = 0;
    while (true) {
      final idx = lower.indexOf(q, start);
      if (idx < 0) {
        spans.add(TextSpan(text: text.substring(start)));
        break;
      }
      if (idx > start) {
        spans.add(TextSpan(text: text.substring(start, idx)));
      }
      // 命中关键词统一用同一个黄色高亮——跟一线聊天/邮件产品的搜索高亮
      // 一致，不随气泡是"我发的"还是"对方发的"变色。之前"我发的"那一侧
      // 用半透明白叠在紫色气泡上，反差太弱，一眼看不出是命中词
      spans.add(
        TextSpan(
          text: text.substring(idx, idx + q.length),
          style: const TextStyle(
            backgroundColor: Color(0xFFFFF176),
            color: Color(0xFF1A1A1A),
            fontWeight: FontWeight.w600,
          ),
        ),
      );
      start = idx + q.length;
    }

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
          // isMe 之前是纯白透明度叠加，卡片本身就是整条消息气泡（没有像
          // 文字气泡那样再套一层 _primary 底色），结果是白字配白底/浅色
          // 背景，几乎看不清——换成实色调低透明度的靛蓝底，跟文字气泡
          // "我发的"用 _primary 系是同一个色系，但不会跟浅色页面背景
          // 融在一起
          color: isMe
              ? const Color(0xFF4F46E5).withValues(alpha: 0.15)
              : isDark
              ? Colors.white.withValues(alpha: 0.06)
              : const Color(0xFFF9F9FB),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isMe
                ? Colors.white.withValues(alpha: 0.3)
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
                          ? Colors.white.withValues(alpha: 0.6)
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

  Widget _buildRecalledBubble(bool isDark) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      child: Text(
        '此消息已撤回',
        style: TextStyle(
          fontSize: 12,
          fontStyle: FontStyle.italic,
          color: isDark
              ? Colors.white.withValues(alpha: 0.3)
              : Colors.grey[400],
        ),
      ),
    );
  }

  Widget _buildImageBubble(GroupMessage msg) {
    final url = (msg.metadata?['url'] as String?) ?? msg.content;
    return GestureDetector(
      onTap: () => _showImagePreview(url),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: CachedNetworkImage(
          imageUrl: url,
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

  Widget _buildFormulaBubble(GroupMessage msg, bool isDark) {
    final isMe = msg.isMe;
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
          topLeft: const Radius.circular(14),
          topRight: const Radius.circular(14),
          bottomLeft: Radius.circular(isMe ? 14 : 4),
          bottomRight: Radius.circular(isMe ? 4 : 14),
        ),
        border: isMe ? null : Border.all(color: Theme.of(context).dividerColor),
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

  Widget _buildCodeBubble(GroupMessage msg) {
    final language = (msg.metadata?['language'] as String?) ?? 'text';
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

  Widget _buildFileBubble(GroupMessage msg, bool isDark) {
    final isMe = msg.isMe;
    final filename = (msg.metadata?['filename'] as String?) ?? '文件';
    final size = (msg.metadata?['size'] as num?)?.toInt() ?? 0;
    return GestureDetector(
      onTap: () => _openLink((msg.metadata?['url'] as String?) ?? msg.content),
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
                color: (isMe ? Colors.white : _primary).withValues(alpha: 0.18),
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

  // 长按自己消息 → 复制/撤回菜单
  void _showMessageMenu(GroupMessage msg) {
    final ageMs = DateTime.now().millisecondsSinceEpoch - msg.createdAt;
    final canRecall = ageMs < 2 * 60 * 1000; // 2分钟内，跟后端一致
    final canCopy =
        msg.type == GroupMessageType.text || msg.type == GroupMessageType.code;
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
            if (canRecall)
              ListTile(
                leading: const Icon(
                  Icons.undo,
                  size: 20,
                  color: Color(0xFFEF4444),
                ),
                title: const Text(
                  '撤回消息',
                  style: TextStyle(color: Color(0xFFEF4444)),
                ),
                onTap: () {
                  Navigator.pop(ctx);
                  _recallMessage(msg);
                },
              )
            else
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 8, 16, 16),
                child: Text(
                  '超过2分钟无法撤回',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _recallMessage(GroupMessage msg) async {
    final res = await ref
        .read(apiClientProvider)
        .post('/auth/groups/${widget.groupId}/messages/${msg.id}/recall');
    if (!mounted) return;
    if (res.success) {
      setState(() {
        final i = _messages.indexWhere((m) => m.id == msg.id);
        if (i >= 0) _messages[i] = _copyRecalled(_messages[i]);
      });
    } else {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('撤回失败：${res.message ?? '请重试'}')));
    }
  }

  GroupMessage _copyRecalled(GroupMessage m) => GroupMessage(
    id: m.id,
    groupId: m.groupId,
    senderId: m.senderId,
    senderName: m.senderName,
    senderAvatar: m.senderAvatar,
    type: m.type,
    content: m.content,
    refId: m.refId,
    refTitle: m.refTitle,
    refMeta: m.refMeta,
    metadata: m.metadata,
    isRecalled: true,
    createdAt: m.createdAt,
    isMe: m.isMe,
  );

  // "+"面板——旧版是 showModalBottomSheet 弹窗，改成跟输入框同屏内联展开/
  // 收起（"+"图标本身旋转45度变"×"，不换图标），点面板里任意一项立即
  // 收起面板+发送，跟私信页 chat_screen.dart 的弹窗式菜单是两种不同交互，
  // 这里改用户体验反馈重做过
  void _closeAttachPanel() {
    if (_attachPanelOpen) setState(() => _attachPanelOpen = false);
  }

  void _toggleAttachPanel() {
    _focusNode.unfocus();
    setState(() => _attachPanelOpen = !_attachPanelOpen);
  }

  Widget _buildAttachPanel(bool isDark) {
    return AnimatedSize(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
      alignment: Alignment.topCenter,
      child: !_attachPanelOpen
          ? const SizedBox(width: double.infinity)
          : Container(
              width: double.infinity,
              color: Theme.of(context).cardColor,
              // 面板现在是输入栏下面的内联区块，不再是输入栏 SafeArea 里的
              // 弹窗——自己得再包一层 SafeArea(top:false)，不然最下面一排
              // 图标会被 iPhone 底部 Home 指示条盖住
              child: SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: [
                          _attachBtn(Icons.image, '图片', () {
                            _closeAttachPanel();
                            _sendImage();
                          }),
                          _attachBtn(Icons.camera_alt_outlined, '拍照', () {
                            _closeAttachPanel();
                            _sendImage(source: ImageSource.camera);
                          }),
                          _attachBtn(
                            Icons.insert_drive_file_outlined,
                            '文件',
                            () {
                              _closeAttachPanel();
                              // 发送文件（含音视频媒体）是 Pro 权益
                              if (!requirePro(context, ref, feature: '发送文件')) {
                                return;
                              }
                              _sendFile();
                            },
                          ),
                          _attachBtn(Icons.code, '代码', () {
                            _closeAttachPanel();
                            // 发送代码片段是 Pro 权益
                            if (!requirePro(context, ref, feature: '发送代码')) {
                              return;
                            }
                            _showCodeInput();
                          }),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: [
                          _attachBtn(Icons.functions, '公式', () {
                            _closeAttachPanel();
                            // 发送 LaTeX 公式是 Pro 权益
                            if (!requirePro(context, ref, feature: '发送公式')) {
                              return;
                            }
                            _showLatexInput();
                          }),
                          _attachBtn(Icons.article_outlined, '文章', () {
                            _closeAttachPanel();
                            _shareContent('share_tutorial');
                          }),
                          _attachBtn(Icons.help_outline, '问题', () {
                            _closeAttachPanel();
                            _shareContent('share_question');
                          }),
                        ],
                      ),
                    ],
                  ),
                ),
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
      // 输入栏跟正文（米白 #FAFAF8）连成一块；深色仍用 cardColor
      color: isDark ? Theme.of(context).cardColor : const Color(0xFFFAFAF8),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              GestureDetector(
                onTap: _toggleAttachPanel,
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 5),
                  child: AnimatedRotation(
                    turns: _attachPanelOpen ? 0.125 : 0,
                    duration: const Duration(milliseconds: 200),
                    child: const Icon(
                      Icons.add_circle_outline,
                      size: 26,
                      color: Colors.grey,
                    ),
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
