import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_client.dart';

// 后端目前没有 POST /auth/questions/:id/answers 这个接口（问答闭环只做到
// "发布提问+邀请专家"这一步），这里按真实接口路径调用，接口没上线之前
// 点发布会收到失败提示，不是本地假装成功——等后端加上就能直接跑通，
// 不用再改一遍前端
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
  final _ctrl = TextEditingController();
  bool _submitting = false;
  bool _done = false;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_ctrl.text.trim().length < 10) return;
    setState(() => _submitting = true);
    final res = await ref
        .read(apiClientProvider)
        .post('/auth/questions/${widget.questionId}/answers', data: {'content': _ctrl.text.trim()});
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

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF0A0A1A) : const Color(0xFFFAFAF8),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, size: 18),
          onPressed: () => context.pop(),
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
                onPressed: _ctrl.text.trim().length >= 10 && !_submitting ? _submit : null,
                child: _submitting
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text(
                        '发布',
                        style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                      ),
              ),
            ),
        ],
      ),
      body: _done ? _buildSuccess() : _buildForm(isDark),
    );
  }

  Widget _buildForm(bool isDark) {
    return Column(
      children: [
        Container(
          margin: const EdgeInsets.fromLTRB(14, 8, 14, 12),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFF6366F1).withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: const Color(0xFF6366F1).withValues(alpha: 0.2),
              width: 0.5,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '回答问题',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  letterSpacing: .06,
                  color: const Color(0xFF6366F1).withValues(alpha: 0.7),
                ),
              ),
              const SizedBox(height: 5),
              Text(
                widget.questionText,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: isDark ? Colors.white.withValues(alpha: 0.9) : const Color(0xFF1A1A1A),
                  height: 1.5,
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: TextField(
              controller: _ctrl,
              maxLines: null,
              expands: true,
              autofocus: true,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                hintText: '分享你的见解...',
                hintStyle: TextStyle(
                  color: isDark ? Colors.white.withValues(alpha: 0.25) : Colors.grey[400],
                  fontSize: 15,
                ),
                border: InputBorder.none,
              ),
              style: TextStyle(
                fontSize: 15,
                height: 1.7,
                color: isDark ? Colors.white.withValues(alpha: 0.9) : const Color(0xFF1A1A1A),
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 0, 14, 24),
          child: Column(
            children: [
              Text(
                '你的回答将展示在问题页，并通知提问者',
                style: TextStyle(
                  fontSize: 12,
                  color: isDark ? Colors.white.withValues(alpha: 0.3) : Colors.grey[400],
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: _ctrl.text.trim().length >= 10 && !_submitting ? _submit : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: isDark ? const Color(0xFF6366F1) : const Color(0xFF1A1A1A),
                    foregroundColor: Colors.white,
                    elevation: 0,
                    disabledBackgroundColor: isDark
                        ? Colors.white.withValues(alpha: 0.08)
                        : Colors.grey[200],
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: _submitting
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Text(
                          '发布回答',
                          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                        ),
                ),
              ),
            ],
          ),
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
              child: const Icon(Icons.check_circle_outline, size: 32, color: Color(0xFF16A34A)),
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
                child: const Text(
                  '完成',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
