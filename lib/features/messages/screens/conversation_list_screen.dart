import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../l10n/generated/app_localizations.dart';
import '../models/conversation_model.dart';
import '../providers/messages_provider.dart';
import '../utils/message_avatar.dart';

sealed class _Row {}

class _DateRow extends _Row {
  final DateTime day;
  _DateRow(this.day);
}

class _ConvRow extends _Row {
  final Conversation conv;
  _ConvRow(this.conv);
}

class ConversationListScreen extends ConsumerStatefulWidget {
  const ConversationListScreen({super.key});
  @override
  ConsumerState<ConversationListScreen> createState() =>
      _ConversationListScreenState();
}

class _ConversationListScreenState
    extends ConsumerState<ConversationListScreen> {
  final _searchCtrl = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  String _dateLabel(BuildContext context, DateTime day) {
    final l10n = AppLocalizations.of(context)!;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    if (day == today) return l10n.today;
    if (day == yesterday) return l10n.yesterday;
    return '${day.month}月${day.day}日';
  }

  // 会话本身没有"置顶"/"在线"这类字段，唯一能真实做的分组只有按最后
  // 一条消息的日期——跟聊天页的日期分隔用的是同一套口径
  List<_Row> _buildRows(List<Conversation> conversations) {
    final rows = <_Row>[];
    DateTime? lastDay;
    for (final conv in conversations) {
      final ts = conv.lastMessageAt;
      final day = ts == null
          ? DateTime.fromMillisecondsSinceEpoch(0)
          : DateTime(
              DateTime.fromMillisecondsSinceEpoch(ts).year,
              DateTime.fromMillisecondsSinceEpoch(ts).month,
              DateTime.fromMillisecondsSinceEpoch(ts).day,
            );
      if (lastDay == null || day != lastDay) {
        rows.add(_DateRow(day));
        lastDay = day;
      }
      rows.add(_ConvRow(conv));
    }
    return rows;
  }

  void _comingSoon(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final all = ref.watch(conversationsProvider);
    final conversations = _query.isEmpty
        ? all
        : all
              .where(
                (c) => c.otherUsername.toLowerCase().contains(
                  _query.toLowerCase(),
                ),
              )
              .toList();
    final rows = _buildRows(conversations);

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 16, 0),
              child: Row(
                children: [
                  IconButton(
                    onPressed: () => context.pop(),
                    icon: const Icon(Icons.arrow_back_ios, size: 18),
                  ),
                  Text(
                    l10n.tabDirectMessages,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: TextField(
                controller: _searchCtrl,
                onChanged: (v) => setState(() => _query = v),
                decoration: InputDecoration(
                  hintText: l10n.searchConversationsHint,
                  prefixIcon: const Icon(Icons.search, size: 20),
                  filled: true,
                  isDense: true,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
            // 置顶/在线——会话模型目前都没有对应字段（没有 pinned 标记，
            // 也没有在线状态系统），保留参考图里的视觉位置，点了给明确的
            // "即将上线"反馈，不假装能筛出真实结果
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  _disabledChip(
                    Icons.push_pin_outlined,
                    l10n.pinnedChipLabel,
                    () => _comingSoon(l10n.pinnedConversationsComingSoon),
                  ),
                  const SizedBox(width: 8),
                  _disabledChip(
                    Icons.circle,
                    l10n.onlineChipLabel,
                    () => _comingSoon(l10n.onlineStatusComingSoon),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 4),
            Expanded(
              child: conversations.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(
                            Icons.chat_bubble_outline,
                            size: 56,
                            color: Colors.grey,
                          ),
                          const SizedBox(height: 12),
                          Text(
                            l10n.noDirectMessagesYet,
                            style: const TextStyle(
                              color: Colors.grey,
                              fontSize: 15,
                            ),
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      itemCount: rows.length,
                      itemBuilder: (ctx, i) {
                        final row = rows[i];
                        return switch (row) {
                          _DateRow(:final day) => Padding(
                            padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
                            child: Text(
                              _dateLabel(context, day),
                              style: const TextStyle(
                                fontSize: 11,
                                color: Colors.grey,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          _ConvRow(:final conv) => ListTile(
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 6,
                            ),
                            onTap: () => context.push(
                              '/messages/chat/${conv.id}',
                              extra: conv,
                            ),
                            leading: buildMessageAvatar(
                              conv.otherAvatar,
                              conv.otherUsername,
                            ),
                            title: Row(
                              children: [
                                Text(
                                  conv.otherUsername,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 15,
                                  ),
                                ),
                                const Spacer(),
                                Text(
                                  conv.lastMessageAt == null
                                      ? ''
                                      : messageTimeAgo(
                                          l10n,
                                          conv.lastMessageAt!,
                                        ),
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey,
                                  ),
                                ),
                              ],
                            ),
                            subtitle: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    conv.lastMessage ?? '',
                                    style: const TextStyle(
                                      fontSize: 13,
                                      color: Colors.grey,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                if (conv.unreadCount > 0)
                                  Container(
                                    margin: const EdgeInsets.only(left: 8),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 6,
                                      vertical: 2,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.red,
                                      borderRadius: BorderRadius.circular(99),
                                    ),
                                    child: Text(
                                      '${conv.unreadCount}',
                                      style: const TextStyle(
                                        fontSize: 11,
                                        color: Colors.white,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        };
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _disabledChip(IconData icon, String label, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Theme.of(context).dividerColor),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 12, color: Colors.grey),
            const SizedBox(width: 4),
            Text(
              label,
              style: const TextStyle(fontSize: 11, color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }
}
