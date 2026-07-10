import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_client.dart';

const _primary = Color(0xFF6366F1);

// 建论坛——POST /auth/forums 是真实接口（name/description/tags），但
// forums 表没有 avatar/color 字段（createForum 的 INSERT 语句里没有这一
// 列），所以这里的渐变色只是创建时的本地取色器，纯展示用，不会随创建
// 请求提交、也不会保存下来——AllForumsScreen/ForumHomeScreen 之后看到
// 的这个论坛头像用的是它们各自的默认配色，不会跟这里选的颜色同步。
// 没有做单独的"创建成功页"：创建成功直接 pushReplacement 进论坛主页，
// 新论坛的名称/标签在那边就是从刚创建的真实数据里来的，不需要再摆一层
// 复述界面
class CreateForumScreen extends ConsumerStatefulWidget {
  const CreateForumScreen({super.key});

  @override
  ConsumerState<CreateForumScreen> createState() =>
      _CreateForumScreenState();
}

class _CreateForumScreenState extends ConsumerState<CreateForumScreen> {
  final _nameCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _customTagCtrl = TextEditingController();
  final Set<String> _selectedTags = {};
  bool _submitting = false;
  int _colorIdx = 0;

  static const _gradients = [
    [Color(0xFF6366F1), Color(0xFF8B5CF6)],
    [Color(0xFF16A34A), Color(0xFF0891B2)],
    [Color(0xFFD97706), Color(0xFFEF4444)],
    [Color(0xFFEC4899), Color(0xFF8B5CF6)],
    [Color(0xFF0891B2), Color(0xFF6366F1)],
    [Color(0xFFEF4444), Color(0xFFD97706)],
  ];

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

  List<Color> get _currentGradient => _gradients[_colorIdx];

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
    final res = await ref.read(apiClientProvider).post(
      '/auth/forums',
      data: {
        'name': _nameCtrl.text.trim(),
        if (_descCtrl.text.trim().isNotEmpty)
          'description': _descCtrl.text.trim(),
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
      body: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 20),
              child: Column(
                children: [
                  GestureDetector(
                    onTap: () => setState(
                      () => _colorIdx = (_colorIdx + 1) % _gradients.length,
                    ),
                    child: Stack(
                      children: [
                        Container(
                          width: 76,
                          height: 76,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [c1, c2],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Center(
                            child: Text(
                              name.isNotEmpty ? name[0] : '论',
                              style: TextStyle(
                                fontSize: 28,
                                fontWeight: FontWeight.w700,
                                color: name.isNotEmpty
                                    ? Colors.white
                                    : Colors.white.withValues(alpha: 0.4),
                              ),
                            ),
                          ),
                        ),
                        Positioned(
                          bottom: -3,
                          right: -3,
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
                              Icons.edit,
                              size: 11,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '点击更换颜色',
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
    color: isDark ? Colors.white.withValues(alpha: 0.9) : const Color(0xFF1A1A1A),
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
