import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_client.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../utils/message_avatar.dart';

class InviteListScreen extends ConsumerStatefulWidget {
  const InviteListScreen({super.key});

  @override
  ConsumerState<InviteListScreen> createState() => _InviteListScreenState();
}

class _InviteListScreenState extends ConsumerState<InviteListScreen> {
  List<Map<String, dynamic>> _invites = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final res = await ref
        .read(apiClientProvider)
        .get('/auth/questions/invites');
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (res.success && res.data != null) {
        _invites = ((res.data['invites'] as List?) ?? [])
            .map((i) => Map<String, dynamic>.from(i as Map))
            .toList();
      }
    });
  }

  Future<void> _accept(Map<String, dynamic> invite, int index) async {
    final res = await ref
        .read(apiClientProvider)
        .post(
          '/auth/questions/invites/${invite['id']}/respond',
          data: {'action': 'accept'},
        );
    if (!mounted) return;
    if (!res.success) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(res.message ?? '操作失败，请重试')));
      return;
    }
    setState(
      () => _invites[index] = {..._invites[index], 'status': 'accepted'},
    );
    context.push(
      '/answer-question',
      extra: {
        'questionId': invite['question_id'],
        'questionText': invite['question_text'],
        'domain': invite['domain'] ?? '',
      },
    );
  }

  Future<void> _ignore(Map<String, dynamic> invite, int index) async {
    final res = await ref
        .read(apiClientProvider)
        .post(
          '/auth/questions/invites/${invite['id']}/respond',
          data: {'action': 'ignore'},
        );
    if (!mounted) return;
    if (!res.success) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(res.message ?? '操作失败，请重试')));
      return;
    }
    setState(() => _invites.removeAt(index));
  }

  Future<void> _clearAll() async {
    final pending = _invites.where((i) => i['status'] != 'accepted').toList();
    if (pending.isEmpty) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('忽略所有邀请'),
        content: Text('确定忽略全部 ${pending.length} 个邀请？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(
              '确定忽略',
              style: TextStyle(color: Color(0xFFEF4444)),
            ),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;

    final results = await Future.wait(
      pending.map(
        (inv) => ref
            .read(apiClientProvider)
            .post(
              '/auth/questions/invites/${inv['id']}/respond',
              data: {'action': 'ignore'},
            ),
      ),
    );
    if (!mounted) return;
    // 只摘掉真的成功了的那些，失败的留在列表里，不能假装全部处理完了
    final failedIds = <dynamic>{};
    for (var i = 0; i < pending.length; i++) {
      if (!results[i].success) failedIds.add(pending[i]['id']);
    }
    setState(() {
      _invites.removeWhere(
        (inv) => inv['status'] != 'accepted' && !failedIds.contains(inv['id']),
      );
    });
    if (failedIds.isNotEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('部分邀请忽略失败，请重试')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final pendingCount = _invites
        .where((i) => i['status'] != 'accepted')
        .length;

    return Scaffold(
      // 浅色统一首页米白 #FAFAF8；深色不变。AppBar 透明会透出这个底色
      backgroundColor: isDark
          ? Theme.of(context).scaffoldBackgroundColor
          : const Color(0xFFFAFAF8),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, size: 18),
          onPressed: () => context.pop(),
        ),
        title: Row(
          children: [
            const Text(
              '邀请回答',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            if (pendingCount > 0) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFFEF4444),
                  borderRadius: BorderRadius.circular(99),
                ),
                child: Text(
                  '$pendingCount',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ],
        ),
        actions: [
          if (pendingCount > 0)
            TextButton(
              onPressed: _clearAll,
              child: const Text(
                '全部忽略',
                style: TextStyle(fontSize: 13, color: Color(0xFFEF4444)),
              ),
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _invites.isEmpty
          ? _buildEmpty()
          : RefreshIndicator(
              onRefresh: _load,
              // 全部邀请归到一张大圆角卡片里，卡片内每条邀请之间用
              // _InviteItem 自带的底部分隔线隔开——跟私信/通知列表统一
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
                children: [
                  Container(
                    decoration: BoxDecoration(
                      color: Theme.of(context).cardColor,
                      borderRadius: BorderRadius.circular(16),
                      border: isDark
                          ? Border.all(
                              color: Theme.of(context).dividerColor,
                              width: 0.5,
                            )
                          : null,
                      boxShadow: isDark
                          ? null
                          : [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.03),
                                blurRadius: 10,
                                offset: const Offset(0, 3),
                              ),
                            ],
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: Column(
                      children: [
                        for (var i = 0; i < _invites.length; i++)
                          _InviteItem(
                            invite: _invites[i],
                            isDark: isDark,
                            onAccept: () => _accept(_invites[i], i),
                            onIgnore: () => _ignore(_invites[i], i),
                          ),
                        if (pendingCount > 0)
                          GestureDetector(
                            onTap: _clearAll,
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              decoration: BoxDecoration(
                                border: Border(
                                  top: BorderSide(
                                    color: isDark
                                        ? Colors.white.withValues(alpha: 0.06)
                                        : const Color(0xFFEBEBEB),
                                    width: 0.5,
                                  ),
                                ),
                              ),
                              child: const Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.delete_outline,
                                    size: 16,
                                    color: Color(0xFFEF4444),
                                  ),
                                  SizedBox(width: 6),
                                  Text(
                                    '一键忽略所有邀请',
                                    style: TextStyle(
                                      fontSize: 13,
                                      color: Color(0xFFEF4444),
                                    ),
                                  ),
                                ],
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

  Widget _buildEmpty() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: const BoxDecoration(
              color: Color(0xFFF5F5F5),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.question_answer_outlined,
              size: 24,
              color: Color(0xFFCCCCCC),
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            '暂无待处理邀请',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 5),
          Text(
            '当有人邀请你回答问题时\n会在这里显示',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              height: 1.6,
              color: Colors.grey[400],
            ),
          ),
        ],
      ),
    );
  }
}

class _InviteItem extends StatelessWidget {
  final Map<String, dynamic> invite;
  final bool isDark;
  final VoidCallback onAccept;
  final VoidCallback onIgnore;

  const _InviteItem({
    required this.invite,
    required this.isDark,
    required this.onAccept,
    required this.onIgnore,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final isAccepted = invite['status'] == 'accepted';
    final askerName = (invite['asker_name'] as String?) ?? '匿名用户';
    final questionText = (invite['question_text'] as String?) ?? '';
    final domain = (invite['domain'] as String?) ?? '';
    final createdAt = (invite['question_created_at'] as num?)?.toInt();

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: isDark
                ? Colors.white.withValues(alpha: 0.06)
                : const Color(0xFFEBEBEB),
            width: 0.5,
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              buildMessageAvatar(
                invite['asker_avatar'] as String?,
                askerName,
                radius: 14,
              ),
              const SizedBox(width: 8),
              Text(
                '$askerName · 邀请你回答',
                style: TextStyle(
                  fontSize: 12,
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.4)
                      : Colors.grey[500],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            questionText,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              height: 1.4,
              color: isDark
                  ? Colors.white.withValues(alpha: 0.9)
                  : const Color(0xFF1A1A1A),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              if (domain.isNotEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 7,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEEF0FF),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    domain,
                    style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF6366F1),
                    ),
                  ),
                ),
              const Spacer(),
              Text(
                createdAt != null ? messageTimeAgo(l10n, createdAt * 1000) : '',
                style: TextStyle(
                  fontSize: 10,
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.3)
                      : Colors.grey[400],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (isAccepted)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFFF0FFF4),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: const Color(0xFF16A34A).withValues(alpha: 0.2),
                  width: 0.5,
                ),
              ),
              child: const Text(
                '✓ 已接受',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  color: Color(0xFF16A34A),
                  fontWeight: FontWeight.w500,
                ),
              ),
            )
          else
            Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    onTap: onAccept,
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 9),
                      decoration: BoxDecoration(
                        color: isDark
                            ? const Color(0xFF6366F1)
                            : const Color(0xFF1A1A1A),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Text(
                        '接受并回答',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: GestureDetector(
                    onTap: onIgnore,
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 9),
                      decoration: BoxDecoration(
                        color: isDark
                            ? Colors.white.withValues(alpha: 0.05)
                            : const Color(0xFFF5F5F5),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: isDark
                              ? Colors.white.withValues(alpha: 0.1)
                              : const Color(0xFFE5E5E5),
                          width: 0.5,
                        ),
                      ),
                      child: Text(
                        '忽略',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 13,
                          color: isDark
                              ? Colors.white.withValues(alpha: 0.5)
                              : const Color(0xFF555555),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}
