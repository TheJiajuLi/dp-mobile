import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/jisuo_refresh_signal.dart';
import '../../../core/network/api_client.dart';
import '../../../features/auth/auth_service.dart';
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
  ConsumerState<QuestionDetailScreen> createState() =>
      _QuestionDetailScreenState();
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

  bool _deleting = false;

  // 后端目前只有 GET /auth/questions（列表）没有单条详情接口，从通知冷
  // 启动进来、initialQuestion 是 null 时拿不到 asker_id，没法判断是不是
  // 本人的提问——这种情况下不展示"···"菜单，只在从极索列表/回答成功页带
  // 着完整问题数据跳进来时才有编辑/删除入口
  bool get _isOwnQuestion {
    final askerId = widget.initialQuestion?['asker_id']?.toString();
    return askerId != null && askerId == ref.watch(currentUserProvider)?.id;
  }

  Future<void> _share() async {
    final text = widget.initialQuestion?['text'] as String? ?? '';
    if (text.isEmpty) return;
    await Share.share('来看看极索上的这个问题：\n$text');
  }

  void _edit() {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('编辑问题功能即将上线')));
  }

  Future<void> _showDeleteSheet() async {
    await showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _DeleteConfirmSheet(
        answerCount: _answers.length,
        onConfirm: () {
          Navigator.pop(ctx);
          _deleteQuestion();
        },
      ),
    );
  }

  Future<void> _deleteQuestion() async {
    if (_deleting) return;
    _deleting = true;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(
        child: CircularProgressIndicator(color: Color(0xFFEF4444)),
      ),
    );

    final res = await ref
        .read(apiClientProvider)
        .delete('/auth/questions/${widget.questionId}');
    if (!mounted) return;
    Navigator.of(context).pop();

    if (res.success) {
      notifyJisuoShouldRefresh(ref);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('问题已删除'),
          duration: Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
          backgroundColor: Color(0xFF1A1A1A),
        ),
      );
      context.pop({'deleted': true, 'questionId': widget.questionId});
    } else {
      _deleting = false;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(res.message ?? '删除失败，请稍后重试'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final q = widget.initialQuestion;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isOwnQuestion = _isOwnQuestion;

    return Scaffold(
      appBar: AppBar(
        title: const Text('问题详情'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, size: 18),
          onPressed: () => context.pop(),
        ),
        actions: [
          if (isOwnQuestion)
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert, size: 20),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              onSelected: (val) {
                if (val == 'share') _share();
                if (val == 'edit') _edit();
                if (val == 'delete') _showDeleteSheet();
              },
              itemBuilder: (_) => [
                PopupMenuItem(
                  value: 'share',
                  child: Row(
                    children: [
                      Icon(
                        Icons.share_outlined,
                        size: 16,
                        color: Colors.grey[600],
                      ),
                      const SizedBox(width: 9),
                      const Text('分享问题', style: TextStyle(fontSize: 13)),
                    ],
                  ),
                ),
                PopupMenuItem(
                  value: 'edit',
                  child: Row(
                    children: [
                      Icon(
                        Icons.edit_outlined,
                        size: 16,
                        color: Colors.grey[600],
                      ),
                      const SizedBox(width: 9),
                      const Text('编辑问题', style: TextStyle(fontSize: 13)),
                    ],
                  ),
                ),
                const PopupMenuItem(
                  value: 'delete',
                  child: Row(
                    children: [
                      Icon(
                        Icons.delete_outline,
                        size: 16,
                        color: Color(0xFFEF4444),
                      ),
                      SizedBox(width: 9),
                      Text(
                        '删除问题',
                        style: TextStyle(
                          fontSize: 13,
                          color: Color(0xFFEF4444),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            )
          else if (q != null)
            IconButton(
              icon: const Icon(Icons.share_outlined, size: 20),
              onPressed: _share,
            ),
          const SizedBox(width: 4),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(14),
          children: [
            if (q != null) _questionHeader(q, isDark),
            const SizedBox(height: 12),
            Text(
              _loading ? '加载中…' : '回答（${_answers.length}）',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Colors.grey[500],
              ),
            ),
            const SizedBox(height: 6),
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
    final viewCount = (q['view_count'] as num?)?.toInt();
    final isOwnQuestion = _isOwnQuestion;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Colors.grey.withValues(alpha: 0.1),
          width: 0.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (domain.isNotEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
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
              const Spacer(),
              if (isOwnQuestion)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 7,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1A0E2E),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Text(
                    '我的提问',
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
            text,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              height: 1.4,
            ),
          ),
          if (viewCount != null) ...[
            const SizedBox(height: 8),
            Text(
              '$_answersCountLabel · $viewCount 次浏览',
              style: TextStyle(fontSize: 11, color: Colors.grey[500]),
            ),
          ],
        ],
      ),
    );
  }

  String get _answersCountLabel => '${_answers.length} 个回答';
}

class _DeleteConfirmSheet extends StatelessWidget {
  final int answerCount;
  final VoidCallback onConfirm;

  const _DeleteConfirmSheet({
    required this.answerCount,
    required this.onConfirm,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 36,
              height: 3,
              margin: const EdgeInsets.only(top: 10, bottom: 20),
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(99),
              ),
            ),
            Container(
              width: 52,
              height: 52,
              decoration: const BoxDecoration(
                color: Color(0xFFFFF0F0),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.delete_outline,
                size: 24,
                color: Color(0xFFEF4444),
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              '删除这个问题？',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Text(
              answerCount > 0
                  ? '删除后无法恢复\n该问题下的 $answerCount 条回答也将一并删除'
                  : '删除后无法恢复',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                height: 1.6,
                color: Colors.grey[500],
              ),
            ),
            const SizedBox(height: 20),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Column(
                children: [
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton(
                      onPressed: onConfirm,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFEF4444),
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text(
                        '确认删除',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: TextButton(
                      onPressed: () => Navigator.pop(context),
                      style: TextButton.styleFrom(
                        backgroundColor: Colors.grey.withValues(alpha: 0.08),
                        foregroundColor: Colors.grey[600],
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text(
                        '取消',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
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
          bottom: BorderSide(
            color: Colors.grey.withValues(alpha: 0.1),
            width: 0.5,
          ),
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
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
              if (a['is_aurora_creator'] == 1 || a['is_aurora_creator'] == true)
                Container(
                  margin: const EdgeInsets.only(left: 5),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 5,
                    vertical: 2,
                  ),
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
            style: TextStyle(
              fontSize: 14,
              height: 1.7,
              color: Colors.grey[700],
            ),
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
                  style: TextStyle(
                    fontSize: 12,
                    color: _liked ? Colors.red : Colors.grey[400],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
