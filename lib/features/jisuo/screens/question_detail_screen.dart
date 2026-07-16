import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/jisuo_refresh_signal.dart';
import '../../community/widgets/question_share_sheet.dart';
import '../../../core/network/api_client.dart';
import '../../../core/theme/app_theme.dart';
import '../../../features/auth/auth_service.dart';
import '../../../shared/widgets/ai_content_renderer.dart';
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

  // 「写回答」——弹出轻量 Sheet 编辑器（问题引用 + 输入区 + 快捷公式/代码 +
  // 字数计数 + 发布）。发布成功后刷新回答列表并弹绿色 Toast
  Future<void> _openWriteAnswer(String questionText) async {
    final posted = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _WriteAnswerSheet(
        questionId: widget.questionId,
        questionText: questionText,
      ),
    );
    if (posted == true && mounted) {
      _load();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('回答已发布，提问者将收到通知'),
          duration: Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
          backgroundColor: Color(0xFF16A34A),
        ),
      );
    }
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

  void _share() {
    final q = widget.initialQuestion;
    if (q == null || (q['text'] as String?)?.isEmpty != false) return;
    // 论坛/群组/好友三选一的 in-app 分享 Sheet（替代原来的系统分享面板）
    showQuestionShareSheet(context, q);
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
      backgroundColor: isDark ? AppColors.darkBg : const Color(0xFFFAFAF8),
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
      body: Stack(
        children: [
          RefreshIndicator(
            onRefresh: _load,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              // 底部留白给悬浮的「写回答」胶囊，不遮住最后一条回答
              padding: const EdgeInsets.fromLTRB(14, 14, 14, 88),
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
          // 「写回答」——任何登录用户都能答，唯独提问者本人不显示（后端也有
          // 400 限制，前端一并隐藏）。冷启动没拿到问题原文/domain 时传空，
          // 不阻断回答流程
          if (!isOwnQuestion && ref.watch(currentUserProvider) != null)
            Positioned(
              right: 16,
              bottom: 20,
              child: _WriteAnswerButton(
                onTap: () => _openWriteAnswer(q?['text']?.toString() ?? ''),
              ),
            ),
        ],
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
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
          AiContentRenderer(
            content: a['content'] as String? ?? '',
            isDark: isDark,
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

// 底部悬浮「写回答」——纯品牌紫胶囊，笔形图标 + 文字，一道很淡的同色投影
class _WriteAnswerButton extends StatelessWidget {
  final VoidCallback onTap;
  const _WriteAnswerButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    const primary = Color(0xFF6366F1);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 13),
        decoration: BoxDecoration(
          color: primary,
          borderRadius: BorderRadius.circular(28),
          boxShadow: [
            BoxShadow(
              color: primary.withValues(alpha: 0.28),
              blurRadius: 16,
              offset: const Offset(0, 5),
            ),
          ],
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.edit_outlined, size: 17, color: Colors.white),
            SizedBox(width: 7),
            Text(
              '写回答',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: Colors.white,
                letterSpacing: 0.3,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// 「写回答」轻量 Sheet：问题引用（蓝左边框）+ 输入区 + LaTeX/代码快捷 +
// 字数计数 + 发布。发布走 POST /auth/questions/:id/answers，成功 pop(true)
class _WriteAnswerSheet extends ConsumerStatefulWidget {
  final String questionId;
  final String questionText;
  const _WriteAnswerSheet({
    required this.questionId,
    required this.questionText,
  });

  @override
  ConsumerState<_WriteAnswerSheet> createState() => _WriteAnswerSheetState();
}

class _WriteAnswerSheetState extends ConsumerState<_WriteAnswerSheet> {
  static const _primary = Color(0xFF6366F1);
  static const _maxLen = 2000;
  final _ctrl = TextEditingController();
  final _focus = FocusNode();
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _ctrl.addListener(() => setState(() {}));
    WidgetsBinding.instance.addPostFrameCallback((_) => _focus.requestFocus());
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _focus.dispose();
    super.dispose();
  }

  bool get _canPost => _ctrl.text.trim().isNotEmpty && !_submitting;

  // 在光标处包裹/插入片段（LaTeX/代码），插入后把光标落在片段中间
  void _wrap(String left, String right) {
    final t = _ctrl.text;
    final sel = _ctrl.selection;
    final start = sel.isValid ? sel.start : t.length;
    final end = sel.isValid ? sel.end : t.length;
    final selected = t.substring(start, end);
    final inserted = '$left$selected$right';
    _ctrl.text = t.replaceRange(start, end, inserted);
    _ctrl.selection = TextSelection.collapsed(
      offset: start + left.length + selected.length,
    );
    _focus.requestFocus();
  }

  Future<void> _submit() async {
    if (!_canPost) return;
    setState(() => _submitting = true);
    final res = await ref
        .read(apiClientProvider)
        .post(
          '/auth/questions/${widget.questionId}/answers',
          data: {'content': _ctrl.text.trim()},
        );
    if (!mounted) return;
    if (res.success) {
      notifyJisuoShouldRefresh(ref);
      Navigator.pop(context, true);
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
    final card = isDark ? const Color(0xFF17171F) : Colors.white;
    final ink = isDark ? const Color(0xFFF0F2F8) : const Color(0xFF1A1A1A);
    final muted = isDark ? const Color(0xFF7A80A0) : const Color(0xFF888888);
    final fieldBorder = isDark
        ? Colors.white.withValues(alpha: 0.12)
        : const Color(0xFFE5E5EA);

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Container(
        decoration: BoxDecoration(
          color: card,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(bottom: 14),
                decoration: BoxDecoration(
                  color: Colors.grey.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
            ),
            Row(
              children: [
                Text(
                  '写回答',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: ink,
                  ),
                ),
                const Spacer(),
                TextButton(
                  onPressed: _canPost ? _submit : null,
                  style: TextButton.styleFrom(
                    backgroundColor: _canPost
                        ? _primary
                        : (isDark
                              ? Colors.white.withValues(alpha: 0.08)
                              : const Color(0xFFECECEF)),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 8,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: _submitting
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                            strokeWidth: 1.6,
                            color: Colors.white,
                          ),
                        )
                      : Text(
                          '发布',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: _canPost ? Colors.white : muted,
                          ),
                        ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            // 问题引用——蓝色左边框
            if (widget.questionText.isNotEmpty)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
                decoration: BoxDecoration(
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.04)
                      : const Color(0xFFF5F5F7),
                  borderRadius: BorderRadius.circular(10),
                  border: const Border(
                    left: BorderSide(color: _primary, width: 3),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('回答的问题', style: TextStyle(fontSize: 11, color: muted)),
                    const SizedBox(height: 4),
                    Text(
                      widget.questionText,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 14,
                        height: 1.4,
                        fontWeight: FontWeight.w500,
                        color: ink,
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 12),
            // 输入区
            Container(
              constraints: const BoxConstraints(minHeight: 150, maxHeight: 260),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: fieldBorder),
              ),
              child: SingleChildScrollView(
                child: TextField(
                  controller: _ctrl,
                  focusNode: _focus,
                  maxLines: null,
                  inputFormatters: [LengthLimitingTextInputFormatter(_maxLen)],
                  style: TextStyle(fontSize: 15, height: 1.55, color: ink),
                  decoration: InputDecoration(
                    isCollapsed: true,
                    border: InputBorder.none,
                    hintText: '写下你的回答，支持 LaTeX 公式和代码…',
                    hintStyle: TextStyle(
                      fontSize: 15,
                      color: muted,
                      height: 1.55,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 10),
            // 底部：LaTeX / 代码 快捷 + 字数计数
            Row(
              children: [
                _quickBtn(
                  Icons.functions,
                  '公式',
                  () => _wrap('\$\$ ', ' \$\$'),
                  muted,
                ),
                const SizedBox(width: 6),
                _quickBtn(
                  Icons.code,
                  '代码',
                  () => _wrap('\n```\n', '\n```\n'),
                  muted,
                ),
                const Spacer(),
                Text(
                  '${_ctrl.text.characters.length} / $_maxLen',
                  style: TextStyle(fontSize: 12, color: muted),
                ),
              ],
            ),
            SizedBox(height: MediaQuery.of(context).padding.bottom > 0 ? 4 : 8),
          ],
        ),
      ),
    );
  }

  Widget _quickBtn(
    IconData icon,
    String tooltip,
    VoidCallback onTap,
    Color color,
  ) {
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: Icon(icon, size: 20, color: color),
        ),
      ),
    );
  }
}
