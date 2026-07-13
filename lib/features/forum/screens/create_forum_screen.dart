import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/network/api_client.dart';
import '../../../shared/utils/forum_gradient.dart';

const _primary = Color(0xFF6366F1);

// 建论坛——POST /auth/forums 是真实接口（name/description/tags/
// color_index）。color_index（0-5，对应 forumGradients 的下标）会随创建
// 请求一起提交、真实存进 forums 表，AllForumsScreen/ForumHomeScreen 头像
// 用的是同一份 shared/utils/forum_gradient.dart 取色，三处保持一致
//
// 封面图上传：create_group_screen.dart 的头像上传其实是个没做完的
// TODO——只有 ImagePicker 本地预览，没有真的传到服务器（注释里写着"等
// 文件上传接口就绪"），并不是能直接照抄的参考实现。这里改用
// cover_picker_sheet.dart（文章封面）同款的真实、通用文件上传接口
// POST /auth/files/upload，不是 /auth/update-avatar——后者是"更新当前
// 登录用户自己头像"的专用接口（固定覆盖 avatars/{userId}.jpg，改用户
// 表），拿来传论坛封面会把创建者自己的头像也顶掉，是个真实的坑，不能照
// 用户建议里"完全复用建群页逻辑"字面去接错接口
//
// 已知缺口：forums 表目前没有 avatar 列，POST /auth/forums 的
// controller 只解构 name/description/tags/color_index，传 avatar 字段
// 会被后端安静丢弃，不会报错也不会存下来——图片上传本身是真的（能拿到
// 真实 COS URL），但这个 URL 创建成功后不会持久化，刷新/重进论坛主页
// 就没了。跟 color_index 当初的情况一样，Flutter 这边先把接口和读取
// 都接好，等后端加上 forums.avatar 列（连带 getForums/getForum 的
// SELECT）之后不需要再改一行 Flutter 代码
//
// 没有做单独的"创建成功页"：创建成功直接 pushReplacement 进论坛主页，
// 新论坛的名称/标签/头像颜色在那边就是从刚创建的真实数据里来的，不需要
// 再摆一层复述界面
class CreateForumScreen extends ConsumerStatefulWidget {
  const CreateForumScreen({super.key});

  @override
  ConsumerState<CreateForumScreen> createState() => _CreateForumScreenState();
}

class _CreateForumScreenState extends ConsumerState<CreateForumScreen> {
  final _nameCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _customTagCtrl = TextEditingController();
  final Set<String> _selectedTags = {};
  bool _submitting = false;
  int _colorIdx = 0;
  String? _avatarUrl;
  bool _uploadingAvatar = false;

  static const _presetTags = [
    '数学',
    '编程',
    'AI',
    '数据分析',
    '物理',
    '科普',
    '统计',
    '生命科学',
    '经济',
    '天体物理',
  ];

  bool get _canSubmit => _nameCtrl.text.trim().length >= 2;

  List<Color> get _currentGradient => forumGradientFor(_colorIdx);

  @override
  void initState() {
    super.initState();
    _nameCtrl.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _descCtrl.dispose();
    _customTagCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_canSubmit || _submitting) return;
    setState(() => _submitting = true);
    final res = await ref
        .read(apiClientProvider)
        .post(
          '/auth/forums',
          data: {
            'name': _nameCtrl.text.trim(),
            if (_descCtrl.text.trim().isNotEmpty)
              'description': _descCtrl.text.trim(),
            'tags': _selectedTags.toList(),
            'color_index': _colorIdx,
            // 后端 forums 表目前没有 avatar 列，这个字段现在会被安静丢弃——
            // 先传上，等后端加了列不用再改 Flutter
            if (_avatarUrl != null) 'avatar': _avatarUrl,
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

    final forumId = (res.data['forum'] as Map?)?['id']?.toString();
    if (forumId == null || forumId.isEmpty) {
      setState(() => _submitting = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('创建失败，请稍后重试')));
      return;
    }
    context.pushReplacement('/forum-home/$forumId');
  }

  // 跟 cover_picker_sheet.dart（文章封面）同一套真实上传逻辑——头像形状
  // 是方形圆角图标，不是文章封面那种宽幅 banner，裁剪尺寸改成 512x512
  // 跟 create_group_screen.dart 头像选图时用的尺寸一致
  Future<void> _pickAvatarImage() async {
    final picker = ImagePicker();
    final file = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 512,
      maxHeight: 512,
      imageQuality: 85,
    );
    if (file == null || !mounted) return;
    setState(() => _uploadingAvatar = true);
    final bytes = await file.readAsBytes();
    final formData = FormData.fromMap({
      'file': MultipartFile.fromBytes(
        bytes,
        filename: 'forum_cover.jpg',
        contentType: DioMediaType('image', 'jpeg'),
      ),
    });
    final res = await ref
        .read(apiClientProvider)
        .post('/auth/files/upload', data: formData);
    if (!mounted) return;
    setState(() => _uploadingAvatar = false);
    if (!res.success || res.data == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(res.message ?? '上传失败，请稍后重试')));
      return;
    }
    final url = (res.data as Map)['url'] as String?;
    if (url != null) setState(() => _avatarUrl = url);
  }

  void _addCustomTag() {
    final tag = _customTagCtrl.text.trim();
    if (tag.isEmpty) return;
    if (_selectedTags.length >= 3) return;
    setState(() {
      _selectedTags.add(tag);
      _customTagCtrl.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final name = _nameCtrl.text.trim();
    final [c1, c2] = _currentGradient;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close, size: 20),
          onPressed: () => context.pop(),
        ),
        title: const Text(
          '建论坛',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: TextButton(
              onPressed: _canSubmit && !_submitting ? _submit : null,
              style: TextButton.styleFrom(
                backgroundColor: _canSubmit
                    ? _primary
                    : const Color(0xFFE5E5E5),
                foregroundColor: Colors.white,
                disabledForegroundColor: Colors.grey[400],
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 7,
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
      ),
      // 点空白处收起键盘
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => FocusScope.of(context).unfocus(),
        child: ListView(
          padding: const EdgeInsets.only(bottom: 32),
          children: [
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 20),
                child: Column(
                  children: [
                    Stack(
                      children: [
                        GestureDetector(
                          // 点头像本体循环换渐变色——上传了封面图之后颜色
                          // 会被图片盖住看不见，但继续点也不出错，就是
                          // 悄悄换了个不会显示的底色，不需要为此加额外
                          // 状态去禁用它
                          onTap: () => setState(
                            () => _colorIdx =
                                (_colorIdx + 1) % forumGradients.length,
                          ),
                          child: Container(
                            width: 76,
                            height: 76,
                            decoration: BoxDecoration(
                              gradient: _avatarUrl == null
                                  ? LinearGradient(
                                      colors: [c1, c2],
                                      begin: Alignment.topLeft,
                                      end: Alignment.bottomRight,
                                    )
                                  : null,
                              image: _avatarUrl != null
                                  ? DecorationImage(
                                      image: NetworkImage(_avatarUrl!),
                                      fit: BoxFit.cover,
                                    )
                                  : null,
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: _avatarUrl != null
                                ? null
                                : Center(
                                    child: Text(
                                      name.isNotEmpty ? name[0] : '论',
                                      style: TextStyle(
                                        fontSize: 28,
                                        fontWeight: FontWeight.w700,
                                        color: name.isNotEmpty
                                            ? Colors.white
                                            : Colors.white.withValues(
                                                alpha: 0.4,
                                              ),
                                      ),
                                    ),
                                  ),
                          ),
                        ),
                        if (_uploadingAvatar)
                          Positioned.fill(
                            child: Container(
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.35),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: const Center(
                                child: SizedBox(
                                  width: 22,
                                  height: 22,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        Positioned(
                          bottom: -3,
                          right: -3,
                          child: GestureDetector(
                            onTap: _uploadingAvatar ? null : _pickAvatarImage,
                            child: Container(
                              width: 22,
                              height: 22,
                              decoration: BoxDecoration(
                                color: _primary,
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: isDark
                                      ? const Color(0xFF1C1C1E)
                                      : Colors.white,
                                  width: 2,
                                ),
                              ),
                              child: const Icon(
                                Icons.camera_alt,
                                size: 11,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _avatarUrl == null ? '点击头像换色 · 点相机传封面图' : '点相机重新上传',
                      style: TextStyle(fontSize: 11, color: Colors.grey[400]),
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
                  const _Label('论坛名称', required: true),
                  TextField(
                    controller: _nameCtrl,
                    maxLength: 20,
                    decoration: _inputDeco('给你的论坛取个名字', isDark),
                    style: _inputStyle(isDark),
                  ),
                  const SizedBox(height: 14),
                  const _Label('论坛简介'),
                  TextField(
                    controller: _descCtrl,
                    maxLength: 100,
                    maxLines: 3,
                    decoration: _inputDeco('介绍一下这个论坛的主题（可选）', isDark),
                    style: _inputStyle(isDark),
                  ),
                  const SizedBox(height: 14),
                  const _Label('话题标签（最多3个）'),
                  if (_selectedTags.isNotEmpty) ...[
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: _selectedTags
                          .map(
                            (tag) => _SelectedTag(
                              tag: tag,
                              onRemove: () =>
                                  setState(() => _selectedTags.remove(tag)),
                            ),
                          )
                          .toList(),
                    ),
                    const SizedBox(height: 8),
                  ],
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: _presetTags
                        .where((t) => !_selectedTags.contains(t))
                        .map(
                          (tag) => GestureDetector(
                            onTap: _selectedTags.length < 3
                                ? () => setState(() => _selectedTags.add(tag))
                                : null,
                            child: AnimatedOpacity(
                              duration: const Duration(milliseconds: 150),
                              opacity: _selectedTags.length >= 3 ? 0.35 : 1.0,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 5,
                                ),
                                decoration: BoxDecoration(
                                  color: isDark
                                      ? Colors.white.withValues(alpha: 0.05)
                                      : const Color(0xFFF5F5F5),
                                  borderRadius: BorderRadius.circular(99),
                                  border: Border.all(
                                    color: isDark
                                        ? Colors.white.withValues(alpha: 0.1)
                                        : const Color(0xFFE0E0E0),
                                    width: 0.5,
                                  ),
                                ),
                                child: Text(
                                  tag,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: isDark
                                        ? Colors.white.withValues(alpha: 0.5)
                                        : const Color(0xFF555555),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        )
                        .toList(),
                  ),
                  const SizedBox(height: 8),
                  if (_selectedTags.length < 3)
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _customTagCtrl,
                            maxLength: 10,
                            decoration: InputDecoration(
                              hintText: '自定义标签...',
                              hintStyle: TextStyle(
                                fontSize: 12,
                                color: isDark
                                    ? Colors.white.withValues(alpha: 0.25)
                                    : Colors.grey[400],
                              ),
                              filled: false,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                                borderSide: BorderSide(
                                  color: isDark
                                      ? Colors.white.withValues(alpha: 0.1)
                                      : const Color(0xFFEBEBEB),
                                  width: 0.5,
                                ),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                                borderSide: const BorderSide(
                                  color: _primary,
                                  width: 0.5,
                                ),
                              ),
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 8,
                              ),
                              counterText: '',
                              isDense: true,
                            ),
                            style: TextStyle(
                              fontSize: 12,
                              color: isDark
                                  ? Colors.white.withValues(alpha: 0.9)
                                  : const Color(0xFF1A1A1A),
                            ),
                            onSubmitted: (_) => _addCustomTag(),
                          ),
                        ),
                        const SizedBox(width: 7),
                        GestureDetector(
                          onTap: _addCustomTag,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 9,
                            ),
                            decoration: BoxDecoration(
                              color: _primary,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Text(
                              '添加',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.white,
                                fontWeight: FontWeight.w500,
                              ),
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
      ),
    );
  }

  InputDecoration _inputDeco(String hint, bool isDark) => InputDecoration(
    hintText: hint,
    hintStyle: TextStyle(
      fontSize: 14,
      color: isDark ? Colors.white.withValues(alpha: 0.2) : Colors.grey[400],
    ),
    filled: true,
    fillColor: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.white,
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: BorderSide(
        color: isDark
            ? Colors.white.withValues(alpha: 0.08)
            : const Color(0xFFEBEBEB),
        width: 0.5,
      ),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: BorderSide(
        color: isDark
            ? Colors.white.withValues(alpha: 0.08)
            : const Color(0xFFEBEBEB),
        width: 0.5,
      ),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: const BorderSide(color: _primary, width: 0.5),
    ),
    counterText: '',
    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
  );

  TextStyle _inputStyle(bool isDark) => TextStyle(
    fontSize: 14,
    color: isDark
        ? Colors.white.withValues(alpha: 0.9)
        : const Color(0xFF1A1A1A),
  );
}

class _SelectedTag extends StatelessWidget {
  final String tag;
  final VoidCallback onRemove;
  const _SelectedTag({required this.tag, required this.onRemove});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.fromLTRB(10, 5, 6, 5),
    decoration: BoxDecoration(
      color: const Color(0xFFEEF0FF),
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
            fontWeight: FontWeight.w500,
            color: _primary,
          ),
        ),
        const SizedBox(width: 4),
        GestureDetector(
          onTap: onRemove,
          child: Container(
            width: 14,
            height: 14,
            decoration: BoxDecoration(
              color: _primary.withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.close, size: 9, color: _primary),
          ),
        ),
      ],
    ),
  );
}

class _Label extends StatelessWidget {
  final String text;
  final bool required;
  const _Label(this.text, {this.required = false});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 7),
    child: Row(
      children: [
        Text(
          text,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w500,
            color: Colors.grey[500],
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
