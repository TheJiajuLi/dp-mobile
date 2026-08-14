import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_client.dart';
import '../../../shared/widgets/app_toast.dart';
import '../../../shared/widgets/confirm_dialog.dart';
import '../../../shared/widgets/input_dialog.dart';
import '../../../shared/widgets/online_dot.dart';
import '../../auth/auth_service.dart';
import '../../messages/utils/message_avatar.dart';
import '../models/group_model.dart';

const _primary = AppColors.primary;
const _ownerColor = Color(0xFFF59E0B);
const _danger = Color(0xFFEF4444);

// 群设置页——纯 UI，数据（group / members / myRole）全部由群聊页通过 extra
// 传入，本页不发任何网络请求。群主的改名/改简介/设管理员/踢人、成员的退群/
// 群主的解散，目前都只做本地乐观更新 + 二次确认弹窗；后端 /auth/groups 接口
// 上线后，在各个 _on... 回调里补上真实调用即可（已用注释标出）
class GroupSettingsScreen extends ConsumerStatefulWidget {
  final String groupId;
  final GroupModel? group;
  final List<Map<String, dynamic>> members;
  final String myRole; // owner / admin / member

  const GroupSettingsScreen({
    super.key,
    required this.groupId,
    this.group,
    this.members = const [],
    this.myRole = 'member',
  });

  @override
  ConsumerState<GroupSettingsScreen> createState() =>
      _GroupSettingsScreenState();
}

class _GroupSettingsScreenState extends ConsumerState<GroupSettingsScreen> {
  late String _name;
  late String _desc;
  late String _avatar;
  late List<String> _tags;
  late List<Map<String, dynamic>> _members;

  bool get _isOwner => widget.myRole == 'owner';
  bool get _isAdmin => widget.myRole == 'admin' || _isOwner;
  String get _myId => ref.read(currentUserProvider)?.id ?? '';

  // 跟建群页同一套预设标签
  static const _presetTags = [
    '数学',
    '编程',
    '天体物理',
    '经济',
    '生命科学',
    '科普',
    '数据分析',
    'AI',
  ];

  @override
  void initState() {
    super.initState();
    _name = widget.group?.name ?? '群组';
    _desc = widget.group?.description ?? '';
    _avatar = widget.group?.avatar ?? '';
    _tags = List<String>.from(widget.group?.tags ?? const []);
    // 拷一份可变副本，本页的踢人/设管理员直接改它，不动传入的原始列表
    _members = widget.members.map((m) => Map<String, dynamic>.from(m)).toList();
    _sortMembers();
  }

  // 群主置顶、管理员其次、普通成员最后，保证角色标签自上而下排列整齐
  void _sortMembers() {
    int rank(String role) => switch (role) {
      'owner' => 0,
      'admin' => 1,
      _ => 2,
    };
    _members.sort(
      (a, b) => rank('${a['role']}').compareTo(rank('${b['role']}')),
    );
  }

  String _memberId(Map<String, dynamic> m) =>
      (m['id'] ?? m['user_id'] ?? '').toString();

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final bg = isDark
        ? Theme.of(context).scaffoldBackgroundColor
        : const Color(0xFFFAFAF8);

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        backgroundColor: bg,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, size: 18),
          onPressed: () => context.pop(),
        ),
        title: const Text(
          '群设置',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 32),
        children: [
          _buildHeader(isDark),
          const SizedBox(height: 16),
          _buildProfileCard(isDark),
          const SizedBox(height: 16),
          _buildMembersSection(isDark),
          const SizedBox(height: 24),
          _buildDangerButton(isDark),
        ],
      ),
    );
  }

  // ---- 顶部：头像 + 群名 + 成员数 ----
  Widget _buildHeader(bool isDark) {
    return Column(
      children: [
        Container(
          width: 72,
          height: 72,
          decoration: const BoxDecoration(
            color: _primary,
            shape: BoxShape.circle,
          ),
          clipBehavior: Clip.antiAlias,
          child: _avatar.isNotEmpty
              ? Image.network(
                  _avatar,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => _avatarFallback(),
                )
              : _avatarFallback(),
        ),
        const SizedBox(height: 12),
        Text(
          _name,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 4),
        Text(
          '${_members.length} 名成员',
          style: TextStyle(fontSize: 12, color: Colors.grey[500]),
        ),
      ],
    );
  }

  Widget _avatarFallback() => Center(
    child: Text(
      _name.isNotEmpty ? _name.substring(0, 1) : 'G',
      style: const TextStyle(
        fontSize: 28,
        fontWeight: FontWeight.w700,
        color: Colors.white,
      ),
    ),
  );

  // ---- 群资料：名称 / 简介（群主可编辑，其余只读）----
  Widget _buildProfileCard(bool isDark) {
    return _card(
      isDark,
      child: Column(
        children: [
          _profileRow(
            isDark,
            label: '群名称',
            value: _name,
            editable: _isOwner,
            onTap: () => _editField(
              title: '修改群名称',
              initial: _name,
              maxLength: 20,
              onSave: (v) => setState(() => _name = v),
            ),
          ),
          Divider(
            height: 0.5,
            indent: 16,
            color: Theme.of(context).dividerColor,
          ),
          _profileRow(
            isDark,
            label: '群简介',
            value: _desc.isEmpty ? '这个群组还没有简介' : _desc,
            valueMuted: _desc.isEmpty,
            editable: _isOwner,
            onTap: () => _editField(
              title: '修改群简介',
              initial: _desc,
              maxLength: 200,
              maxLines: 4,
              onSave: (v) => setState(() => _desc = v),
            ),
          ),
          Divider(
            height: 0.5,
            indent: 16,
            color: Theme.of(context).dividerColor,
          ),
          _tagsRow(isDark),
        ],
      ),
    );
  }

  // 话题标签行——群主可点进去增删（本地），非群主只读展示
  Widget _tagsRow(bool isDark) {
    return InkWell(
      onTap: _isOwner ? _editTags : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 64,
              child: Text(
                '话题标签',
                style: TextStyle(fontSize: 14, color: Colors.grey[500]),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _tags.isEmpty
                  ? Text(
                      '未设置',
                      style: TextStyle(fontSize: 14, color: Colors.grey[400]),
                    )
                  : Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: _tags.map((t) {
                        return Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: _primary.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            t,
                            style: const TextStyle(
                              fontSize: 12,
                              color: _primary,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        );
                      }).toList(),
                    ),
            ),
            if (_isOwner) ...[
              const SizedBox(width: 8),
              Icon(Icons.chevron_right, size: 18, color: Colors.grey[400]),
            ],
          ],
        ),
      ),
    );
  }

  Widget _profileRow(
    bool isDark, {
    required String label,
    required String value,
    bool valueMuted = false,
    required bool editable,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: editable ? onTap : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 64,
              child: Text(
                label,
                style: TextStyle(fontSize: 14, color: Colors.grey[500]),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                value,
                style: TextStyle(
                  fontSize: 14,
                  color: valueMuted
                      ? Colors.grey[400]
                      : (isDark ? Colors.white : const Color(0xFF1A1A1A)),
                ),
              ),
            ),
            if (editable) ...[
              const SizedBox(width: 8),
              Icon(Icons.chevron_right, size: 18, color: Colors.grey[400]),
            ],
          ],
        ),
      ),
    );
  }

  // ---- 成员列表 ----
  Widget _buildMembersSection(bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 0, 4, 6),
          child: Text(
            '群成员 · ${_members.length}',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Colors.grey[500],
            ),
          ),
        ),
        _card(
          isDark,
          child: Column(
            children: [
              // 邀请新成员——群主/管理员可见
              if (_isAdmin) ...[
                _inviteRow(isDark),
                Divider(
                  height: 0.5,
                  indent: 64,
                  color: Theme.of(context).dividerColor,
                ),
              ],
              for (var i = 0; i < _members.length; i++) ...[
                if (i > 0)
                  Divider(
                    height: 0.5,
                    indent: 64,
                    color: Theme.of(context).dividerColor,
                  ),
                _memberRow(isDark, _members[i]),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _inviteRow(bool isDark) {
    return InkWell(
      onTap: () => _snack('邀请新成员即将上线'),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: _primary.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.person_add_alt_1,
                size: 20,
                color: _primary,
              ),
            ),
            const SizedBox(width: 12),
            const Text(
              '邀请新成员',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: _primary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _memberRow(bool isDark, Map<String, dynamic> m) {
    final username = (m['username'] as String?) ?? '成员';
    final role = '${m['role'] ?? 'member'}';
    final id = _memberId(m);
    final isMe = id.isNotEmpty && id == _myId;
    // 群主能对「非群主、非自己」的成员做管理操作
    final canManage = _isOwner && role != 'owner' && !isMe;
    final canOpenProfile = username.isNotEmpty && !isMe;
    void openProfile() => context.push('/users/$username');

    return InkWell(
      // 可管理的成员：点行=管理菜单；其余：点行=进对方主页（跟点头像一致，
      // 不然点了名字没反应会觉得断层）
      onTap: canManage
          ? () => _showMemberActions(m)
          : (canOpenProfile ? openProfile : null),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            // 头像永远点进对方主页——即便是可管理的成员，头像也走主页，
            // 管理入口留给行/⋯（子级手势优先命中，不会误触发行的管理菜单）
            GestureDetector(
              onTap: canOpenProfile ? openProfile : null,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  buildMessageAvatar(
                    m['avatar'] as String?,
                    username,
                    radius: 20,
                  ),
                  Positioned(
                    bottom: 0,
                    right: 0,
                    child: OnlineDot(
                      lastSeenAt: (m['last_seen_at'] as num?)?.toInt(),
                      size: 9,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Row(
                children: [
                  Flexible(
                    child: Text(
                      isMe ? '$username（我）' : username,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: isDark ? Colors.white : const Color(0xFF1A1A1A),
                      ),
                    ),
                  ),
                  if (role == 'owner' || role == 'admin') ...[
                    const SizedBox(width: 8),
                    _roleTag(role),
                  ],
                ],
              ),
            ),
            if (canManage)
              Icon(Icons.more_horiz, size: 20, color: Colors.grey[400]),
          ],
        ),
      ),
    );
  }

  Widget _roleTag(String role) {
    final isOwner = role == 'owner';
    final color = isOwner ? _ownerColor : _primary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        isOwner ? '群主' : '管理员',
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }

  // ---- 底部危险操作：群主=解散，其余=退出 ----
  Widget _buildDangerButton(bool isDark) {
    final label = _isOwner ? '解散群组' : '退出群组';
    return GestureDetector(
      onTap: _isOwner ? _onDissolve : _onExit,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: isDark ? _danger.withValues(alpha: 0.12) : Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: _danger.withValues(alpha: isDark ? 0.3 : 0.2),
            width: 0.5,
          ),
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: _danger,
          ),
        ),
      ),
    );
  }

  // ---------------- 交互 ----------------

  // 群主点某个成员 → 底部弹出「设/取消管理员」「移出群聊」
  void _showMemberActions(Map<String, dynamic> m) {
    final username = (m['username'] as String?) ?? '成员';
    final role = '${m['role'] ?? 'member'}';
    final isAdmin = role == 'admin';

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
            const SizedBox(height: 12),
            Text(
              username,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            const Divider(height: 1),
            ListTile(
              leading: Icon(
                isAdmin
                    ? Icons.remove_moderator_outlined
                    : Icons.shield_outlined,
                size: 22,
                color: _primary,
              ),
              title: Text(isAdmin ? '取消管理员' : '设为管理员'),
              onTap: () {
                Navigator.pop(ctx);
                _onToggleAdmin(m);
              },
            ),
            ListTile(
              leading: const Icon(
                Icons.person_remove_outlined,
                size: 22,
                color: _danger,
              ),
              title: const Text('移出群聊', style: TextStyle(color: _danger)),
              onTap: () {
                Navigator.pop(ctx);
                _onKick(m);
              },
            ),
          ],
        ),
      ),
    );
  }

  void _onToggleAdmin(Map<String, dynamic> m) {
    final isAdmin = '${m['role']}' == 'admin';
    // TODO(接口上线): POST /auth/groups/:id/members/:uid/role
    setState(() {
      m['role'] = isAdmin ? 'member' : 'admin';
      _sortMembers();
    });
    _snack(isAdmin ? '已取消管理员' : '已设为管理员');
  }

  Future<void> _onKick(Map<String, dynamic> m) async {
    final username = (m['username'] as String?) ?? '该成员';
    final ok = await _confirm(
      title: '移出成员',
      message: '确定将「$username」移出群聊？',
      confirmLabel: '移出',
    );
    if (!ok || !mounted) return;
    // TODO(接口上线): DELETE /auth/groups/:id/members/:uid
    setState(() => _members.removeWhere((e) => _memberId(e) == _memberId(m)));
    _snack('已将「$username」移出群聊');
  }

  // 群主编辑话题标签——底部弹层里增删，最多 5 个，本地生效
  Future<void> _editTags() async {
    final working = List<String>.from(_tags);
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).cardColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        final isDark = Theme.of(ctx).brightness == Brightness.dark;
        return StatefulBuilder(
          builder: (ctx, setSheet) {
            void toggle(String t) {
              if (working.contains(t)) {
                setSheet(() => working.remove(t));
              } else if (working.length < 5) {
                setSheet(() => working.add(t));
              }
            }

            // 预设 + 已选里的自定义标签，去重后统一渲染成可点选的 chip
            final all = <String>[..._presetTags];
            for (final t in working) {
              if (!all.contains(t)) all.add(t);
            }

            return Padding(
              padding: EdgeInsets.fromLTRB(
                16,
                16,
                16,
                MediaQuery.of(ctx).viewInsets.bottom + 24,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Text(
                        '话题标签',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        '${working.length}/5',
                        style: TextStyle(fontSize: 12, color: Colors.grey[500]),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '点击选择，再次点击移除；最多 5 个',
                    style: TextStyle(fontSize: 12, color: Colors.grey[500]),
                  ),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      ...all.map((t) {
                        final on = working.contains(t);
                        return GestureDetector(
                          onTap: () => toggle(t),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: on
                                  ? _primary.withValues(alpha: 0.12)
                                  : (isDark
                                        ? Colors.white.withValues(alpha: 0.05)
                                        : Colors.white),
                              borderRadius: BorderRadius.circular(99),
                              border: Border.all(
                                color: on
                                    ? _primary
                                    : (isDark
                                          ? Colors.white.withValues(alpha: 0.1)
                                          : const Color(0xFFEBEBEB)),
                                width: 0.5,
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  t,
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: on
                                        ? FontWeight.w500
                                        : FontWeight.w400,
                                    color: on
                                        ? _primary
                                        : (isDark
                                              ? Colors.white.withValues(
                                                  alpha: 0.6,
                                                )
                                              : Colors.grey[600]),
                                  ),
                                ),
                                if (on) ...[
                                  const SizedBox(width: 4),
                                  const Icon(
                                    Icons.close,
                                    size: 13,
                                    color: _primary,
                                  ),
                                ],
                              ],
                            ),
                          ),
                        );
                      }),
                      if (working.length < 5)
                        GestureDetector(
                          onTap: () async {
                            final tag = await _promptCustomTag();
                            if (tag != null &&
                                tag.isNotEmpty &&
                                !working.contains(tag) &&
                                working.length < 5) {
                              setSheet(() => working.add(tag));
                            }
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(99),
                              border: Border.all(
                                color: _primary.withValues(alpha: 0.4),
                                width: 0.5,
                              ),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.add, size: 13, color: _primary),
                                SizedBox(width: 3),
                                Text(
                                  '自定义',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: _primary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  GestureDetector(
                    onTap: () {
                      // TODO(接口上线): PATCH /auth/groups/:id { tags }
                      setState(() => _tags = working);
                      Navigator.pop(ctx);
                      _snack('已更新话题标签');
                    },
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      decoration: BoxDecoration(
                        color: _primary,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Text(
                        '完成',
                        textAlign: TextAlign.center,
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
            );
          },
        );
      },
    );
  }

  Future<String?> _promptCustomTag() {
    return showInputDialog(
      context,
      title: '添加自定义标签',
      hint: '输入标签名称',
      maxLength: 10,
      confirmText: '添加',
    );
  }

  Future<void> _onDissolve() async {
    final ok = await _confirm(
      title: '解散群组',
      message: '解散后，群聊记录将被清空且无法恢复。确定解散「$_name」？',
      confirmLabel: '解散',
    );
    if (!ok || !mounted) return;
    // ApiClient 把 DioException 吞成 ApiResponse.error，不会抛异常——成功与否
    // 看 res.success。接口还没上线时会走到 else 分支给出失败提示，不会崩；
    // 后端补上 DELETE /auth/groups/:id 后自动生效，前端不用改
    final res = await ref
        .read(apiClientProvider)
        .delete('/auth/groups/${widget.groupId}');
    if (!mounted) return;
    if (res.success) {
      _snack('群组已解散');
      // 解散后群聊已不存在，回到消息 Tab，不再 pop 回那个空群聊页
      context.go('/messages');
    } else {
      _snack('解散失败：${res.message ?? '请稍后重试'}');
    }
  }

  Future<void> _onExit() async {
    final ok = await _confirm(
      title: '退出群组',
      message: '退出后将不再接收该群消息。确定退出「$_name」？',
      confirmLabel: '退出',
    );
    if (!ok || !mounted) return;
    final res = await ref
        .read(apiClientProvider)
        .post('/auth/groups/${widget.groupId}/leave', data: {});
    if (!mounted) return;
    if (res.success) {
      _snack('已退出群组');
      // 退出后不再回到那个已离开的群聊页，直接回消息 Tab
      context.go('/messages');
    } else {
      _snack('退出失败：${res.message ?? '请稍后重试'}');
    }
  }

  // ---- 通用弹窗/提示 ----

  Future<void> _editField({
    required String title,
    required String initial,
    required void Function(String) onSave,
    int maxLength = 50,
    int maxLines = 1,
  }) async {
    final result = await showInputDialog(
      context,
      title: title,
      initial: initial,
      maxLength: maxLength,
      maxLines: maxLines,
    );
    if (result == null || !mounted) return;
    // 群名称不能清空；群简介允许清空
    if (title.contains('名称') && result.isEmpty) return;
    onSave(result);
  }

  Future<bool> _confirm({
    required String title,
    required String message,
    required String confirmLabel,
  }) {
    // 群相关的确认基本都是危险/不可逆操作（解散/退出/移除），统一走全站的
    // 危险确认弹窗（红底警示图标 + 取消幽灵 / 红色实心确认）
    return showDangerConfirm(
      context,
      title: title,
      message: message,
      confirmText: confirmLabel,
    );
  }

  // 轻量提示统一走全站浮动圆角胶囊——失败/错误红、其余绿对勾
  void _snack(String msg) {
    final isError = msg.contains('失败') || msg.contains('错误');
    showAppToast(context, msg, ok: !isError);
  }

  Widget _card(bool isDark, {required Widget child}) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(16),
        border: isDark
            ? Border.all(color: Theme.of(context).dividerColor, width: 0.5)
            : null,
        boxShadow: isDark
            ? null
            : [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.03),
                  blurRadius: 10,
                  offset: const Offset(0, 3),
                ),
              ],
      ),
      clipBehavior: Clip.antiAlias,
      child: child,
    );
  }
}
