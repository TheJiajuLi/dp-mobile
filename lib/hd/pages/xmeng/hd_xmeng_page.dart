import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../features/ai/models/ai_conversation_model.dart';
import '../../../features/ai/screens/xiaomeng_chat_screen.dart';
import '../../../features/ai/screens/xiaomeng_screen.dart';

const _primary = Color(0xFF6366F1);

// HD 小梦右栏选中态：conversationId 命中历史对话；newMessage 命中「欢迎页发送/点
// 提示」新起的对话（可为空串=空白新对话）；两者都为 null = 显示欢迎页 XiaomengScreen。
// 用同页状态驱动复用现成 screen，不 push 新路由、不写 HD 专用对话组件。
class HdXmengSelection {
  final String? conversationId;
  final String? newMessage;
  const HdXmengSelection({this.conversationId, this.newMessage});
  const HdXmengSelection.welcome() : conversationId = null, newMessage = null;
}

final hdXmengSelectionProvider = StateProvider<HdXmengSelection>(
  (ref) => const HdXmengSelection.welcome(),
);

// 小梦——HD 宽屏双栏：左栏(240) =「+ 新对话」+ 历史会话列表；右栏(flex) = 当前对话
// XiaomengChatScreen（按 selection.conversationId/newMessage 重建），无选中时显示
// 欢迎页 XiaomengScreen(embedded)。左栏点击/发送只改 provider，右栏 watch 后重建。
class HdXmengPage extends ConsumerStatefulWidget {
  const HdXmengPage({super.key});

  @override
  ConsumerState<HdXmengPage> createState() => _HdXmengPageState();
}

class _HdXmengPageState extends ConsumerState<HdXmengPage> {
  List<AiConversation> _conversations = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (!mounted) return;
    final res = await ref
        .read(apiClientProvider)
        .get('/auth/xmeng/conversations');
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (res.success && res.data is Map) {
        final list = ((res.data as Map)['conversations'] as List?) ?? const [];
        _conversations = list
            .map(
              (c) =>
                  AiConversation.fromJson(Map<String, dynamic>.from(c as Map)),
            )
            .toList();
      }
    });
  }

  // 历史标题被后端拼的「AI 偏好语言」指令顶了前缀，展示层剥掉露出真实问题
  // （与 XiaomengHistoryScreen._cleanTitle 同一套规则）
  String _cleanTitle(String raw) {
    var t = raw.trim();
    t = t.replaceFirst(RegExp(r'^\[[^\]]*\]\s+'), '');
    t = t.replaceFirst(RegExp(r'^\[(请用|Please respond)[^\n]*'), '').trim();
    for (final line in t.split('\n')) {
      if (line.trim().isNotEmpty) return line.trim();
    }
    return raw.trim();
  }

  void _selectConversation(String id) {
    ref.read(hdXmengSelectionProvider.notifier).state = HdXmengSelection(
      conversationId: id,
    );
  }

  void _newChat() {
    ref.read(hdXmengSelectionProvider.notifier).state =
        const HdXmengSelection.welcome();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final divider = isDark
        ? Colors.white.withValues(alpha: 0.08)
        : const Color(0xFFECECEC);

    return Row(
      children: [
        SizedBox(width: 240, child: _leftPanel(isDark, divider)),
        VerticalDivider(width: 0.5, thickness: 0.5, color: divider),
        Expanded(child: _rightPanel()),
      ],
    );
  }

  Widget _leftPanel(bool isDark, Color divider) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // + 新对话
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 16, 12, 12),
          child: GestureDetector(
            onTap: _newChat,
            child: Container(
              height: 40,
              decoration: BoxDecoration(
                color: isDark
                    ? _primary.withValues(alpha: 0.18)
                    : const Color(0xFFEEF0FF),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.add, size: 18, color: _primary),
                  SizedBox(width: 6),
                  Text(
                    '新对话',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: _primary,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _conversations.isEmpty
              ? Center(
                  child: Text(
                    '还没有对话记录',
                    style: TextStyle(fontSize: 13, color: Colors.grey[400]),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView.builder(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    itemCount: _conversations.length,
                    itemBuilder: (_, i) => _row(_conversations[i], isDark),
                  ),
                ),
        ),
      ],
    );
  }

  Widget _row(AiConversation conv, bool isDark) {
    final sel = ref.watch(hdXmengSelectionProvider);
    final active = sel.conversationId == conv.id;
    return GestureDetector(
      onTap: () => _selectConversation(conv.id),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        decoration: BoxDecoration(
          color: active
              ? (isDark
                    ? _primary.withValues(alpha: 0.15)
                    : const Color(0xFFEEF0FF))
              : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            Icon(
              Icons.chat_bubble_outline,
              size: 16,
              color: active ? _primary : Colors.grey[500],
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                _cleanTitle(conv.title),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: active ? FontWeight.w600 : FontWeight.w500,
                  color: active
                      ? _primary
                      : Theme.of(context).textTheme.bodyLarge?.color,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _rightPanel() {
    final sel = ref.watch(hdXmengSelectionProvider);
    if (sel.conversationId != null) {
      return XiaomengChatScreen(
        key: ValueKey('conv:${sel.conversationId}'),
        conversationId: sel.conversationId,
        showBackButton: false,
      );
    }
    if (sel.newMessage != null) {
      return XiaomengChatScreen(
        key: ValueKey('new:${sel.newMessage}'),
        initialMessage: sel.newMessage!.isEmpty ? null : sel.newMessage,
        showBackButton: false,
      );
    }
    return XiaomengScreen(
      embedded: true,
      onOpenChat: (prefill) {
        ref.read(hdXmengSelectionProvider.notifier).state = HdXmengSelection(
          newMessage: prefill ?? '',
        );
      },
    );
  }
}
