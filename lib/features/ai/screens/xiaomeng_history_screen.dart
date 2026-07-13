import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_client.dart';
import '../models/ai_conversation_model.dart';

const _primary = Color(0xFF6366F1);

// 历史对话——GET /auth/xmeng/conversations 是真实接口，返回
// {conversations:[{id,title,created_at,updated_at}]}。title 是后端建
// 对话时自动截的首条用户消息前20个字，不是另外生成的"智能摘要"，所以
// 这里只有一行标题，没有 Demo 里"标题+完整消息预览"两行——后端没有单独
// 存一份消息预览，硬做第二行只能是编的
class XiaomengHistoryScreen extends ConsumerStatefulWidget {
  const XiaomengHistoryScreen({super.key});

  @override
  ConsumerState<XiaomengHistoryScreen> createState() =>
      _XiaomengHistoryScreenState();
}

class _XiaomengHistoryScreenState extends ConsumerState<XiaomengHistoryScreen> {
  List<AiConversation> _conversations = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (!mounted) return;
    if (_conversations.isEmpty) setState(() => _loading = true);
    final res = await ref.read(apiClientProvider).get('/auth/xmeng/conversations');
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (res.success && res.data is Map) {
        final list = ((res.data as Map)['conversations'] as List?) ?? const [];
        _conversations = list
            .map((c) => AiConversation.fromJson(Map<String, dynamic>.from(c as Map)))
            .toList();
      }
    });
  }

  Future<void> _confirmDelete(AiConversation conv) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除此对话'),
        content: Text('删除"${conv.title}"后无法恢复'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除', style: TextStyle(color: Color(0xFFDC2626))),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    final res = await ref
        .read(apiClientProvider)
        .delete('/auth/xmeng/conversations/${conv.id}');
    if (!mounted) return;
    if (res.success) {
      setState(() => _conversations.removeWhere((c) => c.id == conv.id));
    } else {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(res.message ?? '删除失败，请稍后重试')));
    }
  }

  // 清空全部——顶栏扫帚图标的handler，之前漏写了，点了就是个死按钮。
  // 复用 DELETE /auth/xmeng/conversations（不带id，后端按当前用户清空
  // 全部），跟单条删除同一套确认弹窗写法
  Future<void> _confirmClearAll() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('清空历史对话'),
        content: Text('将删除全部 ${_conversations.length} 条对话记录，清空后无法恢复'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('清空', style: TextStyle(color: Color(0xFFDC2626))),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    final res =
        await ref.read(apiClientProvider).delete('/auth/xmeng/conversations');
    if (!mounted) return;
    if (res.success) {
      setState(() => _conversations = []);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('历史对话已清空')));
    } else {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(res.message ?? '清空失败，请稍后重试')));
    }
  }

  // 后端没有存"这个对话属于哪个类型"，用标题里的关键词粗略猜一个图标——
  // 纯客户端的近似展示，不是真的分类，猜不中就落到默认的对话图标
  IconData _iconFor(String title) {
    if (RegExp(r'代码|python|sql|调试|bug', caseSensitive: false).hasMatch(title)) {
      return Icons.code;
    }
    if (RegExp(r'公式|证明|推导|计算|定理').hasMatch(title)) {
      return Icons.functions;
    }
    if (RegExp(r'分析|数据|可视化|建模|样本').hasMatch(title)) {
      return Icons.bar_chart;
    }
    return Icons.chat_bubble_outline;
  }

  String _timeLabel(int updatedAt) {
    final d = DateTime.fromMillisecondsSinceEpoch(updatedAt);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final that = DateTime(d.year, d.month, d.day);
    final diffDays = today.difference(that).inDays;
    if (diffDays == 0) {
      return '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
    }
    if (diffDays == 1) return '昨天';
    return '$diffDays天前';
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));

    final todayList = <AiConversation>[];
    final yesterdayList = <AiConversation>[];
    final earlierList = <AiConversation>[];
    for (final c in _conversations) {
      final d = DateTime.fromMillisecondsSinceEpoch(c.updatedAt);
      final day = DateTime(d.year, d.month, d.day);
      if (day == today) {
        todayList.add(c);
      } else if (day == yesterday) {
        yesterdayList.add(c);
      } else {
        earlierList.add(c);
      }
    }

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: () => context.pop(),
                    child: Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        color: isDark
                            ? Colors.white.withValues(alpha: 0.06)
                            : const Color(0xFFF0F0F0),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.arrow_back_ios, size: 16),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      '历史对话',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        color: Theme.of(context).textTheme.bodyLarge?.color,
                      ),
                    ),
                  ),
                  // 清空历史对话——有记录才显示，避免空列表时点了个寂寞；
                  // 没记录时留一个等宽占位，保持标题居中
                  if (_conversations.isEmpty)
                    const SizedBox(width: 34, height: 34)
                  else
                    GestureDetector(
                      onTap: _confirmClearAll,
                      child: const SizedBox(
                        width: 34,
                        height: 34,
                        child: Icon(Icons.delete_sweep_outlined, size: 18),
                      ),
                    ),
                ],
              ),
            ),
            const Divider(height: 20, thickness: 0.5),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _conversations.isEmpty
                  ? _buildEmpty()
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        children: [
                          if (todayList.isNotEmpty) _section('今天', todayList, isDark),
                          if (yesterdayList.isNotEmpty)
                            _section('昨天', yesterdayList, isDark),
                          if (earlierList.isNotEmpty)
                            _section('更早', earlierList, isDark),
                        ],
                      ),
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
          Icon(Icons.chat_bubble_outline, size: 44, color: Colors.grey[300]),
          const SizedBox(height: 12),
          Text(
            '还没有对话记录',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: Colors.grey[400],
            ),
          ),
        ],
      ),
    );
  }

  Widget _section(String label, List<AiConversation> list, bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: Colors.grey[500],
            ),
          ),
        ),
        ...list.map((c) => _row(c, isDark)),
      ],
    );
  }

  Widget _row(AiConversation conv, bool isDark) {
    return GestureDetector(
      onTap: () => context.push(
        '/xiaomeng/chat',
        extra: {'conversationId': conv.id},
      ),
      onLongPress: () => _confirmDelete(conv),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: isDark
                  ? Colors.white.withValues(alpha: 0.06)
                  : const Color(0xFFF0F0F0),
              width: 0.5,
            ),
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: isDark
                    ? _primary.withValues(alpha: 0.15)
                    : const Color(0xFFEEF0FF),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(_iconFor(conv.title), size: 17, color: _primary),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                conv.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Theme.of(context).textTheme.bodyLarge?.color,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              _timeLabel(conv.updatedAt),
              style: TextStyle(fontSize: 11, color: Colors.grey[400]),
            ),
          ],
        ),
      ),
    );
  }
}
