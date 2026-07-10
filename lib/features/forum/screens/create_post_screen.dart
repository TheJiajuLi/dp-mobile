import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_client.dart';

const _primary = Color(0xFF6366F1);

class CreatePostScreen extends ConsumerStatefulWidget {
  final String forumId;
  const CreatePostScreen({super.key, required this.forumId});

  @override
  ConsumerState<CreatePostScreen> createState() => _CreatePostScreenState();
}

class _CreatePostScreenState extends ConsumerState<CreatePostScreen> {
  final _titleCtrl = TextEditingController();
  final _contentCtrl = TextEditingController();
  final Set<String> _selectedTags = {};
  bool _submitting = false;

  static const _allTags = ['数学', '编程', 'AI', '数据分析', '物理', '科普'];

  @override
  void dispose() {
    _titleCtrl.dispose();
    _contentCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_titleCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('请输入标题')));
      return;
    }
    if (_contentCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('请输入内容')));
      return;
    }

    setState(() => _submitting = true);
    final res = await ref
        .read(apiClientProvider)
        .post(
          '/auth/forums/${widget.forumId}/posts',
          data: {
            'title': _titleCtrl.text.trim(),
            'content': _contentCtrl.text.trim(),
            'tags': _selectedTags.toList(),
          },
        );
    if (!mounted) return;
    if (res.success) {
      context.pop(res.data is Map ? (res.data as Map)['post'] : null);
    } else {
      setState(() => _submitting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('发布失败：${res.message ?? '请稍后重试'}')),
      );
    }
  }

  Widget _fieldLabel(String text, bool isDark) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.4,
          color: isDark
              ? Colors.white.withValues(alpha: 0.35)
              : Colors.grey[400],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final canSubmit =
        _titleCtrl.text.trim().isNotEmpty &&
        _contentCtrl.text.trim().isNotEmpty;
    final cardBorder = Border.all(
      color: isDark
          ? Colors.white.withValues(alpha: 0.08)
          : const Color(0xFFEBEBEB),
      width: 0.5,
    );

    return Scaffold(
      // 跟建群页同一套"产品感"背景——不用纯白/纯黑，跟卡片的 cardColor
      // 拉开一点层次
      backgroundColor: isDark ? const Color(0xFF0A0A1A) : const Color(0xFFFAFAF8),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close, size: 18),
          onPressed: () => context.pop(),
        ),
        title: const Text(
          '发帖',
          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
        ),
        centerTitle: true,
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: TextButton(
              onPressed: (_submitting || !canSubmit) ? null : _submit,
              style: TextButton.styleFrom(
                backgroundColor: canSubmit
                    ? _primary
                    : const Color(0xFFE5E5E5),
                foregroundColor: Colors.white,
                disabledForegroundColor: Colors.grey[400],
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
                      '发布',
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
        padding: const EdgeInsets.all(14),
        children: [
          // 标题 + 标签放一张卡片里，跟发布页的"元信息卡片"一个思路——
          // 两个字段之间用一条发丝线隔开，而不是各自散落在背景上
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Theme.of(context).cardColor,
              borderRadius: BorderRadius.circular(14),
              border: cardBorder,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: _titleCtrl,
                  onChanged: (_) => setState(() {}),
                  maxLength: 100,
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: '标题（必填）',
                    hintStyle: TextStyle(
                      fontSize: 17,
                      color: isDark
                          ? Colors.white.withValues(alpha: 0.3)
                          : Colors.grey[400],
                      fontWeight: FontWeight.w500,
                    ),
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.zero,
                    counterText: '',
                  ),
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                    color: isDark
                        ? Colors.white.withValues(alpha: 0.9)
                        : const Color(0xFF1A1A1A),
                  ),
                ),
                const SizedBox(height: 12),
                Divider(
                  height: 0.5,
                  color: isDark
                      ? Theme.of(context).dividerColor
                      : const Color(0xFFF5F5F5),
                ),
                const SizedBox(height: 12),
                _fieldLabel('话题标签 · 最多3个', isDark),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    ..._allTags.map((tag) {
                      final isOn = _selectedTags.contains(tag);
                      return GestureDetector(
                        onTap: () => setState(() {
                          if (isOn) {
                            _selectedTags.remove(tag);
                          } else if (_selectedTags.length < 3) {
                            _selectedTags.add(tag);
                          }
                        }),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 11,
                            vertical: 5,
                          ),
                          decoration: BoxDecoration(
                            color: isOn
                                ? (isDark
                                      ? _primary.withValues(alpha: 0.15)
                                      : const Color(0xFFEEF0FF))
                                : (isDark
                                      ? Colors.white.withValues(alpha: 0.05)
                                      : Colors.white),
                            borderRadius: BorderRadius.circular(99),
                            border: Border.all(
                              color: isOn
                                  ? _primary
                                  : (isDark
                                        ? Colors.white.withValues(alpha: 0.1)
                                        : const Color(0xFFEBEBEB)),
                              width: 0.5,
                            ),
                          ),
                          child: Text(
                            tag,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: isOn ? FontWeight.w500 : FontWeight.normal,
                              color: isOn
                                  ? _primary
                                  : (isDark
                                        ? Colors.white.withValues(alpha: 0.5)
                                        : Colors.grey[500]),
                            ),
                          ),
                        ),
                      );
                    }),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),

          // 正文单独一张卡片，撑满剩余空间——跟标题/标签那张卡片视觉上
          // 是两个独立区块，不是同一张卡片里越写越长
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Theme.of(context).cardColor,
              borderRadius: BorderRadius.circular(14),
              border: cardBorder,
            ),
            child: TextField(
              controller: _contentCtrl,
              onChanged: (_) => setState(() {}),
              maxLines: null,
              minLines: 10,
              decoration: InputDecoration(
                isDense: true,
                hintText: '写下你的内容...',
                hintStyle: TextStyle(
                  fontSize: 14,
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.3)
                      : Colors.grey[400],
                ),
                border: InputBorder.none,
                contentPadding: EdgeInsets.zero,
              ),
              style: TextStyle(
                fontSize: 14,
                color: isDark
                    ? Colors.white.withValues(alpha: 0.9)
                    : const Color(0xFF444444),
                height: 1.8,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
