import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../l10n/generated/app_localizations.dart';
import '../../../shared/utils/online_status.dart';
import '../../../shared/widgets/online_dot.dart';
import '../../../shared/widgets/rounded_list_card.dart';
import '../models/conversation_model.dart';
import '../providers/messages_provider.dart';
import '../utils/message_avatar.dart';

// 同一天的会话归到一张大圆角卡片里，卡片上方是灰色日期标签
class _DateGroup {
  final DateTime day;
  final List<Conversation> convs = [];
  _DateGroup(this.day);
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
  bool _onlineOnly = false;

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
  List<_DateGroup> _buildGroups(List<Conversation> conversations) {
    final groups = <_DateGroup>[];
    for (final conv in conversations) {
      final ts = conv.lastMessageAt;
      final day = ts == null
          ? DateTime.fromMillisecondsSinceEpoch(0)
          : DateTime(
              DateTime.fromMillisecondsSinceEpoch(ts).year,
              DateTime.fromMillisecondsSinceEpoch(ts).month,
              DateTime.fromMillisecondsSinceEpoch(ts).day,
            );
      if (groups.isEmpty || groups.last.day != day) {
        groups.add(_DateGroup(day));
      }
      groups.last.convs.add(conv);
    }
    return groups;
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
    var conversations = _query.isEmpty
        ? all
        : all
              .where(
                (c) => c.otherUsername.toLowerCase().contains(
                  _query.toLowerCase(),
                ),
              )
              .toList();
    // 「在线」筛选：只留对方在线/最近活跃的会话
    if (_onlineOnly) {
      conversations = conversations
          .where(
            (c) =>
                OnlineStatusHelper.fromLastSeen(c.otherLastSeenAt) !=
                OnlineStatus.offline,
          )
          .toList();
    }
    final groups = _buildGroups(conversations);

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
                  // 主题默认的 0xFFF5F5F5 太浅、跟背景几乎分不出——加深到跟
                  // 搜索页搜索框一致的可见灰
                  fillColor: Theme.of(context).brightness == Brightness.dark
                      ? const Color(0xFF3A3A3C)
                      : const Color(0xFFE8E8ED),
                  isDense: true,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
            // 「在线」已经有真实数据（会话带 other_last_seen_at），做成真实的
            // 筛选开关；「置顶」还没有 pinned 字段，仍是"即将上线"占位
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
                  _filterChip(
                    Icons.circle,
                    l10n.onlineChipLabel,
                    selected: _onlineOnly,
                    onTap: () => setState(() => _onlineOnly = !_onlineOnly),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 4),
            Expanded(
              // 点会话列表空白处收起搜索键盘——ListView 默认不 unfocus，
              // opaque 让整块（含条目间空隙/空状态）都接住 tap；会话卡片是
              // 各自的 GestureDetector，子级优先命中，照常可点进聊天
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => FocusScope.of(context).unfocus(),
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
                        padding: const EdgeInsets.only(top: 4, bottom: 16),
                        itemCount: groups.length,
                        itemBuilder: (ctx, i) =>
                            _buildGroupCard(groups[i], l10n),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // 一个日期分组 = 灰色日期标签 + 一张大圆角卡片，卡片里放当天的全部会话——
  // 跟消息主页/通知页/群组列表同一套 RoundedListCard 配方，不是自己另起
  // 一份卡片样式
  Widget _buildGroupCard(_DateGroup group, AppLocalizations l10n) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 16, 6),
          child: Text(
            _dateLabel(context, group.day),
            style: const TextStyle(
              fontSize: 11,
              color: Colors.grey,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        RoundedListCard(
          children: group.convs.map((c) => _convTile(c, l10n)).toList(),
        ),
      ],
    );
  }

  Widget _convTile(Conversation conv, AppLocalizations l10n) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      onTap: () => context.push('/messages/chat/${conv.id}', extra: conv),
      leading: Stack(
        clipBehavior: Clip.none,
        children: [
          buildMessageAvatar(conv.otherAvatar, conv.otherUsername),
          Positioned(
            bottom: -1,
            right: -1,
            child: OnlineDot(lastSeenAt: conv.otherLastSeenAt),
          ),
        ],
      ),
      title: Row(
        children: [
          Text(
            conv.otherUsername,
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
          ),
          const Spacer(),
          Text(
            conv.lastMessageAt == null
                ? ''
                : messageTimeAgo(l10n, conv.lastMessageAt!),
            style: const TextStyle(fontSize: 12, color: Colors.grey),
          ),
        ],
      ),
      subtitle: Row(
        children: [
          Expanded(
            child: Text(
              conv.lastMessage ?? '',
              style: const TextStyle(fontSize: 13, color: Colors.grey),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (conv.unreadCount > 0)
            Container(
              margin: const EdgeInsets.only(left: 8),
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
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
    );
  }

  // 可切换的筛选 chip——选中时主题色高亮，「在线」的圆点选中时是绿色
  Widget _filterChip(
    IconData icon,
    String label, {
    required bool selected,
    required VoidCallback onTap,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    const primary = Color(0xFF6366F1);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: selected
              ? (isDark
                    ? primary.withValues(alpha: 0.15)
                    : const Color(0xFFEEF0FF))
              : Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? primary : Theme.of(context).dividerColor,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 12,
              color: selected ? const Color(0xFF22C55E) : Colors.grey,
            ),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                color: selected ? primary : Colors.grey,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
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
