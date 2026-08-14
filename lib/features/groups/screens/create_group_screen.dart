import 'dart:io';
import '../../../core/theme/app_colors.dart';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/network/api_client.dart';
import '../../auth/auth_service.dart';
import '../../messages/utils/message_avatar.dart';
import '../../profile/models/user_profile_model.dart';
import '../models/group_model.dart';

const _primary = AppColors.primary;

// 后端还没有 /auth/groups 相关接口（POST 建群/POST 邀请成员），这个页面
// 调用的是真实的 ApiClient，不是编个假的成功——后端补上接口之前，点
// "创建"会拿到一个失败的 ApiResponse，走下面 else 分支的错误提示，不会
// 假装成功跳到第三步。Step 1/2 的表单本身（校验/标签多选/成员多选）
// 现在就能正常操作
class CreateGroupScreen extends ConsumerStatefulWidget {
  const CreateGroupScreen({super.key});

  @override
  ConsumerState<CreateGroupScreen> createState() => _CreateGroupScreenState();
}

class _CreateGroupScreenState extends ConsumerState<CreateGroupScreen> {
  int _step = 1; // 1=基础信息 2=邀请成员

  final _nameCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  bool _isPublic = true;
  String _joinType = 'free';
  final Set<String> _selectedTags = {};
  static const _allTags = [
    '数学',
    '编程',
    '天体物理',
    '经济',
    '生命科学',
    '科普',
    '数据分析',
    'AI',
  ];

  List<UserProfile> _following = [];
  final Set<String> _selectedUserIds = {};
  bool _loadingFollowing = false;
  final _searchCtrl = TextEditingController();
  String _query = '';

  bool _submitting = false;
  GroupModel? _createdGroup;

  // 群头像——本地选中的文件。群头像上传接口还没有，这里只做本地预览，
  // 建群 payload 暂不带 avatar；接口就绪后先上传拿 URL 再一起提交
  File? _avatarFile;

  bool get _step1Valid => _nameCtrl.text.trim().length >= 2;

  List<UserProfile> get _filteredFollowing {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return _following;
    return _following
        .where((u) => u.username.toLowerCase().contains(q))
        .toList();
  }

  @override
  void initState() {
    super.initState();
    _nameCtrl.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _descCtrl.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadFollowing() async {
    if (_following.isNotEmpty || _loadingFollowing) return;
    setState(() => _loadingFollowing = true);
    final userId = ref.read(currentUserProvider)?.id;
    if (userId == null) {
      setState(() => _loadingFollowing = false);
      return;
    }
    final res = await ref
        .read(apiClientProvider)
        .get('/auth/users/$userId/following');
    if (!mounted) return;
    setState(() {
      _loadingFollowing = false;
      if (res.success && res.data != null) {
        _following = ((res.data['following'] as List?) ?? [])
            .map(
              (j) => UserProfile.fromJson(Map<String, dynamic>.from(j as Map)),
            )
            .toList();
      }
    });
  }

  Future<void> _submit() async {
    if (_submitting) return;
    setState(() => _submitting = true);
    final api = ref.read(apiClientProvider);

    // TODO(文件上传接口就绪): 先把 _avatarFile 上传拿到 URL，再加进下面的
    // data['avatar']；目前群头像只本地预览，不随建群提交
    final res = await api.post(
      '/auth/groups',
      data: {
        'name': _nameCtrl.text.trim(),
        if (_descCtrl.text.trim().isNotEmpty)
          'description': _descCtrl.text.trim(),
        'is_public': _isPublic,
        'join_type': _joinType,
        'tags': _selectedTags.toList(),
      },
    );
    if (!mounted) return;
    if (!res.success || res.data == null) {
      setState(() => _submitting = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(res.message ?? '创建失败，请稍后重试')));
      return;
    }

    final group = GroupModel.fromJson(
      Map<String, dynamic>.from(res.data['group'] as Map),
    );

    if (_selectedUserIds.isNotEmpty) {
      // 群已经建成功了，邀请这一步失败不该拖累整个创建流程失败——群主
      // 进群之后本来就能再手动邀一次，静默失败即可，不额外弹错误
      await api.post(
        '/auth/groups/${group.id}/invite',
        data: {'user_ids': _selectedUserIds.toList()},
      );
    }

    setState(() {
      _submitting = false;
      _createdGroup = group;
    });
  }

  Future<void> _pickAvatar() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 512,
      maxHeight: 512,
      imageQuality: 85,
    );
    if (picked == null || !mounted) return;
    setState(() => _avatarFile = File(picked.path));
  }

  Widget _buildAvatar() {
    return GestureDetector(
      onTap: _pickAvatar,
      child: Container(
        width: 76,
        height: 76,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: _avatarFile == null
              ? const LinearGradient(
                  colors: [Color(0xFFEEF0FF), Color(0xFFE0E7FF)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                )
              : null,
          image: _avatarFile != null
              ? DecorationImage(
                  image: FileImage(_avatarFile!),
                  fit: BoxFit.cover,
                )
              : null,
          border: Border.all(
            color: _primary.withValues(alpha: 0.3),
            width: 2,
            strokeAlign: BorderSide.strokeAlignOutside,
          ),
        ),
        child: Stack(
          children: [
            if (_avatarFile == null)
              const Center(
                child: Icon(Icons.groups_outlined, size: 30, color: _primary),
              ),
            Positioned(
              bottom: 0,
              right: 0,
              child: Container(
                width: 22,
                height: 22,
                decoration: const BoxDecoration(
                  color: _primary,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.edit, size: 12, color: Colors.white),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // 话题标签：预设标签 + 自定义添加 + 点选中的可删除，最多 5 个
  Widget _buildTagSection(bool isDark, Color labelColor) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _fieldLabel('话题标签（最多5个）', labelColor),
        // 已选标签——点一下即删除
        if (_selectedTags.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              children: _selectedTags.map((tag) {
                return GestureDetector(
                  onTap: () => setState(() => _selectedTags.remove(tag)),
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(10, 5, 6, 5),
                    decoration: BoxDecoration(
                      color: _primary.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(99),
                      border: Border.all(color: _primary, width: 0.5),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          tag,
                          style: const TextStyle(
                            fontSize: 12,
                            color: _primary,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(width: 4),
                        const Icon(Icons.close, size: 13, color: _primary),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        // 预设（未选的）+「自定义」按钮
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            ..._allTags.where((t) => !_selectedTags.contains(t)).map((tag) {
              return GestureDetector(
                onTap: () {
                  if (_selectedTags.length >= 5) return;
                  setState(() => _selectedTags.add(tag));
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: isDark
                        ? Colors.white.withValues(alpha: 0.05)
                        : Colors.white,
                    borderRadius: BorderRadius.circular(99),
                    border: Border.all(
                      color: isDark
                          ? Colors.white.withValues(alpha: 0.1)
                          : const Color(0xFFEBEBEB),
                      width: 0.5,
                    ),
                  ),
                  child: Text(
                    tag,
                    style: TextStyle(
                      fontSize: 12,
                      color: isDark
                          ? Colors.white.withValues(alpha: 0.5)
                          : Colors.grey[600],
                    ),
                  ),
                ),
              );
            }),
            if (_selectedTags.length < 5)
              GestureDetector(
                onTap: _addCustomTag,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 5,
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
                        style: TextStyle(fontSize: 12, color: _primary),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }

  Future<void> _addCustomTag() async {
    final ctrl = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('添加自定义标签'),
        content: TextField(
          controller: ctrl,
          maxLength: 10,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: '输入标签名称',
            counterText: '',
          ),
          onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: const Text('添加'),
          ),
        ],
      ),
    );
    ctrl.dispose();
    if (result != null &&
        result.isNotEmpty &&
        !_selectedTags.contains(result) &&
        _selectedTags.length < 5) {
      setState(() => _selectedTags.add(result));
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (_createdGroup != null) {
      return _buildSuccessPage(isDark);
    }

    return Scaffold(
      backgroundColor: isDark
          ? const Color(0xFF0A0A1A)
          : const Color(0xFFFAFAF8),
      appBar: _buildAppBar(isDark),
      body: Column(
        children: [
          _buildStepBar(isDark),
          Expanded(
            // 点空白处收起键盘
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => FocusScope.of(context).unfocus(),
              child: _step == 1 ? _buildStep1(isDark) : _buildStep2(isDark),
            ),
          ),
        ],
      ),
    );
  }

  PreferredSizeWidget _buildAppBar(bool isDark) {
    return AppBar(
      backgroundColor: Colors.transparent,
      elevation: 0,
      leading: IconButton(
        icon: Icon(_step == 1 ? Icons.close : Icons.arrow_back_ios, size: 18),
        onPressed: _step == 1
            ? () => context.pop()
            : () => setState(() => _step = 1),
      ),
      title: Text(
        _step == 1 ? '建群' : '邀请成员',
        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
      ),
      actions: [
        Padding(
          padding: const EdgeInsets.only(right: 12),
          child: _step == 1
              ? TextButton(
                  onPressed: _step1Valid
                      ? () {
                          setState(() => _step = 2);
                          _loadFollowing();
                        }
                      : null,
                  style: TextButton.styleFrom(
                    backgroundColor: _step1Valid
                        ? const Color(0xFF1A1A1A)
                        : const Color(0xFFE5E5E5),
                    foregroundColor: _step1Valid
                        ? Colors.white
                        : Colors.grey[400],
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 6,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(99),
                    ),
                  ),
                  child: const Text(
                    '下一步',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                  ),
                )
              : TextButton(
                  onPressed: _submitting ? null : _submit,
                  style: TextButton.styleFrom(
                    backgroundColor: _primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 6,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(99),
                    ),
                  ),
                  child: _submitting
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                            strokeWidth: 1.5,
                            color: Colors.white,
                          ),
                        )
                      : const Text(
                          '创建',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                ),
        ),
      ],
    );
  }

  Widget _buildStepBar(bool isDark) {
    final divColor = isDark
        ? Colors.white.withValues(alpha: 0.08)
        : const Color(0xFFEBEBEB);

    Widget dot(int n, String label) {
      final isDone = _step > n || _createdGroup != null;
      final isNow = _step == n && _createdGroup == null;
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 250),
            width: 22,
            height: 22,
            decoration: BoxDecoration(
              color: isDone
                  ? AppColors.success
                  : isNow
                  ? _primary
                  : isDark
                  ? Colors.white.withValues(alpha: 0.1)
                  : const Color(0xFFF0F0F0),
              shape: BoxShape.circle,
              border: (!isDone && !isNow)
                  ? Border.all(color: divColor, width: 1.5)
                  : null,
            ),
            child: Center(
              child: isDone
                  ? const Icon(Icons.check, size: 12, color: Colors.white)
                  : Text(
                      '$n',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: isNow
                            ? Colors.white
                            : isDark
                            ? Colors.white.withValues(alpha: 0.3)
                            : Colors.grey[400],
                      ),
                    ),
            ),
          ),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              fontWeight: (isDone || isNow) ? FontWeight.w500 : FontWeight.w400,
              color: isDone
                  ? AppColors.success
                  : isNow
                  ? _primary
                  : isDark
                  ? Colors.white.withValues(alpha: 0.3)
                  : Colors.grey[400],
            ),
          ),
        ],
      );
    }

    Widget line(bool done) => Expanded(
      child: Container(
        height: 1,
        margin: const EdgeInsets.symmetric(horizontal: 6),
        color: done ? AppColors.success : divColor,
      ),
    );

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: divColor, width: 0.5)),
      ),
      child: Row(
        children: [
          dot(1, '基础信息'),
          line(_step > 1),
          dot(2, '邀请成员'),
          line(_createdGroup != null),
          dot(3, '完成'),
        ],
      ),
    );
  }

  Widget _buildStep1(bool isDark) {
    final fieldBg = isDark
        ? Colors.white.withValues(alpha: 0.05)
        : Colors.white;
    final borderColor = isDark
        ? Colors.white.withValues(alpha: 0.08)
        : const Color(0xFFEBEBEB);
    final labelColor = isDark
        ? Colors.white.withValues(alpha: 0.4)
        : Colors.grey[500]!;

    InputDecoration fieldDecoration(String hint) => InputDecoration(
      hintText: hint,
      hintStyle: TextStyle(
        color: isDark ? Colors.white.withValues(alpha: 0.2) : Colors.grey[400],
      ),
      filled: true,
      fillColor: fieldBg,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: borderColor, width: 0.5),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: borderColor, width: 0.5),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: _primary, width: 0.5),
      ),
      counterText: '',
      contentPadding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
    );

    return ListView(
      padding: const EdgeInsets.only(bottom: 32),
      children: [
        Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 20),
            child: Column(
              children: [
                _buildAvatar(),
                const SizedBox(height: 8),
                Text(
                  '点击设置群头像（可选）',
                  style: TextStyle(fontSize: 11, color: labelColor),
                ),
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _fieldLabel('群名称', labelColor, required: true),
              TextField(
                controller: _nameCtrl,
                maxLength: 20,
                decoration: fieldDecoration('给你的群起个名字'),
                style: TextStyle(
                  fontSize: 14,
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.9)
                      : const Color(0xFF1A1A1A),
                ),
              ),
              const SizedBox(height: 14),
              _fieldLabel('群简介', labelColor),
              TextField(
                controller: _descCtrl,
                maxLength: 100,
                maxLines: 3,
                decoration: fieldDecoration('描述这个群的主题和目的（可选）'),
                style: TextStyle(
                  fontSize: 14,
                  height: 1.6,
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.9)
                      : const Color(0xFF1A1A1A),
                ),
              ),
              const SizedBox(height: 14),
              _fieldLabel('群类型', labelColor),
              Row(
                children: [
                  Expanded(
                    child: _TypeCard(
                      icon: Icons.public,
                      iconColor: _primary,
                      iconBg: const Color(0xFFEEF0FF),
                      title: '公开群',
                      desc: '任何人可搜索并申请加入',
                      selected: _isPublic,
                      isDark: isDark,
                      onTap: () => setState(() {
                        _isPublic = true;
                        _joinType = 'free';
                      }),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _TypeCard(
                      icon: Icons.lock_outline,
                      iconColor: Colors.grey[600]!,
                      iconBg: const Color(0xFFF5F5F5),
                      title: '私密群',
                      desc: '仅受邀成员可加入',
                      selected: !_isPublic,
                      isDark: isDark,
                      onTap: () => setState(() {
                        _isPublic = false;
                        _joinType = 'invite';
                      }),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              _buildTagSection(isDark, labelColor),
            ],
          ),
        ),
      ],
    );
  }

  Widget _fieldLabel(String text, Color color, {bool required = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 7),
      child: Row(
        children: [
          Text(
            text,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: color,
              letterSpacing: .04,
            ),
          ),
          if (required)
            const Text(
              ' *',
              style: TextStyle(color: Color(0xFFEF4444), fontSize: 11),
            ),
        ],
      ),
    );
  }

  Widget _buildStep2(bool isDark) {
    final borderColor = isDark
        ? Colors.white.withValues(alpha: 0.08)
        : const Color(0xFFEBEBEB);

    return Column(
      children: [
        Container(
          margin: const EdgeInsets.fromLTRB(12, 10, 12, 8),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          decoration: BoxDecoration(
            color: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: borderColor, width: 0.5),
          ),
          child: Row(
            children: [
              Icon(
                Icons.search,
                size: 16,
                color: isDark
                    ? Colors.white.withValues(alpha: 0.3)
                    : Colors.grey[400],
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _searchCtrl,
                  onChanged: (v) => setState(() => _query = v),
                  decoration: InputDecoration(
                    hintText: '搜索关注的用户',
                    hintStyle: TextStyle(
                      fontSize: 13,
                      color: isDark
                          ? Colors.white.withValues(alpha: 0.3)
                          : Colors.grey[400],
                    ),
                    border: InputBorder.none,
                    isDense: true,
                    contentPadding: EdgeInsets.zero,
                  ),
                  style: TextStyle(
                    fontSize: 13,
                    color: isDark
                        ? Colors.white.withValues(alpha: 0.9)
                        : const Color(0xFF1A1A1A),
                  ),
                ),
              ),
            ],
          ),
        ),
        if (_selectedUserIds.isNotEmpty)
          Container(
            height: 60,
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(color: borderColor, width: 0.5),
              ),
            ),
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              itemCount: _selectedUserIds.length,
              itemBuilder: (ctx, i) {
                final uid = _selectedUserIds.elementAt(i);
                UserProfile? user;
                for (final u in _following) {
                  if (u.id == uid) {
                    user = u;
                    break;
                  }
                }
                return GestureDetector(
                  onTap: () => setState(() => _selectedUserIds.remove(uid)),
                  child: Container(
                    margin: const EdgeInsets.only(right: 8),
                    child: Stack(
                      children: [
                        buildMessageAvatar(
                          user?.avatar,
                          user?.username ?? 'U',
                          radius: 18,
                        ),
                        Positioned(
                          top: 0,
                          right: 0,
                          child: Container(
                            width: 14,
                            height: 14,
                            decoration: const BoxDecoration(
                              color: Color(0xFFEF4444),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.close,
                              size: 9,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          )
        else
          Container(
            height: 44,
            alignment: Alignment.centerLeft,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(color: borderColor, width: 0.5),
              ),
            ),
            child: Text(
              '选择要邀请的成员（可跳过）',
              style: TextStyle(
                fontSize: 12,
                color: isDark
                    ? Colors.white.withValues(alpha: 0.3)
                    : Colors.grey[400],
              ),
            ),
          ),
        Expanded(
          child: _loadingFollowing
              ? const Center(child: CircularProgressIndicator())
              : _filteredFollowing.isEmpty
              ? Center(
                  child: Text(
                    _following.isEmpty ? '暂无关注的用户' : '没有找到匹配的用户',
                    style: TextStyle(
                      fontSize: 14,
                      color: isDark
                          ? Colors.white.withValues(alpha: 0.4)
                          : Colors.grey[400],
                    ),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  itemCount: _filteredFollowing.length,
                  itemBuilder: (ctx, i) {
                    final user = _filteredFollowing[i];
                    final isSelected = _selectedUserIds.contains(user.id);
                    return GestureDetector(
                      onTap: () => setState(() {
                        if (isSelected) {
                          _selectedUserIds.remove(user.id);
                        } else {
                          _selectedUserIds.add(user.id);
                        }
                      }),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        decoration: BoxDecoration(
                          border: Border(
                            bottom: BorderSide(color: borderColor, width: 0.5),
                          ),
                        ),
                        child: Row(
                          children: [
                            buildMessageAvatar(
                              user.avatar,
                              user.username,
                              radius: 18,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    user.username,
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w500,
                                      color: isDark
                                          ? Colors.white.withValues(alpha: 0.9)
                                          : const Color(0xFF1A1A1A),
                                    ),
                                  ),
                                  if (user.tags.isNotEmpty ||
                                      user.followerCount > 0)
                                    Text(
                                      [
                                        if (user.tags.isNotEmpty)
                                          user.tags.first,
                                        '${_formatCount(user.followerCount)} 关注者',
                                      ].join(' · '),
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: isDark
                                            ? Colors.white.withValues(
                                                alpha: 0.4,
                                              )
                                            : Colors.grey[500],
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                ],
                              ),
                            ),
                            AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              width: 22,
                              height: 22,
                              decoration: BoxDecoration(
                                color: isSelected
                                    ? _primary
                                    : Colors.transparent,
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: isSelected ? _primary : borderColor,
                                  width: 1.5,
                                ),
                              ),
                              child: isSelected
                                  ? const Icon(
                                      Icons.check,
                                      size: 13,
                                      color: Colors.white,
                                    )
                                  : null,
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  String _formatCount(int n) {
    if (n >= 10000) return '${(n / 10000).toStringAsFixed(1)}万';
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}k';
    return '$n';
  }

  Widget _buildSuccessPage(bool isDark) {
    return Scaffold(
      backgroundColor: isDark
          ? const Color(0xFF0A0A1A)
          : const Color(0xFFFAFAF8),
      body: SafeArea(
        child: Column(
          children: [
            _buildStepBar(isDark),
            Expanded(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(28),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 72,
                        height: 72,
                        decoration: const BoxDecoration(
                          color: Color(0xFFDCFCE7),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.check,
                          size: 34,
                          color: AppColors.success,
                        ),
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        '群组已创建 🎉',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _selectedUserIds.isEmpty
                            ? '你是群里唯一的成员，快去邀请好友吧'
                            : '已向 ${_selectedUserIds.length} 位成员发送邀请',
                        style: TextStyle(
                          fontSize: 13,
                          color: isDark
                              ? Colors.white.withValues(alpha: 0.5)
                              : Colors.grey[500],
                          height: 1.6,
                        ),
                      ),
                      const SizedBox(height: 24),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: isDark
                              ? Colors.white.withValues(alpha: 0.04)
                              : Colors.white,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: isDark
                                ? Colors.white.withValues(alpha: 0.08)
                                : const Color(0xFFEBEBEB),
                            width: 0.5,
                          ),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 44,
                              height: 44,
                              decoration: BoxDecoration(
                                gradient: const LinearGradient(
                                  colors: [
                                    Color(0xFFEEF0FF),
                                    Color(0xFFDDD6FE),
                                  ],
                                ),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Icon(
                                Icons.groups_outlined,
                                size: 22,
                                color: _primary,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _createdGroup!.name,
                                  style: const TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                Text(
                                  '${_createdGroup!.isPublic ? "公开群" : "私密群"} · 1 名成员',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: isDark
                                        ? Colors.white.withValues(alpha: 0.4)
                                        : Colors.grey[500],
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),
                      SizedBox(
                        width: double.infinity,
                        height: 50,
                        child: ElevatedButton(
                          onPressed: () => context.pushReplacement(
                            '/group/${_createdGroup!.id}',
                            extra: {
                              'name': _createdGroup!.name,
                              'memberCount': _createdGroup!.memberCount,
                            },
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _primary,
                            foregroundColor: Colors.white,
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: const Text(
                            '进入群聊',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      TextButton(
                        onPressed: () => context.go('/messages'),
                        child: Text(
                          '稍后再说',
                          style: TextStyle(
                            fontSize: 13,
                            color: isDark
                                ? Colors.white.withValues(alpha: 0.4)
                                : Colors.grey[400],
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
    );
  }
}

class _TypeCard extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final Color iconBg;
  final String title;
  final String desc;
  final bool selected;
  final bool isDark;
  final VoidCallback onTap;

  const _TypeCard({
    required this.icon,
    required this.iconColor,
    required this.iconBg,
    required this.title,
    required this.desc,
    required this.selected,
    required this.isDark,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: selected
              ? _primary.withValues(alpha: 0.08)
              : isDark
              ? Colors.white.withValues(alpha: 0.04)
              : Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected
                ? _primary
                : isDark
                ? Colors.white.withValues(alpha: 0.08)
                : const Color(0xFFEBEBEB),
            width: 0.5,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: iconBg,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(icon, size: 15, color: iconColor),
                ),
                const SizedBox(width: 7),
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: selected
                        ? _primary
                        : isDark
                        ? Colors.white.withValues(alpha: 0.9)
                        : const Color(0xFF1A1A1A),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 5),
            Text(
              desc,
              style: TextStyle(
                fontSize: 11,
                height: 1.4,
                color: selected
                    ? _primary.withValues(alpha: 0.7)
                    : isDark
                    ? Colors.white.withValues(alpha: 0.35)
                    : Colors.grey[500]!,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
