import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_client.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../../shared/services/pyodide_engine.dart';
import '../../auth/auth_service.dart';
import '../../publish/models/block_model.dart';
import '../../publish/widgets/block_card.dart';
import '../../publish/widgets/block_picker_sheet.dart' show blockTypeIcon;
import '../../publish/widgets/formatting_toolbar.dart'
    show showBlockPickerSheet;

const _primary = AppColors.primary;

// 论坛发帖——复用发布页那套 Block 编辑器（EditorBlock + BlockCard）：文字/
// 标题/引用/公式(源码+预览)/代码(可运行 Pyodide)/图片(上传 COS) 都现成，
// 不重复造。发布时把 blocks 序列化成 markdown-ish 字符串存 content，读者端
// 由 AiContentRenderer 富渲染（公式/代码高亮/图片；代码只显示不运行）
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
  final _customCtrl = TextEditingController();
  final Set<String> _selectedTags = {};
  final _customFocus = FocusNode();
  bool _submitting = false;

  // Block 编辑器状态
  int _blockSeq = 0;
  late final List<EditorBlock> _blocks = [
    EditorBlock(id: _uid(), type: BlockType.text),
  ];
  String? _focusedBlockId;

  String _uid() => 'fb_${DateTime.now().millisecondsSinceEpoch}_${_blockSeq++}';

  List<String> get _presetTags => widget.forumTags.isNotEmpty
      ? widget.forumTags
      : const ['数学', '编程', 'AI', '数据分析', '物理', '科普', '统计', '机器学习'];

  @override
  void initState() {
    super.initState();
    _customFocus.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _customCtrl.dispose();
    _customFocus.dispose();
    for (final b in _blocks) {
      b.focusNode.dispose();
    }
    super.dispose();
  }

  void _addCustomTag([String? val]) {
    final tag = (val ?? _customCtrl.text).trim();
    if (tag.isEmpty || _selectedTags.length >= 3) return;
    if (!_selectedTags.contains(tag)) {
      setState(() => _selectedTags.add(tag));
    }
    _customCtrl.clear();
  }

  // —————————————————————————— Block 管理（精简自 publish_screen）
  Future<List<Map<String, dynamic>>> _runBlockCode(
    String blockId,
    String code,
    String language,
  ) async {
    final l10n = AppLocalizations.of(context)!;
    if (language == 'html' || language == 'markdown') {
      return [
        {'type': 'info', 'content': l10n.unsupportedCellType},
      ];
    }
    final engine = ref.read(pyodideEngineProvider);
    if (language == 'javascript') return engine.runJavaScript(code);
    return engine.run(blockId, code, language, l10n);
  }

  EditorBlock _createBlock(BlockType type) => EditorBlock(
    id: _uid(),
    type: type,
    language: type == BlockType.code ? 'python' : null,
  );

  void _addBlock(BlockType type) {
    final block = _createBlock(type);
    setState(() => _blocks.add(block));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) block.focusNode.requestFocus();
    });
  }

  void _insertBlockAt(int index, BlockType type) {
    final block = _createBlock(type);
    setState(() => _blocks.insert(index, block));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) block.focusNode.requestFocus();
    });
  }

  void _deleteBlock(String id) {
    if (_blocks.length <= 1) {
      // 只剩一个就清空成空文字块，不整没了
      final b = _blocks.first;
      if (b.type == BlockType.text && b.content.isEmpty) return;
      setState(() {
        for (final x in _blocks) {
          x.focusNode.dispose();
        }
        _blocks
          ..clear()
          ..add(EditorBlock(id: _uid(), type: BlockType.text));
      });
      return;
    }
    final idx = _blocks.indexWhere((b) => b.id == id);
    if (idx < 0) return;
    setState(() {
      _blocks[idx].focusNode.dispose();
      _blocks.removeAt(idx);
    });
  }

  void _deleteBlockAndFocusPrevious(int i) {
    if (i < 0 || i >= _blocks.length) return;
    final prev = i > 0 ? _blocks[i - 1].focusNode : null;
    _deleteBlock(_blocks[i].id);
    prev?.requestFocus();
  }

  void _swapBlocks(int i, int j) {
    if (i < 0 || j < 0 || i >= _blocks.length || j >= _blocks.length) return;
    setState(() {
      final b = _blocks.removeAt(i);
      _blocks.insert(j, b);
    });
  }

  void _onReorder(int oldIndex, int newIndex) {
    setState(() {
      if (newIndex > oldIndex) newIndex--;
      final b = _blocks.removeAt(oldIndex);
      _blocks.insert(newIndex, b);
    });
  }

  // Block → markdown-ish 字符串（AiContentRenderer 能还原：$$公式$$、```代码```、
  // ![](图片)、## 标题、> 引用）
  String _serializeBlocks() {
    final buf = StringBuffer();
    for (final b in _blocks) {
      final c = b.content.trim();
      switch (b.type) {
        case BlockType.text:
          if (c.isNotEmpty) buf.writeln(c);
          break;
        case BlockType.heading:
          if (c.isNotEmpty) {
            buf.writeln('${'#' * (b.headingLevel ?? 2).clamp(1, 6)} $c');
          }
          break;
        case BlockType.callout:
          if (c.isNotEmpty) buf.writeln('> $c');
          break;
        case BlockType.latex:
          if (c.isNotEmpty) buf.writeln('\$\$\n$c\n\$\$');
          break;
        case BlockType.code:
          if (c.isNotEmpty) {
            buf.writeln('```${b.language ?? ''}\n$c\n```');
          }
          break;
        case BlockType.image:
          if ((b.imageUrl ?? '').isNotEmpty) {
            buf.writeln('![](${b.imageUrl})');
          }
          break;
        default:
          if (c.isNotEmpty) buf.writeln(c);
      }
      buf.writeln();
    }
    return buf.toString().trim();
  }

  bool get _hasContent => _blocks.any(
    (b) => b.content.trim().isNotEmpty || (b.imageUrl ?? '').isNotEmpty,
  );

  Future<void> _submit() async {
    if (_titleCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('请输入标题')));
      return;
    }
    final content = _serializeBlocks();
    if (content.isEmpty) {
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
            'content': content,
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
    final l10n = AppLocalizations.of(context)!;
    final membership = ref.watch(currentUserProvider)?.membership ?? 'free';
    final canSubmit = _titleCtrl.text.trim().isNotEmpty && _hasContent;
    final titleLen = _titleCtrl.text.characters.length;

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
      body: Column(
        children: [
          Expanded(
            child: CustomScrollView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              slivers: [
                // 标题 + 标签卡
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 14),
                    child: _buildTitleTagsCard(isDark, titleLen),
                  ),
                ),
                // Block 正文——可拖拽重排，每张卡后跟一个「+」插入条
                SliverReorderableList(
                  itemCount: _blocks.length,
                  onReorder: _onReorder,
                  proxyDecorator: (child, index, animation) => Material(
                    color: Colors.transparent,
                    elevation: 6,
                    shadowColor: Colors.black.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(14),
                    child: child,
                  ),
                  itemBuilder: (ctx, i) => Padding(
                    key: ValueKey(_blocks[i].id),
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        BlockCard(
                          key: ValueKey('card_${_blocks[i].id}'),
                          block: _blocks[i],
                          index: i,
                          total: _blocks.length,
                          membership: membership,
                          onRunCode: _runBlockCode,
                          onDelete: () => _deleteBlock(_blocks[i].id),
                          onEmptyBackspace: () =>
                              _deleteBlockAndFocusPrevious(i),
                          onMoveUp: i > 0 ? () => _swapBlocks(i, i - 1) : null,
                          onMoveDown: i < _blocks.length - 1
                              ? () => _swapBlocks(i, i + 1)
                              : null,
                          onChanged: () => setState(() {}),
                          focusedBlockId: _focusedBlockId,
                          onFocusGained: () =>
                              setState(() => _focusedBlockId = _blocks[i].id),
                          onNonTextTap: () =>
                              setState(() => _focusedBlockId = _blocks[i].id),
                        ),
                        _insertDivider(i, isDark, l10n),
                      ],
                    ),
                  ),
                ),
                const SliverToBoxAdapter(child: SizedBox(height: 28)),
              ],
            ),
          ),
          _buildToolbar(isDark, l10n),
        ],
      ),
    );
  }

  // Block 间「+」插入条
  Widget _insertDivider(int i, bool isDark, AppLocalizations l10n) {
    final line = isDark
        ? Colors.white.withValues(alpha: 0.06)
        : const Color(0xFFEDEDED);
    return GestureDetector(
      onTap: () => showBlockPickerSheet(
        context,
        l10n: l10n,
        isDarkMode: isDark,
        onPick: (type) => _insertBlockAt(i + 1, type),
      ),
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            Expanded(child: Container(height: 0.5, color: line)),
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 8),
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isDark
                    ? Colors.white.withValues(alpha: 0.05)
                    : Colors.white,
                border: Border.all(color: line),
              ),
              child: Icon(
                Icons.add,
                size: 13,
                color: isDark ? Colors.white38 : const Color(0xFF9AA0A6),
              ),
            ),
            Expanded(child: Container(height: 0.5, color: line)),
          ],
        ),
      ),
    );
  }

  // 底部快捷工具栏——常用块一键新建 + 更多
  Widget _buildToolbar(bool isDark, AppLocalizations l10n) {
    Widget btn(IconData icon, VoidCallback onTap) => GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.all(9),
        child: Icon(
          icon,
          size: 21,
          color: isDark ? Colors.white70 : const Color(0xFF555555),
        ),
      ),
    );
    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF0A0A1A) : const Color(0xFFFAFAF8),
        border: Border(
          top: BorderSide(
            color: isDark
                ? Colors.white.withValues(alpha: 0.06)
                : const Color(0xFFEDEDED),
            width: 0.5,
          ),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          child: Row(
            children: [
              btn(
                blockTypeIcon(BlockType.text),
                () => _addBlock(BlockType.text),
              ),
              btn(
                blockTypeIcon(BlockType.latex),
                () => _addBlock(BlockType.latex),
              ),
              btn(
                blockTypeIcon(BlockType.code),
                () => _addBlock(BlockType.code),
              ),
              btn(
                blockTypeIcon(BlockType.image),
                () => _addBlock(BlockType.image),
              ),
              const Spacer(),
              btn(
                Icons.more_horiz,
                () => showBlockPickerSheet(
                  context,
                  l10n: l10n,
                  isDarkMode: isDark,
                  onPick: _addBlock,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTitleTagsCard(bool isDark, int titleLen) {
    return Container(
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
                        : AppColors.primaryLight,
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
                        onTap: () => setState(() => _selectedTags.remove(tag)),
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
                          : () => setState(() => _selectedTags.add(tag)),
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
                                      ? Colors.white.withValues(alpha: 0.6)
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
                        color: isDark ? Colors.white30 : Colors.grey[400],
                      ),
                      prefixIcon: Icon(
                        Icons.tag_rounded,
                        size: 15,
                        color: _customFocus.hasFocus
                            ? _primary
                            : (isDark ? Colors.white38 : Colors.grey[400]),
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
                        borderSide: const BorderSide(color: _primary, width: 1),
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
                Builder(
                  builder: (_) {
                    final hasText = _customCtrl.text.trim().isNotEmpty;
                    return GestureDetector(
                      onTap: hasText ? _addCustomTag : null,
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 150),
                        height: 38,
                        padding: const EdgeInsets.symmetric(horizontal: 15),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: hasText
                              ? _primary
                              : (isDark
                                    ? Colors.white.withValues(alpha: 0.06)
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
                                : (isDark ? Colors.white38 : Colors.grey[500]),
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
    );
  }
}
