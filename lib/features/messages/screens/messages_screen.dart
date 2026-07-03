import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_client.dart';
import '../models/conversation_model.dart';
import '../models/notification_model.dart';
import '../providers/messages_provider.dart';

const _primary = Color(0xFF6366F1);

String _initial(String? name) {
  if (name == null || name.isEmpty) return '?';
  return name.substring(0, 1).toUpperCase();
}

class MessagesScreen extends ConsumerStatefulWidget {
  const MessagesScreen({super.key});
  @override
  ConsumerState<MessagesScreen> createState() => _MessagesScreenState();
}

class _MessagesScreenState extends ConsumerState<MessagesScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabCtrl;
  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 3, vsync: this);
    _loadData();
    // 每 30 秒轮询一次
    _pollTimer = Timer.periodic(const Duration(seconds: 30), (_) => _loadData());
  }

  Future<void> _loadData() async {
    await ref.read(notificationsProvider.notifier).fetch();
    await ref.read(conversationsProvider.notifier).fetch();
    final res = await ref.read(apiClientProvider).get('/auth/notifications/unread-count');
    if (res.success && res.data != null && mounted) {
      ref.read(unreadCountProvider.notifier).state =
          (res.data['unread'] as num?)?.toInt() ?? 0;
    }
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    _pollTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final notifications = ref.watch(notificationsProvider);
    final conversations = ref.watch(conversationsProvider);
    final unread = ref.watch(unreadCountProvider);

    return Scaffold(
      backgroundColor: const Color(0xFFF8F8F8),
      body: SafeArea(
        child: Column(
          children: [
            // 顶部栏
            Container(
              color: Colors.white,
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
              child: Column(
                children: [
                  Row(
                    children: [
                      const Text('消息',
                          style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
                      const Spacer(),
                      if (unread > 0)
                        GestureDetector(
                          onTap: () => ref.read(notificationsProvider.notifier).markAllRead(),
                          child: const Text('全部已读',
                              style: TextStyle(fontSize: 14, color: _primary)),
                        ),
                      const SizedBox(width: 12),
                      const Icon(Icons.search, size: 22),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TabBar(
                    controller: _tabCtrl,
                    labelColor: _primary,
                    unselectedLabelColor: Colors.grey,
                    labelStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                    unselectedLabelStyle:
                        const TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
                    indicatorColor: _primary,
                    indicatorWeight: 2,
                    tabs: [
                      Tab(child: _tabLabel('通知', unread)),
                      Tab(
                          child: _tabLabel('私信',
                              conversations.fold<int>(0, (s, c) => s + c.unreadCount))),
                      const Tab(text: '群组'),
                    ],
                  ),
                ],
              ),
            ),

            // 内容
            Expanded(
              child: TabBarView(
                controller: _tabCtrl,
                children: [
                  _NotifTab(notifications: notifications),
                  _DmTab(conversations: conversations),
                  const _GroupTab(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _tabLabel(String text, int count) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(text),
        if (count > 0) ...[
          const SizedBox(width: 4),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
            decoration: BoxDecoration(color: Colors.red, borderRadius: BorderRadius.circular(99)),
            child: Text('$count',
                style: const TextStyle(
                    fontSize: 10, color: Colors.white, fontWeight: FontWeight.w700)),
          ),
        ],
      ],
    );
  }
}

// 通知 tab
class _NotifTab extends StatelessWidget {
  final List<AppNotification> notifications;
  const _NotifTab({required this.notifications});

  String _timeAgo(int tsMs) {
    final diff = DateTime.now().difference(DateTime.fromMillisecondsSinceEpoch(tsMs));
    if (diff.inMinutes < 1) return '刚刚';
    if (diff.inMinutes < 60) return '${diff.inMinutes}分钟前';
    if (diff.inHours < 24) return '${diff.inHours}小时前';
    if (diff.inDays < 30) return '${diff.inDays}天前';
    return '${diff.inDays ~/ 30}个月前';
  }

  Color _typeColor(String type) {
    switch (type) {
      case 'like':
        return Colors.red;
      case 'comment':
        return _primary;
      case 'follow':
        return const Color(0xFF34C759);
      default:
        return Colors.orange;
    }
  }

  IconData _typeIcon(String type) {
    switch (type) {
      case 'like':
        return Icons.favorite;
      case 'comment':
        return Icons.chat_bubble;
      case 'follow':
        return Icons.person_add;
      default:
        return Icons.notifications;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (notifications.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.notifications_none, size: 56, color: Colors.grey),
            SizedBox(height: 12),
            Text('暂无通知', style: TextStyle(color: Colors.grey, fontSize: 15)),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: notifications.length,
      itemBuilder: (ctx, i) {
        final n = notifications[i];
        return Container(
          color: n.isRead ? Colors.transparent : _primary.withValues(alpha: 0.04),
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            leading: Stack(
              clipBehavior: Clip.none,
              children: [
                CircleAvatar(
                  radius: 22,
                  backgroundColor: _primary.withValues(alpha: 0.15),
                  child: Text(_initial(n.fromUsername ?? '系'),
                      style: const TextStyle(fontWeight: FontWeight.w700, color: _primary)),
                ),
                Positioned(
                  bottom: -2,
                  right: -2,
                  child: Container(
                    width: 18,
                    height: 18,
                    decoration: BoxDecoration(
                        color: _typeColor(n.type),
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 1.5)),
                    child: Icon(_typeIcon(n.type), size: 10, color: Colors.white),
                  ),
                ),
              ],
            ),
            title: Text(
              n.content ?? n.title ?? '',
              style: TextStyle(
                  fontSize: 14, fontWeight: n.isRead ? FontWeight.w400 : FontWeight.w500),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle:
                Text(_timeAgo(n.createdAt), style: const TextStyle(fontSize: 12, color: Colors.grey)),
            trailing: n.tutorialId != null
                ? Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                        color: _primary.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8)),
                    child: const Icon(Icons.article_outlined, color: _primary, size: 20),
                  )
                : n.isRead
                    ? null
                    : Container(
                        width: 8,
                        height: 8,
                        decoration: const BoxDecoration(color: _primary, shape: BoxShape.circle)),
          ),
        );
      },
    );
  }
}

// 私信 tab
class _DmTab extends ConsumerWidget {
  final List<Conversation> conversations;
  const _DmTab({required this.conversations});

  String _timeAgo(int? tsMs) {
    if (tsMs == null) return '';
    final diff = DateTime.now().difference(DateTime.fromMillisecondsSinceEpoch(tsMs));
    if (diff.inMinutes < 1) return '刚刚';
    if (diff.inMinutes < 60) return '${diff.inMinutes}分钟前';
    if (diff.inHours < 24) return '${diff.inHours}小时前';
    return '${diff.inDays}天前';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (conversations.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.chat_bubble_outline, size: 56, color: Colors.grey),
            const SizedBox(height: 12),
            const Text('还没有私信', style: TextStyle(color: Colors.grey, fontSize: 15)),
            const SizedBox(height: 8),
            GestureDetector(
              onTap: () => context.go('/community'),
              child: const Text('去社区认识新朋友', style: TextStyle(color: _primary, fontSize: 14)),
            ),
          ],
        ),
      );
    }

    return ListView.separated(
      itemCount: conversations.length,
      separatorBuilder: (_, __) => const Divider(height: 0.5, indent: 76),
      itemBuilder: (ctx, i) {
        final conv = conversations[i];
        return ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          onTap: () => context.push('/messages/chat/${conv.id}', extra: conv),
          leading: CircleAvatar(
            radius: 24,
            backgroundColor: _primary,
            child: Text(_initial(conv.otherUsername),
                style: const TextStyle(
                    color: Colors.white, fontWeight: FontWeight.w700, fontSize: 16)),
          ),
          title: Row(
            children: [
              Text(conv.otherUsername,
                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
              const Spacer(),
              Text(_timeAgo(conv.lastMessageAt),
                  style: const TextStyle(fontSize: 12, color: Colors.grey)),
            ],
          ),
          subtitle: Row(
            children: [
              Expanded(
                child: Text(conv.lastMessage ?? '',
                    style: const TextStyle(fontSize: 13, color: Colors.grey),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
              ),
              if (conv.unreadCount > 0)
                Container(
                  margin: const EdgeInsets.only(left: 8),
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration:
                      BoxDecoration(color: Colors.red, borderRadius: BorderRadius.circular(99)),
                  child: Text('${conv.unreadCount}',
                      style: const TextStyle(
                          fontSize: 11, color: Colors.white, fontWeight: FontWeight.w700)),
                ),
            ],
          ),
        );
      },
    );
  }
}

// 群组 tab（占位——讨论群/技术交流论坛下个版本上线）
class _GroupTab extends StatelessWidget {
  const _GroupTab();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 80,
            height: 80,
            decoration:
                BoxDecoration(color: const Color(0xFFEEF0FF), borderRadius: BorderRadius.circular(20)),
            child: const Icon(Icons.group, size: 40, color: _primary),
          ),
          const SizedBox(height: 16),
          const Text('群组功能', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          const Text('即将上线，敬请期待', style: TextStyle(color: Colors.grey, fontSize: 14)),
        ],
      ),
    );
  }
}
