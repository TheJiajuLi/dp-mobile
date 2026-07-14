import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_client.dart';

const _primary = Color(0xFF6366F1);

class CreatePostScreen extends ConsumerStatefulWidget {
  final String forumId;
  final List<String> forumTags;
  const CreatePostScreen({
    super.key,
    required this.forumId,
    this.forumTags = const [],
  });

  @override
  ConsumerState<CreatePostScreen> createState() => _CreatePostScreenState();
}

class _CreatePostScreenState extends ConsumerState<CreatePostScreen> {
  final _titleCtrl = TextEditingController();
  final _contentCtrl = TextEditingController();
  final _customCtrl = TextEditingController();
  final Set<String> _selectedTags = {};
  final _customFocus = FocusNode();
  bool _submitting = false;

  // 预设标签优先用论坛自己的标签；没传就退回一组通用标签
  List<String> get _presetTags => widget.forumTags.isNotEmpty
      ? widget.forumTags
      : const ['数学', '编程', 'AI', '数据分析', '物理', '科普', '统计', '机器学习'];

  @override
  void initState() {
    super.initState();
    // 自定义标签输入框聚焦时切换边框/图标高亮，focus 变化要重建
    _customFocus.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _contentCtrl.dispose();
    _customCtrl.dispose();
    _customFocus.dispose();
    super.dispose();
  }

  // 自定义标签：回车（onSubmitted 传入 val）或点"添加"（无参）都走这里
  void _addCustomTag([String? val]) {
    final tag = (val ?? _customCtrl.text).trim();
    if (tag.isEmpty || _selectedTags.length >= 3) return;
    if (!_selectedTags.contains(tag)) {
      setState(() => _selectedTags.add(tag));
    }
    _customCtrl.clear();
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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('发布失败：${res.message ?? '请稍后重试'}')));
    }
  }

  // 统一的卡片外观：18px 圆角 + 发丝边 + 极淡投影（浅色才有，制造"浮起"层次）
  BoxDecoration _cardDeco(bool isDark) => BoxDecoration(
    color: Theme.of(context).cardColor,
    borderRadius: BorderRadius.circular(18),
    border: Border.all(
      color: isDark
          ? Colors.white.withValues(alpha: 0.08)
          : const Color(0xFFEDEDED),
      width: 0.5,
    ),
    boxShadow: isDark
        ? null
        : [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.035),
              blurRadius: 16,
              offset: const Offset(0, 6),
            ),
          ],
  );

  // 顶栏圆形图标按钮——比裸图标更有"产品感"
  Widget _circleBtn(IconData icon, VoidCallback onTap, bool isDark) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 34,
        height: 34,
        decoration: BoxDecoration(
          color: isDark ? Colors.white.withValues(alpha: 0.06) : Colors.white,
          shape: BoxShape.circle,
          border: Border.all(
            color: isDark
                ? Colors.white.withValues(alpha: 0.08)
                : const Color(0xFFEDEDED),
            width: 0.5,
          ),
        ),
        child: Icon(
          icon,
          size: 17,
          color: isDark ? Colors.white70 : const Color(0xFF1A1A1A),
        ),
      ),
    );
  }

  // 标签区小标题 + 右侧实时 n/3 计数
  Widget _tagHeader(bool isDark) {
    final count = _selectedTags.length;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Text(
            '话题标签',
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              color: isDark
                  ? Colors.white.withValues(alpha: 0.85)
                  : const Color(0xFF1A1A1A),
            ),
          ),
          const SizedBox(width: 6),
          Text(
            '为帖子加点上下文',
            style: TextStyle(
              fontSize: 11,
              color: isDark ? Colors.white38 : Colors.grey[400],
            ),
          ),
          const Spacer(),
          Text(
            '$count/3',
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              color: count == 0
                  ? (isDark ? Colors.white38 : Colors.grey[400])
                  : _primary,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final canSubmit =
        _titleCtrl.text.trim().isNotEmpty &&
        _contentCtrl.text.trim().isNotEmpty;
    final titleLen = _titleCtrl.text.characters.length;
    final contentLen = _contentCtrl.text.characters.length;

    return Scaffold(
      backgroundColor: isDark
          ? const Color(0xFF0A0A1A)
          : const Color(0xFFFAFAF8),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        leadingWidth: 56,
        leading: Center(
          child: _circleBtn(Icons.close, () => context.pop(), isDark),
        ),
        title: Text(
          '发帖',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: isDark ? Colors.white : const Color(0xFF1A1A1A),
          ),
        ),
        centerTitle: true,
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 14),
            child: GestureDetector(
              onTap: (_submitting || !canSubmit) ? null : _submit,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                height: 34,
                padding: const EdgeInsets.symmetric(horizontal: 18),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: canSubmit
                      ? _primary
                      : (isDark
                            ? Colors.white.withValues(alpha: 0.08)
                            : const Color(0xFFECECEF)),
                  borderRadius: BorderRadius.circular(99),
                  boxShadow: canSubmit && !isDark
                      ? [
                          BoxShadow(
                            color: _primary.withValues(alpha: 0.28),
                            blurRadius: 12,
                            offset: const Offset(0, 4),
                          ),
                        ]
                      : null,
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
                    : Text(
                        '发布',
                        style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w700,
                          color: canSubmit
                              ? Colors.white
                              : (isDark ? Colors.white38 : Colors.grey[400]),
                        ),
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
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            // 标题 + 标签放一张卡片里，两字段之间用发丝线隔开
            Container(
              padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
              decoration: _cardDeco(isDark),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: _titleCtrl,
                    onChanged: (_) => setState(() {}),
                    maxLength: 100,
                    textInputAction: TextInputAction.next,
                    decoration: InputDecoration(
                      isDense: true,
                      hintText: '起个好标题',
                      hintStyle: TextStyle(
                        fontSize: 19,
                        color: isDark
                            ? Colors.white.withValues(alpha: 0.28)
                            : const Color(0xFFBFBFBF),
                        fontWeight: FontWeight.w700,
                      ),
                      filled: false,
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.zero,
                      counterText: '',
                    ),
                    style: TextStyle(
                      fontSize: 19,
                      fontWeight: FontWeight.w700,
                      height: 1.35,
                      color: isDark
                          ? Colors.white.withValues(alpha: 0.92)
                          : const Color(0xFF1A1A1A),
                    ),
                  ),
                  // 标题字数——只在开始输入后出现，克制不抢眼
                  if (titleLen > 0)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Align(
                        alignment: Alignment.centerRight,
                        child: Text(
                          '$titleLen/100',
                          style: TextStyle(
                            fontSize: 11,
                            color: titleLen >= 100
                                ? const Color(0xFFEF4444)
                                : (isDark ? Colors.white30 : Colors.grey[400]),
                          ),
                        ),
                      ),
                    ),
                  const SizedBox(height: 14),
                  Divider(
                    height: 0.5,
                    thickness: 0.5,
                    color: isDark
                        ? Theme.of(context).dividerColor
                        : const Color(0xFFF0F0F0),
                  ),
                  const SizedBox(height: 16),
                  _tagHeader(isDark),
                  // 1) 已选标签——实心紫描边胶囊，右侧 × 删除
                  if (_selectedTags.isNotEmpty) ...[
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: _selectedTags.map((tag) {
                        return Container(
                          padding: const EdgeInsets.fromLTRB(12, 6, 7, 6),
                          decoration: BoxDecoration(
                            color: isDark
                                ? _primary.withValues(alpha: 0.18)
                                : const Color(0xFFEEF0FF),
                            borderRadius: BorderRadius.circular(99),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                tag,
                                style: const TextStyle(
                                  fontSize: 12.5,
                                  color: _primary,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(width: 5),
                              GestureDetector(
                                onTap: () =>
                                    setState(() => _selectedTags.remove(tag)),
                                behavior: HitTestBehavior.opaque,
                                child: Icon(
                                  Icons.close_rounded,
                                  size: 14,
                                  color: _primary.withValues(alpha: 0.7),
                                ),
                              ),
                            ],
                          ),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 10),
                  ],
                  // 2) 预设标签——只显示未选的；满 3 个变灰不可点
                  if (_presetTags.any((t) => !_selectedTags.contains(t)))
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: _presetTags
                          .where((t) => !_selectedTags.contains(t))
                          .map((tag) {
                            final full = _selectedTags.length >= 3;
                            return GestureDetector(
                              onTap: full
                                  ? null
                                  : () =>
                                        setState(() => _selectedTags.add(tag)),
                              child: Opacity(
                                opacity: full ? 0.4 : 1.0,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 13,
                                    vertical: 7,
                                  ),
                                  decoration: BoxDecoration(
                                    color: isDark
                                        ? Colors.white.withValues(alpha: 0.05)
                                        : const Color(0xFFF4F4F6),
                                    borderRadius: BorderRadius.circular(99),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        Icons.add_rounded,
                                        size: 13,
                                        color: isDark
                                            ? Colors.white38
                                            : const Color(0xFF9AA0A6),
                                      ),
                                      const SizedBox(width: 3),
                                      Text(
                                        tag,
                                        style: TextStyle(
                                          fontSize: 12.5,
                                          color: isDark
                                              ? Colors.white.withValues(
                                                  alpha: 0.6,
                                                )
                                              : const Color(0xFF555555),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          })
                          .toList(),
                    ),
                  // 3) 自定义输入——填充胶囊，聚焦时描边/图标变紫；满 3 个隐藏
                  if (_selectedTags.length < 3) ...[
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _customCtrl,
                            focusNode: _customFocus,
                            maxLength: 10,
                            textInputAction: TextInputAction.done,
                            onSubmitted: _addCustomTag,
                            onChanged: (_) => setState(() {}),
                            decoration: InputDecoration(
                              hintText: '自定义标签…',
                              hintStyle: TextStyle(
                                fontSize: 12.5,
                                color: isDark
                                    ? Colors.white30
                                    : Colors.grey[400],
                              ),
                              prefixIcon: Icon(
                                Icons.tag_rounded,
                                size: 15,
                                color: _customFocus.hasFocus
                                    ? _primary
                                    : (isDark
                                          ? Colors.white38
                                          : Colors.grey[400]),
                              ),
                              prefixIconConstraints: const BoxConstraints(
                                minWidth: 34,
                                minHeight: 20,
                              ),
                              filled: true,
                              fillColor: isDark
                                  ? Colors.white.withValues(alpha: 0.05)
                                  : const Color(0xFFF6F6F8),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(99),
                                borderSide: BorderSide(
                                  color: isDark
                                      ? Colors.white.withValues(alpha: 0.1)
                                      : const Color(0xFFE6E6EA),
                                  width: 0.5,
                                ),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(99),
                                borderSide: const BorderSide(
                                  color: _primary,
                                  width: 1,
                                ),
                              ),
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 10,
                              ),
                              counterText: '',
                              isDense: true,
                            ),
                            style: TextStyle(
                              fontSize: 12.5,
                              color: isDark
                                  ? Colors.white.withValues(alpha: 0.9)
                                  : const Color(0xFF1A1A1A),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        // 有内容才点亮成实心紫，空态是低调的中性胶囊
                        Builder(
                          builder: (_) {
                            final hasText = _customCtrl.text.trim().isNotEmpty;
                            return GestureDetector(
                              onTap: hasText ? _addCustomTag : null,
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 150),
                                height: 38,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 15,
                                ),
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  color: hasText
                                      ? _primary
                                      : (isDark
                                            ? Colors.white.withValues(
                                                alpha: 0.06,
                                              )
                                            : const Color(0xFFECECEF)),
                                  borderRadius: BorderRadius.circular(99),
                                ),
                                child: Text(
                                  '添加',
                                  style: TextStyle(
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w600,
                                    color: hasText
                                        ? Colors.white
                                        : (isDark
                                              ? Colors.white38
                                              : Colors.grey[500]),
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 14),

            // 正文单独一张卡片，撑满剩余空间
            Container(
              padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
              decoration: _cardDeco(isDark),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(
                    controller: _contentCtrl,
                    onChanged: (_) => setState(() {}),
                    maxLines: null,
                    minLines: 10,
                    decoration: InputDecoration(
                      isDense: true,
                      hintText: '分享你的想法、问题或发现…',
                      hintStyle: TextStyle(
                        fontSize: 14.5,
                        color: isDark
                            ? Colors.white.withValues(alpha: 0.3)
                            : const Color(0xFFBFBFBF),
                      ),
                      filled: false,
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.zero,
                    ),
                    style: TextStyle(
                      fontSize: 14.5,
                      color: isDark
                          ? Colors.white.withValues(alpha: 0.9)
                          : const Color(0xFF3A3A3A),
                      height: 1.85,
                    ),
                  ),
                  // 正文字数——写了才出现，靠右对齐，克制的产品细节
                  if (contentLen > 0)
                    Padding(
                      padding: const EdgeInsets.only(top: 10),
                      child: Align(
                        alignment: Alignment.centerRight,
                        child: Text(
                          '$contentLen 字',
                          style: TextStyle(
                            fontSize: 11,
                            color: isDark ? Colors.white30 : Colors.grey[400],
                          ),
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
}
