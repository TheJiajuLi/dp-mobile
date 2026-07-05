import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/network/api_client.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../settings/providers/storage_provider.dart';
import '../models/block_model.dart';
import '../widgets/block_card.dart';
import '../widgets/block_picker_sheet.dart';
import '../widgets/preview_drawer.dart';

const _primary = Color(0xFF6366F1);

class PublishScreen extends ConsumerStatefulWidget {
  const PublishScreen({super.key});
  @override
  ConsumerState<PublishScreen> createState() => _PublishScreenState();
}

class _PublishScreenState extends ConsumerState<PublishScreen> {
  final _titleCtrl = TextEditingController();
  final _summaryCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();

  final List<EditorBlock> _blocks = [];
  final List<String> _tags = ['Python', '数据分析'];
  bool _saving = false;
  bool _toolbarExpanded = true;
  String? _coverImageUrl;
  String? _selectedColumn;

  @override
  void initState() {
    super.initState();
    _blocks.add(EditorBlock(id: _uid(), type: BlockType.text, content: ''));
  }

  String _uid() =>
      'block_${DateTime.now().millisecondsSinceEpoch}_${_blocks.length}';

  void _addBlock(BlockType type) {
    setState(() {
      _blocks.add(
        EditorBlock(
          id: _uid(),
          type: type,
          language: type == BlockType.code ? 'python' : null,
        ),
      );
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollCtrl.hasClients) return;
      _scrollCtrl.animateTo(
        _scrollCtrl.position.maxScrollExtent,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    });
  }

  void _deleteBlock(String id) {
    setState(() => _blocks.removeWhere((b) => b.id == id));
  }

  // 上下箭头：调用方传的 j 已经是移除 i 之后那份列表里的最终目标下标
  // （相邻交换，i 和 j 本来就只差 1），直接 removeAt+insert，不需要
  // 再调整下标
  void _swapBlocks(int i, int j) {
    setState(() {
      final b = _blocks.removeAt(i);
      _blocks.insert(j, b);
    });
  }

  // ReorderableListView 的 onReorder 回调里，newIndex 是"还没移除
  // oldIndex 那一项"时的目标下标——往下拖的话要先减 1，不然会多移一格。
  // 这跟上面 _swapBlocks 用的下标含义不一样，混在一个函数里靠 diff 大小
  // 猜调用方是谁很容易猜错，拆成两个函数更保险
  void _onReorder(int oldIndex, int newIndex) {
    setState(() {
      if (newIndex > oldIndex) newIndex -= 1;
      final b = _blocks.removeAt(oldIndex);
      _blocks.insert(newIndex, b);
    });
  }

  Future<void> _saveDraft() async => _save('draft');

  Future<void> _publish() async {
    if (_titleCtrl.text.trim().isEmpty) {
      final l10n = AppLocalizations.of(context)!;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l10n.pleaseEnterNoteTitle)));
      return;
    }
    await _save('published');
  }

  Future<void> _save(String status) async {
    final l10n = AppLocalizations.of(context)!;
    setState(() => _saving = true);
    try {
      // 实测确认（2026-07-05）：blocks 字段要传原始数组，传
      // jsonEncode(...) 得到的字符串会被后端静默丢弃——创建和读取接口
      // 拿到的都是 blocks: []，连一个最简单的 text block 都不例外
      final blocksJson = _blocks.map((b) => b.toJson()).toList();

      final res = await ref
          .read(apiClientProvider)
          .post(
            '/auth/tutorials',
            data: {
              'title': _titleCtrl.text.trim(),
              'summary': _summaryCtrl.text.trim(),
              'cover_image': _coverImageUrl ?? '',
              'tags': _tags,
              'blocks': blocksJson,
              'status': status,
            },
          );

      if (!mounted) return;
      if (res.success) {
        if (status == 'published') {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(l10n.publishSuccessMessage),
              backgroundColor: const Color(0xFF16A34A),
            ),
          );
          context.go('/community');
        } else {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(l10n.draftSavedMessage)));
        }
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.saveFailedWithReason('${res.message}'))),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    // membership 只有 GET /auth/storage/usage 会返回（currentUserProvider
    // 的 UserModel 上没有这个字段）——用 ref.watch 而不是 read，会员状态
    // 变化时（比如刚升级完）文件/音频/视频 block 的解锁状态能跟着更新
    final storageAsync = ref.watch(storageUsageProvider);
    final membership =
        storageAsync.valueOrNull?['membership'] as String? ?? 'free';

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      endDrawer: PreviewDrawer(
        title: _titleCtrl.text,
        summary: _summaryCtrl.text,
        tags: _tags,
        blocks: _blocks,
        coverImageUrl: _coverImageUrl,
      ),
      body: SafeArea(
        child: Column(
          children: [
            _buildTopBar(l10n),
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildLeftToolbar(l10n),
                  Expanded(
                    child: ListView(
                      controller: _scrollCtrl,
                      padding: const EdgeInsets.all(12),
                      children: [
                        _buildMetaCard(l10n),
                        const SizedBox(height: 8),
                        ReorderableListView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: _blocks.length,
                          onReorder: _onReorder,
                          itemBuilder: (ctx, i) => BlockCard(
                            key: ValueKey(_blocks[i].id),
                            block: _blocks[i],
                            index: i,
                            total: _blocks.length,
                            membership: membership,
                            onDelete: () => _deleteBlock(_blocks[i].id),
                            onMoveUp: i > 0
                                ? () => _swapBlocks(i, i - 1)
                                : null,
                            onMoveDown: i < _blocks.length - 1
                                ? () => _swapBlocks(i, i + 1)
                                : null,
                            onChanged: () => setState(() {}),
                          ),
                        ),
                        const SizedBox(height: 8),
                        _buildAddBlockButton(l10n),
                        const SizedBox(height: 80),
                      ],
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

  Widget _buildTopBar(AppLocalizations l10n) {
    return Container(
      color: Theme.of(context).cardColor,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => context.pop(),
            child: const Icon(Icons.arrow_back_ios, size: 18, color: _primary),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: _titleCtrl,
              decoration: InputDecoration(
                hintText: l10n.publishTitleHint,
                hintStyle: const TextStyle(color: Color(0xFFC7C7CC)),
                border: InputBorder.none,
                isDense: true,
                contentPadding: EdgeInsets.zero,
              ),
              style: TextStyle(
                fontSize: 15,
                color: Theme.of(context).textTheme.bodyLarge?.color,
              ),
              onChanged: (_) => setState(() {}),
            ),
          ),
          Builder(
            builder: (ctx) => IconButton(
              icon: const Icon(
                Icons.preview_outlined,
                color: _primary,
                size: 22,
              ),
              onPressed: () => Scaffold.of(ctx).openEndDrawer(),
              tooltip: l10n.previewTooltip,
            ),
          ),
          TextButton(
            onPressed: _saving ? null : _saveDraft,
            child: Text(
              l10n.saveDraftAction,
              style: const TextStyle(fontSize: 13, color: Colors.grey),
            ),
          ),
          const SizedBox(width: 4),
          ElevatedButton(
            onPressed: _saving ? null : _publish,
            style: ElevatedButton.styleFrom(
              backgroundColor: _primary,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              elevation: 0,
            ),
            child: _saving
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      color: Colors.white,
                      strokeWidth: 2,
                    ),
                  )
                : Text(
                    l10n.publish,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  // 左侧悬浮工具栏——常驻竖排图标，点一下直接在末尾加一个对应类型的
  // block（真正的"拖到列表中间插入"需要跨 widget 树的 Draggable/
  // DragTarget，工程量明显更大，这次先满足"快速加 block"这个核心诉求，
  // 拖拽排序已经有 ReorderableListView 覆盖）。旁边一个小箭头可以收起
  Widget _buildLeftToolbar(AppLocalizations l10n) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      width: _toolbarExpanded ? 48 : 16,
      color: Theme.of(context).cardColor,
      child: _toolbarExpanded
          ? Column(
              children: [
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    children: BlockType.values
                        .map(
                          (type) => IconButton(
                            icon: Icon(
                              blockTypeIcon(type),
                              size: 20,
                              color: _primary,
                            ),
                            tooltip: blockTypeLabel(l10n, type),
                            onPressed: () => _addBlock(type),
                          ),
                        )
                        .toList(),
                  ),
                ),
                IconButton(
                  icon: const Icon(
                    Icons.chevron_left,
                    size: 18,
                    color: Colors.grey,
                  ),
                  onPressed: () => setState(() => _toolbarExpanded = false),
                ),
              ],
            )
          : Center(
              child: GestureDetector(
                onTap: () => setState(() => _toolbarExpanded = true),
                child: const Icon(
                  Icons.chevron_right,
                  size: 16,
                  color: Colors.grey,
                ),
              ),
            ),
    );
  }

  Widget _buildMetaCard(AppLocalizations l10n) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE5E5EA), width: 0.5),
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              GestureDetector(
                onTap: _pickCoverImage,
                child: Container(
                  width: 90,
                  height: 60,
                  decoration: BoxDecoration(
                    color: const Color(0xFFEEF0FF),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: const Color(0xFFC7C7FF),
                      width: 1.5,
                    ),
                    image: _coverImageUrl != null
                        ? DecorationImage(
                            image: NetworkImage(_coverImageUrl!),
                            fit: BoxFit.cover,
                          )
                        : null,
                  ),
                  child: _coverImageUrl == null
                      ? Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(
                              Icons.add_photo_alternate,
                              color: Color(0xFFA5B4FC),
                              size: 22,
                            ),
                            const SizedBox(height: 2),
                            Text(
                              l10n.coverImageLabel,
                              style: const TextStyle(
                                fontSize: 10,
                                color: Color(0xFFA5B4FC),
                              ),
                            ),
                          ],
                        )
                      : null,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  children: [
                    TextField(
                      controller: _titleCtrl,
                      decoration: InputDecoration(
                        hintText: l10n.notePlaceholderTitle,
                        border: InputBorder.none,
                        isDense: true,
                        contentPadding: EdgeInsets.zero,
                      ),
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: Theme.of(context).textTheme.bodyLarge?.color,
                      ),
                      maxLines: 1,
                      onChanged: (_) => setState(() {}),
                    ),
                    const SizedBox(height: 4),
                    TextField(
                      controller: _summaryCtrl,
                      decoration: InputDecoration(
                        hintText: l10n.summaryHint,
                        hintStyle: const TextStyle(
                          color: Color(0xFFC7C7CC),
                          fontSize: 13,
                        ),
                        border: InputBorder.none,
                        isDense: true,
                        contentPadding: EdgeInsets.zero,
                      ),
                      style: const TextStyle(
                        fontSize: 13,
                        color: Color(0xFF8E8E93),
                      ),
                      maxLines: 2,
                      onChanged: (_) => setState(() {}),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              ..._tags.map(
                (tag) => GestureDetector(
                  onLongPress: () => setState(() => _tags.remove(tag)),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEEF0FF),
                      borderRadius: BorderRadius.circular(99),
                    ),
                    child: Text(
                      '#$tag',
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFF4F46E5),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ),
              ),
              GestureDetector(
                onTap: _addTag,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(99),
                    border: Border.all(color: const Color(0xFFD1D1D6)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.add, size: 12, color: Colors.grey),
                      const SizedBox(width: 3),
                      Text(
                        l10n.addTagAction,
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.grey,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          const Divider(height: 1, color: Color(0xFFF0F0F0)),
          const SizedBox(height: 8),
          Row(
            children: [
              const Icon(
                Icons.view_column_outlined,
                size: 14,
                color: Colors.grey,
              ),
              const SizedBox(width: 6),
              Text(
                l10n.columnLabel,
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              ),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: _showColumnPicker,
                child: Text(
                  _selectedColumn ?? l10n.joinColumnOptional,
                  style: const TextStyle(fontSize: 12, color: _primary),
                ),
              ),
              const Icon(Icons.chevron_right, size: 14, color: _primary),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildAddBlockButton(AppLocalizations l10n) {
    return GestureDetector(
      onTap: _showBlockPicker,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xFFD1D1D6), width: 1.5),
        ),
        child: Column(
          children: [
            const Icon(
              Icons.add_circle_outline,
              color: Color(0xFFC7C7CC),
              size: 24,
            ),
            const SizedBox(height: 4),
            Text(
              l10n.addContentBlockLabel,
              style: const TextStyle(fontSize: 13, color: Color(0xFFC7C7CC)),
            ),
          ],
        ),
      ),
    );
  }

  void _showBlockPicker() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => BlockPickerSheet(
        onSelect: (type) {
          Navigator.pop(ctx);
          _addBlock(type);
        },
      ),
    );
  }

  void _addTag() {
    final l10n = AppLocalizations.of(context)!;
    final ctrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.addTagAction),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: InputDecoration(
            hintText: l10n.tagNameHint,
            prefixText: '#',
          ),
          onSubmitted: (v) {
            if (v.trim().isNotEmpty && _tags.length < 8) {
              setState(() => _tags.add(v.trim()));
            }
            Navigator.pop(ctx);
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(l10n.cancel),
          ),
          TextButton(
            onPressed: () {
              if (ctrl.text.trim().isNotEmpty && _tags.length < 8) {
                setState(() => _tags.add(ctrl.text.trim()));
              }
              Navigator.pop(ctx);
            },
            child: Text(
              l10n.addTagAction,
              style: const TextStyle(color: _primary),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _pickCoverImage() async {
    final picker = ImagePicker();
    final file = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 1200,
      maxHeight: 600,
      imageQuality: 85,
    );
    if (file == null) return;
    final bytes = await file.readAsBytes();
    try {
      final formData = FormData.fromMap({
        'file': MultipartFile.fromBytes(
          bytes,
          filename: 'cover.jpg',
          contentType: DioMediaType('image', 'jpeg'),
        ),
      });
      final res = await ref
          .read(apiClientProvider)
          .post('/auth/files/upload', data: formData);
      if (!res.success || res.data == null) return;
      final url = (res.data as Map)['url'] as String?;
      if (url != null && mounted) setState(() => _coverImageUrl = url);
    } catch (e) {
      if (mounted) {
        final l10n = AppLocalizations.of(context)!;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.saveFailedWithReason('$e'))),
        );
      }
    }
  }

  void _showColumnPicker() {
    final l10n = AppLocalizations.of(context)!;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(l10n.columnComingSoonMessage)));
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _summaryCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }
}
