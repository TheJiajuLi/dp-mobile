import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_client.dart';
import '../models/answer_block.dart';
import '../widgets/answer_block_widget.dart';
import '../widgets/block_picker_sheet.dart';
import '../widgets/format_toolbar.dart';

// 后端目前没有 POST /auth/questions/:id/answers 这个接口上线之前那版是
// 单个 TextField；现在换成极索首页"社区精选"卡片同一套 Block 编辑器
// 语言（正文/标题/引用/公式/代码/图片/分割线），发布时用 toMarkdown()
// 拼成纯文本传给后端——question_answers.content 是单个 TEXT 列，没有
// 单独的富文本存储结构，不是 tutorials.blocks 那套 JSON
class AnswerQuestionScreen extends ConsumerStatefulWidget {
  final String questionId;
  final String questionText;
  final String domain;

  const AnswerQuestionScreen({
    super.key,
    required this.questionId,
    required this.questionText,
    required this.domain,
  });

  @override
  ConsumerState<AnswerQuestionScreen> createState() => _AnswerQuestionScreenState();
}

class _AnswerQuestionScreenState extends ConsumerState<AnswerQuestionScreen> {
  final List<AnswerBlock> _blocks = [
    AnswerBlock(id: UniqueKey().toString(), type: BlockType.text),
  ];
  final Map<String, FocusNode> _focusNodes = {};
  bool _submitting = false;
  bool _done = false;

  FocusNode _focusFor(String id) => _focusNodes.putIfAbsent(id, () => FocusNode());

  void _addBlock(BlockType type) {
    final block = AnswerBlock(id: UniqueKey().toString(), type: type);
    setState(() => _blocks.add(block));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focusFor(block.id).requestFocus();
    });
  }

  void _deleteBlock(String id) {
    if (_blocks.length <= 1) return;
    _focusNodes[id]?.dispose();
    _focusNodes.remove(id);
    setState(() => _blocks.removeWhere((b) => b.id == id));
  }

  bool get _hasContent => _blocks.any((b) => b.content.trim().length > 5);

  Future<void> _submit() async {
    if (!_hasContent) return;
    setState(() => _submitting = true);
    final content = blocksToContent(_blocks);
    final res = await ref
        .read(apiClientProvider)
        .post('/auth/questions/${widget.questionId}/answers', data: {'content': content});
    if (!mounted) return;
    if (res.success) {
      setState(() {
        _submitting = false;
        _done = true;
      });
    } else {
      setState(() => _submitting = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(res.message ?? '发布失败，请重试')));
    }
  }

  Future<void> _handleBack() async {
    if (_hasContent) {
      final confirm = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('放弃回答？'),
          content: const Text('内容将不会保存'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('继续编辑'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('放弃', style: TextStyle(color: Colors.red)),
            ),
          ],
        ),
      );
      if (confirm == true && mounted) context.pop();
    } else {
      context.pop();
    }
  }

  @override
  void dispose() {
    for (final fn in _focusNodes.values) {
      fn.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? const Color(0xFF0A0A1A) : const Color(0xFFFAFAF8);

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, size: 18),
          onPressed: _handleBack,
        ),
        title: const Text(
          '撰写回答',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
        actions: [
          if (!_done)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: TextButton(
                onPressed: _hasContent && !_submitting ? _submit : null,
                style: TextButton.styleFrom(
                  backgroundColor: _hasContent && !_submitting
                      ? (isDark ? const Color(0xFF6366F1) : const Color(0xFF1A1A1A))
                      : (isDark ? Colors.white.withValues(alpha: 0.08) : Colors.grey[200]),
                  foregroundColor: _hasContent && !_submitting
                      ? Colors.white
                      : (isDark ? Colors.white.withValues(alpha: 0.3) : Colors.grey[400]),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(99)),
                ),
                child: _submitting
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 1.5, color: Colors.white),
                      )
                    : const Text('发布', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
              ),
            ),
        ],
      ),
      body: _done ? _buildSuccess() : _buildEditor(isDark),
    );
  }

  Widget _buildEditor(bool isDark) {
    return Column(
      children: [
        Container(
          margin: const EdgeInsets.fromLTRB(12, 8, 12, 4),
          padding: const EdgeInsets.all(11),
          decoration: BoxDecoration(
            color: const Color(0xFF6366F1).withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0xFF6366F1).withValues(alpha: 0.18), width: 0.5),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '回答问题',
                style: TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.w600,
                  letterSpacing: .06,
                  color: const Color(0xFF6366F1).withValues(alpha: 0.8),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                widget.questionText,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  height: 1.4,
                  color: isDark ? Colors.white.withValues(alpha: 0.9) : const Color(0xFF1A1A1A),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 16),
            itemCount: _blocks.length + 1,
            itemBuilder: (ctx, i) {
              if (i == _blocks.length) {
                return GestureDetector(
                  onTap: () => BlockPickerSheet.show(context, _addBlock),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Row(
                      children: [
                        Expanded(
                          child: Container(
                            height: 0.5,
                            color: isDark ? Colors.white.withValues(alpha: 0.08) : const Color(0xFFEBEBEB),
                          ),
                        ),
                        Container(
                          margin: const EdgeInsets.symmetric(horizontal: 8),
                          width: 22,
                          height: 22,
                          decoration: BoxDecoration(
                            color: const Color(0xFFEEF0FF),
                            shape: BoxShape.circle,
                            border: Border.all(color: const Color(0xFF6366F1).withValues(alpha: 0.3), width: 0.5),
                          ),
                          child: const Icon(Icons.add, size: 13, color: Color(0xFF6366F1)),
                        ),
                        Expanded(
                          child: Container(
                            height: 0.5,
                            color: isDark ? Colors.white.withValues(alpha: 0.08) : const Color(0xFFEBEBEB),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }
              final block = _blocks[i];
              return AnswerBlockWidget(
                key: ValueKey(block.id),
                block: block,
                isDark: isDark,
                focusNode: _focusFor(block.id),
                onChanged: (v) => setState(() => block.content = v),
                onDelete: () => _deleteBlock(block.id),
              );
            },
          ),
        ),
        FormatToolbar(
          onAddBlock: _addBlock,
          onBold: () {},
          onItalic: () {},
        ),
      ],
    );
  }

  Widget _buildSuccess() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: const BoxDecoration(color: Color(0xFFDCFCE7), shape: BoxShape.circle),
              child: const Icon(Icons.check, size: 30, color: Color(0xFF16A34A)),
            ),
            const SizedBox(height: 16),
            const Text(
              '回答已发布',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Text('提问者将收到通知', style: TextStyle(fontSize: 14, color: Colors.grey[400])),
            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: () => context.pop(),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF6366F1),
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: const Text('完成', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
