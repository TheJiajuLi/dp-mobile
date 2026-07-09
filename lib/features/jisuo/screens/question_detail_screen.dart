import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_client.dart';
import '../../messages/utils/message_avatar.dart';
import 'jisuo_screen.dart' show jisuoDomainBg, jisuoDomainColor;

// 后端目前只有 GET /auth/questions（列表）没有单条详情接口，问题本文
// 只能靠调用方（热门提问卡片/接受邀请流程）在跳转时把已经拿到手的数据
// 通过 initialQuestion 带过来——从通知冷启动进来、手上没有这份数据时，
// 头部就不展示问题原文，只展示"回答"列表，不编造/硬凑一个问题文本出来
class QuestionDetailScreen extends ConsumerStatefulWidget {
  final String questionId;
  final Map<String, dynamic>? initialQuestion;

  const QuestionDetailScreen({
    super.key,
    required this.questionId,
    this.initialQuestion,
  });

  @override
  ConsumerState<QuestionDetailScreen> createState() => _QuestionDetailScreenState();
}

class _QuestionDetailScreenState extends ConsumerState<QuestionDetailScreen> {
  List<Map<String, dynamic>> _answers = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final res = await ref
        .read(apiClientProvider)
        .get('/auth/questions/${widget.questionId}/answers');
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (res.success && res.data != null) {
        _answers = ((res.data['answers'] as List?) ?? [])
            .map((a) => Map<String, dynamic>.from(a as Map))
            .toList();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final q = widget.initialQuestion;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text('问题详情'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, size: 18),
          onPressed: () => context.pop(),
        ),
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(14),
          children: [
            if (q != null) _questionHeader(q, isDark),
            const SizedBox(height: 8),
            Text(
              _loading ? '加载中…' : '${_answers.length} 个回答',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Colors.grey[400],
              ),
            ),
            if (_loading)
              const Padding(
                padding: EdgeInsets.only(top: 60),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_answers.isEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 60),
                child: Center(
                  child: Text(
                    '还没有人回答，等等看吧',
                    style: TextStyle(color: Colors.grey[400]),
                  ),
                ),
              )
            else
              ..._answers.map((a) => _AnswerCard(answer: a)),
          ],
        ),
      ),
    );
  }

  Widget _questionHeader(Map<String, dynamic> q, bool isDark) {
    final domain = q['domain'] as String? ?? '';
    final text = q['text'] as String? ?? '';
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.withValues(alpha: 0.1), width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (domain.isNotEmpty)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: jisuoDomainBg(domain),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                domain,
                style: TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.w600,
                  color: jisuoDomainColor(domain),
                ),
              ),
            ),
          const SizedBox(height: 8),
          Text(
            text,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, height: 1.4),
          ),
        ],
      ),
    );
  }
}

class _AnswerCard extends ConsumerStatefulWidget {
  final Map<String, dynamic> answer;
  const _AnswerCard({required this.answer});

  @override
  ConsumerState<_AnswerCard> createState() => _AnswerCardState();
}

class _AnswerCardState extends ConsumerState<_AnswerCard> {
  bool _liked = false;
  late int _likes = (widget.answer['like_count'] as num?)?.toInt() ?? 0;

  Future<void> _like() async {
    if (_liked) return;
    setState(() {
      _liked = true;
      _likes++;
    });
    final res = await ref
        .read(apiClientProvider)
        .post('/auth/questions/answers/${widget.answer['id']}/like');
    if (!mounted || res.success) return;
    setState(() {
      _liked = false;
      _likes--;
    });
  }

  @override
  Widget build(BuildContext context) {
    final a = widget.answer;
    final username = a['username'] as String? ?? '';
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: Colors.grey.withValues(alpha: 0.1), width: 0.5),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              buildMessageAvatar(a['avatar'] as String?, username, radius: 14),
              const SizedBox(width: 8),
              Text(
                username,
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
              ),
              if (a['is_aurora_creator'] == 1 || a['is_aurora_creator'] == true)
                Container(
                  margin: const EdgeInsets.only(left: 5),
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1A0E2E),
                    borderRadius: BorderRadius.circular(3),
                  ),
                  child: const Text(
                    '★ 极光',
                    style: TextStyle(
                      fontSize: 9,
                      color: Color(0xFFF59E0B),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            a['content'] as String? ?? '',
            style: TextStyle(fontSize: 14, height: 1.7, color: Colors.grey[700]),
          ),
          const SizedBox(height: 10),
          GestureDetector(
            onTap: _like,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  _liked ? Icons.favorite : Icons.favorite_border,
                  size: 16,
                  color: _liked ? Colors.red : Colors.grey[400],
                ),
                const SizedBox(width: 4),
                Text(
                  '$_likes',
                  style: TextStyle(fontSize: 12, color: _liked ? Colors.red : Colors.grey[400]),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
