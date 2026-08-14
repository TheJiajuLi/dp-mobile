import 'dart:convert';
import '../../../core/theme/app_colors.dart';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../shared/widgets/app_toast.dart';

const _primary = AppColors.primary;

// 问题详情页「分享问题」——三选一：分享到论坛 / 群组 / 好友，各自二级选目标、
// 多选（论坛单选）、可加附言、确认发送。全部用真实后端端点：
//   论坛列表 GET /auth/forums、发帖 POST /auth/forums/:id/posts（只吃
//     {title, content}，链接塞进 content）
//   我的群组 GET /auth/groups、群消息 POST /auth/groups/:id/messages
//   互相关注的好友 GET /auth/friends、私信 POST /auth/messages（{toUserId,...}）
// 群/私信统一 type:'text'+链接进 content：现有聊天 UI 都能正常渲染，且私信
// 的陌生人限制对「首条非文字」会 403——好友虽是双向关注不受限，仍用 text 最稳。
void showQuestionShareSheet(
  BuildContext context,
  Map<String, dynamic> question,
) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _QuestionShareSheet(question: question),
  );
}

enum _Step { choose, forum, group, friend }

// 字母头像的浅底/深字配色，按列表下标轮换（跟截图的紫/绿/琥珀三色一致）
const _avatarPalette = [
  [AppColors.primaryLight, AppColors.primary],
  [Color(0xFFE7F8EF), AppColors.success],
  [Color(0xFFFEF3C7), Color(0xFFD97706)],
];

class _QuestionShareSheet extends ConsumerStatefulWidget {
  final Map<String, dynamic> question;
  const _QuestionShareSheet({required this.question});

  @override
  ConsumerState<_QuestionShareSheet> createState() =>
      _QuestionShareSheetState();
}

class _QuestionShareSheetState extends ConsumerState<_QuestionShareSheet> {
  _Step _step = _Step.choose;
  bool _loading = false;
  bool _sending = false;

  List<Map<String, dynamic>> _forums = [];
  List<Map<String, dynamic>> _groups = [];
  List<Map<String, dynamic>> _friends = [];

  String? _selectedForum;
  final Set<String> _selectedGroups = {};
  final Set<String> _selectedFriends = {};

  final _messageCtrl = TextEditingController();

  @override
  void dispose() {
    _messageCtrl.dispose();
    super.dispose();
  }

  String get _title => widget.question['text']?.toString() ?? '';
  String get _domain => widget.question['domain']?.toString() ?? '';
  int get _answerCount =>
      (widget.question['answer_count'] as num?)?.toInt() ?? 0;
  String get _link =>
      'https://dreamingpolar.com/question/${widget.question['id']}';

  // 附言（可空）+ 问题标题 + 链接。群/私信/论坛帖正文都用这份
  String _composeContent() {
    final note = _messageCtrl.text.trim();
    final buf = StringBuffer();
    if (note.isNotEmpty) buf.write('$note\n\n');
    buf.write('问题：$_title\n$_link');
    return buf.toString();
  }

  // 富卡片元数据——聊天里 type:'question_share' 消息靠这个渲染问题分享卡片。
  // content 仍带上文本+链接（会话列表最后一条预览、旧客户端向后兼容用）
  Map<String, dynamic> get _shareMetadata => {
    'questionId': widget.question['id']?.toString() ?? '',
    'title': _title,
    'tag': _domain,
    'answerCount': _answerCount,
  };

  String _firstLetter(Object? name) {
    final s = name?.toString() ?? '';
    return s.isEmpty ? '#' : s.substring(0, 1);
  }

  // 成功：先弹标准 toast（走上层 ScaffoldMessenger，pop sheet 后仍在），再关 sheet
  void _showSuccess(String msg) {
    if (!mounted) return;
    showAppToast(context, msg, ok: true);
    Navigator.pop(context);
  }

  void _showError(String msg) {
    if (!mounted) return;
    showAppToast(context, msg);
  }

  // ---------- 加载目标列表 ----------
  Future<void> _goForum() async {
    setState(() {
      _step = _Step.forum;
      _loading = true;
    });
    final res = await ref.read(apiClientProvider).get('/auth/forums');
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (res.success && res.data != null) {
        _forums = ((res.data['forums'] as List?) ?? [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
      }
    });
  }

  Future<void> _goGroup() async {
    setState(() {
      _step = _Step.group;
      _loading = true;
    });
    final res = await ref.read(apiClientProvider).get('/auth/groups');
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (res.success && res.data != null) {
        _groups = ((res.data['groups'] as List?) ?? [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
      }
    });
  }

  Future<void> _goFriend() async {
    setState(() {
      _step = _Step.friend;
      _loading = true;
    });
    // /auth/friends = 互相关注（双向）的好友，不是单向 following
    final res = await ref.read(apiClientProvider).get('/auth/friends');
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (res.success && res.data != null) {
        _friends = ((res.data['friends'] as List?) ?? [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
      }
    });
  }

  // ---------- 发送 ----------
  Future<void> _shareToForum() async {
    if (_selectedForum == null || _sending) return;
    setState(() => _sending = true);
    final res = await ref
        .read(apiClientProvider)
        .post(
          '/auth/forums/$_selectedForum/posts',
          data: {'title': _title, 'content': _composeContent()},
        );
    if (!mounted) return;
    setState(() => _sending = false);
    if (res.success) {
      _showSuccess('已分享到论坛');
    } else {
      _showError(res.message ?? '分享失败，请稍后重试');
    }
  }

  Future<void> _shareToGroups() async {
    if (_selectedGroups.isEmpty || _sending) return;
    setState(() => _sending = true);
    final content = _composeContent();
    var ok = 0;
    for (final id in _selectedGroups) {
      final res = await ref
          .read(apiClientProvider)
          .post(
            '/auth/groups/$id/messages',
            data: {
              // 群消息 model 认 'share_question'（私信认 'question_share'），
              // 各按各自 model 的命名，metadata 里带富卡片数据
              'type': 'share_question',
              'content': content,
              'metadata': _shareMetadata,
            },
          );
      if (res.success) ok++;
    }
    if (!mounted) return;
    setState(() => _sending = false);
    if (ok > 0) {
      _showSuccess('已发送到 $ok 个群组');
    } else {
      _showError('发送失败，请稍后重试');
    }
  }

  Future<void> _shareToFriends() async {
    if (_selectedFriends.isEmpty || _sending) return;
    setState(() => _sending = true);
    final content = _composeContent();
    var ok = 0;
    for (final id in _selectedFriends) {
      final res = await ref
          .read(apiClientProvider)
          .post(
            '/auth/messages',
            data: {
              'toUserId': id,
              'type': 'question_share',
              'content': content,
              'metadata': _shareMetadata,
            },
          );
      if (res.success) ok++;
    }
    if (!mounted) return;
    setState(() => _sending = false);
    if (ok > 0) {
      _showSuccess('已发送给 $ok 位好友');
    } else {
      _showError('发送失败，请稍后重试');
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final ink = isDark ? Colors.white : const Color(0xFF1A1A1A);
    final muted = isDark ? Colors.white54 : const Color(0xFF999999);
    final border = isDark
        ? Theme.of(context).dividerColor
        : const Color(0xFFEEEEEE);

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.8,
        ),
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
        ),
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 20),
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
            const SizedBox(height: 16),
            Flexible(child: _body(isDark, ink, muted, border)),
          ],
        ),
      ),
    );
  }

  Widget _body(bool isDark, Color ink, Color muted, Color border) {
    switch (_step) {
      case _Step.choose:
        return _chooseBody(ink, muted, border);
      case _Step.forum:
        return _targetBody(
          title: '选择版块',
          ink: ink,
          muted: muted,
          border: border,
          empty: _forums.isEmpty,
          emptyText: '还没有可分享的版块',
          list: [
            for (var i = 0; i < _forums.length; i++)
              _listItem(
                letter: _firstLetter(_forums[i]['name']),
                index: i,
                name: _forums[i]['name']?.toString() ?? '',
                sub: '${(_forums[i]['post_count'] as num?)?.toInt() ?? 0} 个帖子',
                selected: _selectedForum == _forums[i]['id']?.toString(),
                onTap: () => setState(
                  () => _selectedForum = _forums[i]['id']?.toString(),
                ),
                ink: ink,
                muted: muted,
                border: border,
              ),
          ],
          actionLabel: '分享到版块',
          actionEnabled: _selectedForum != null,
          onAction: _shareToForum,
        );
      case _Step.group:
        return _targetBody(
          title: '选择群组',
          ink: ink,
          muted: muted,
          border: border,
          empty: _groups.isEmpty,
          emptyText: '你还没有加入任何群组',
          list: [
            for (var i = 0; i < _groups.length; i++)
              _listItem(
                letter: _firstLetter(_groups[i]['name']),
                index: i,
                name: _groups[i]['name']?.toString() ?? '',
                sub:
                    '${(_groups[i]['member_count'] as num?)?.toInt() ?? 0} 位成员',
                selected: _selectedGroups.contains(
                  _groups[i]['id']?.toString(),
                ),
                onTap: () => _toggle(_selectedGroups, _groups[i]['id']),
                ink: ink,
                muted: muted,
                border: border,
              ),
          ],
          actionLabel: '发送到群组',
          actionEnabled: _selectedGroups.isNotEmpty,
          onAction: _shareToGroups,
        );
      case _Step.friend:
        return _targetBody(
          title: '选择好友',
          ink: ink,
          muted: muted,
          border: border,
          empty: _friends.isEmpty,
          emptyText: '还没有互相关注的好友',
          list: [
            for (var i = 0; i < _friends.length; i++)
              _listItem(
                avatarUrl: _friends[i]['avatar']?.toString(),
                letter: _firstLetter(_friends[i]['username']),
                index: i,
                name: _friends[i]['username']?.toString() ?? '',
                sub: '@${_friends[i]['handle']?.toString() ?? ''}',
                selected: _selectedFriends.contains(
                  _friends[i]['id']?.toString(),
                ),
                onTap: () => _toggle(_selectedFriends, _friends[i]['id']),
                ink: ink,
                muted: muted,
                border: border,
              ),
          ],
          actionLabel: '发送给好友',
          actionEnabled: _selectedFriends.isNotEmpty,
          onAction: _shareToFriends,
        );
    }
  }

  void _toggle(Set<String> set, Object? rawId) {
    final id = rawId?.toString();
    if (id == null) return;
    setState(() {
      if (set.contains(id)) {
        set.remove(id);
      } else {
        set.add(id);
      }
    });
  }

  Widget _chooseBody(Color ink, Color muted, Color border) {
    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '分享问题',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: ink,
            ),
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: border, width: 0.5),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('分享内容', style: TextStyle(fontSize: 11, color: muted)),
                const SizedBox(height: 6),
                Text(
                  _title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: ink,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '极梦社区${_domain.isNotEmpty ? ' · $_domain' : ''} · $_answerCount个回答',
                  style: TextStyle(fontSize: 12, color: muted),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Text('选择分享方式', style: TextStyle(fontSize: 12, color: muted)),
          const SizedBox(height: 10),
          _shareOption(
            iconBg: AppColors.primaryLight,
            icon: Icons.view_column_outlined,
            iconColor: AppColors.primary,
            label: '分享到论坛',
            sub: '发布到公开版块，所有人可见',
            onTap: _goForum,
            ink: ink,
            muted: muted,
            border: border,
          ),
          _shareOption(
            iconBg: const Color(0xFFF0FFF5),
            icon: Icons.group_outlined,
            iconColor: AppColors.success,
            label: '分享到群组',
            sub: '发送到你加入的群聊',
            onTap: _goGroup,
            ink: ink,
            muted: muted,
            border: border,
          ),
          _shareOption(
            iconBg: const Color(0xFFFEF3C7),
            icon: Icons.chat_bubble_outline,
            iconColor: const Color(0xFFD97706),
            label: '发送给好友',
            sub: '私信给互相关注的好友',
            onTap: _goFriend,
            ink: ink,
            muted: muted,
            border: border,
          ),
          const SizedBox(height: 6),
          SizedBox(
            width: double.infinity,
            child: TextButton(
              onPressed: () => Navigator.pop(context),
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                  side: BorderSide(color: border, width: 0.5),
                ),
              ),
              child: Text('取消', style: TextStyle(fontSize: 14, color: muted)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _targetBody({
    required String title,
    required Color ink,
    required Color muted,
    required Color border,
    required bool empty,
    required String emptyText,
    required List<Widget> list,
    required String actionLabel,
    required bool actionEnabled,
    required VoidCallback onAction,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final ctaBg = isDark ? _primary : const Color(0xFF1A1A1A);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: ink,
          ),
        ),
        const SizedBox(height: 12),
        Flexible(
          child: _loading
              ? const Padding(
                  padding: EdgeInsets.symmetric(vertical: 40),
                  child: Center(
                    child: CircularProgressIndicator(color: _primary),
                  ),
                )
              : empty
              ? Padding(
                  padding: const EdgeInsets.symmetric(vertical: 40),
                  child: Center(
                    child: Text(
                      emptyText,
                      style: TextStyle(fontSize: 13, color: muted),
                    ),
                  ),
                )
              : ListView(shrinkWrap: true, children: list),
        ),
        const SizedBox(height: 12),
        Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: border, width: 0.5),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: TextField(
            controller: _messageCtrl,
            minLines: 1,
            maxLines: 2,
            style: TextStyle(fontSize: 13, color: ink),
            decoration: InputDecoration(
              filled: false,
              border: InputBorder.none,
              isCollapsed: true,
              contentPadding: const EdgeInsets.symmetric(vertical: 12),
              hintText: '添加附言（选填）',
              hintStyle: TextStyle(fontSize: 13, color: muted),
            ),
          ),
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: _sending
                    ? null
                    : () => setState(() => _step = _Step.choose),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  side: BorderSide(color: border),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                child: Text('返回', style: TextStyle(color: muted)),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: FilledButton(
                onPressed: (actionEnabled && !_sending) ? onAction : null,
                style: FilledButton.styleFrom(
                  backgroundColor: ctaBg,
                  // 显式给白字——深色模式 ctaBg 是紫、浅色是近黑，不给的话
                  // FilledButton 默认前景色在深色下会算成暗色，白底紫按钮上
                  // 「发送到群组」几乎看不清
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                child: _sending
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : Text(
                        actionLabel,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _shareOption({
    required Color iconBg,
    required IconData icon,
    required Color iconColor,
    required String label,
    required String sub,
    required VoidCallback onTap,
    required Color ink,
    required Color muted,
    required Color border,
  }) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: border, width: 0.5),
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: iconBg,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: iconColor, size: 22),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: ink,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(sub, style: TextStyle(fontSize: 12, color: muted)),
                ],
              ),
            ),
            Icon(Icons.chevron_right, size: 20, color: muted),
          ],
        ),
      ),
    );
  }

  Widget _listItem({
    String? avatarUrl,
    required String letter,
    required int index,
    required String name,
    required String sub,
    required bool selected,
    required VoidCallback onTap,
    required Color ink,
    required Color muted,
    required Color border,
  }) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 11),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: border, width: 0.5)),
        ),
        child: Row(
          children: [
            _avatarCircle(url: avatarUrl, letter: letter, index: index),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: ink,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    sub,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 11, color: muted),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Container(
              width: 20,
              height: 20,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: selected ? _primary : Colors.transparent,
                border: Border.all(
                  color: selected ? _primary : border,
                  width: 1.5,
                ),
              ),
              child: selected
                  ? const Icon(Icons.check, size: 12, color: Colors.white)
                  : null,
            ),
          ],
        ),
      ),
    );
  }

  // 头像：好友有 avatar（COS URL 或历史 base64，都兼容），版块/群组无头像走
  // 首字母彩底圈；解析失败也回落到首字母
  Widget _avatarCircle({
    String? url,
    required String letter,
    required int index,
  }) {
    final pair = _avatarPalette[index % _avatarPalette.length];
    ImageProvider? img;
    if (url != null && url.isNotEmpty) {
      if (url.startsWith('data:image')) {
        try {
          img = MemoryImage(base64Decode(url.split(',').last));
        } catch (_) {}
      } else if (url.startsWith('http')) {
        img = NetworkImage(url);
      }
    }
    return CircleAvatar(
      radius: 18,
      backgroundColor: pair[0],
      backgroundImage: img,
      child: img == null
          ? Text(
              letter,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: pair[1],
              ),
            )
          : null,
    );
  }
}
