import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/network/api_client.dart';
import '../../auth/auth_service.dart';
import '../models/conversation_model.dart';
import '../models/notification_model.dart';

final unreadCountProvider = StateProvider<int>((ref) => 0);
final mentionUnreadCountProvider = StateProvider<int>((ref) => 0);

final notificationsProvider =
    StateNotifierProvider<NotificationsNotifier, List<AppNotification>>((ref) {
      return NotificationsNotifier(ref.read(apiClientProvider));
    });

class NotificationsNotifier extends StateNotifier<List<AppNotification>> {
  final ApiClient _api;
  NotificationsNotifier(this._api) : super([]);

  Future<void> fetch() async {
    final res = await _api.get('/auth/notifications');
    if (!res.success || res.data == null) {
      debugPrint('[notifications] fetch failed: ${res.message}');
      return;
    }
    try {
      final list = (res.data['notifications'] as List)
          .map((j) => AppNotification.fromJson(j as Map<String, dynamic>))
          .toList();
      state = list;
    } catch (e) {
      debugPrint('[notifications] parse error: $e');
    }
  }

  Future<void> markAllRead() async {
    final res = await _api.post('/auth/notifications/read', data: {'ids': []});
    if (!res.success) {
      debugPrint('[notifications] markRead error: ${res.message}');
      return;
    }
    for (final n in state) {
      n.isRead = true;
    }
    state = [...state];
  }

  // 之前 markAllRead 一直传 ids:[]（后端语义是"全标已读"）——提及Tab
  // 这种只想标记某一类通知已读、不想连带把其它未读通知也清掉的场景，
  // 需要真的传具体 ids 这个参数
  Future<void> markRead(List<String> ids) async {
    if (ids.isEmpty) return;
    final res = await _api.post('/auth/notifications/read', data: {'ids': ids});
    if (!res.success) {
      debugPrint('[notifications] markRead(ids) error: ${res.message}');
      return;
    }
    final idSet = ids.toSet();
    for (final n in state) {
      if (idSet.contains(n.id)) n.isRead = true;
    }
    state = [...state];
  }
}

final conversationsProvider =
    StateNotifierProvider<ConversationsNotifier, List<Conversation>>((ref) {
      return ConversationsNotifier(ref);
    });

class ConversationsNotifier extends StateNotifier<List<Conversation>> {
  final Ref _ref;
  ConversationsNotifier(this._ref) : super([]);

  Future<void> fetch() async {
    final res = await _ref.read(apiClientProvider).get('/auth/conversations');
    if (!res.success || res.data == null) {
      debugPrint('[conversations] fetch failed: ${res.message}');
      return;
    }
    try {
      final currentUserId = _ref.read(currentUserProvider)?.id;
      final list = (res.data['conversations'] as List)
          .map(
            (j) => Conversation.fromJson(
              j as Map<String, dynamic>,
              currentUserId: currentUserId,
            ),
          )
          .toList();
      state = list;
    } catch (e) {
      debugPrint('[conversations] parse error: $e');
    }
  }

  // 进入聊天页时本地立即清零，不等下一次轮询——实测确认
  // GET /auth/conversations/:id/messages 后端会顺手把这个会话标成已读，
  // 下次 fetch() 到的 unread_count 本来就会是 0，这里只是不想让用户
  // 在轮询间隔里看着红点还在
  void clearUnread(String convId) {
    state = state
        .map((c) => c.id == convId ? c.copyWith(unreadCount: 0) : c)
        .toList();
  }

  // 免打扰/清空历史消息本地即时更新，不等下一次轮询——跟 clearUnread
  // 同一个套路
  void setMuted(String convId, bool muted) {
    state = state
        .map((c) => c.id == convId ? c.copyWith(isMuted: muted) : c)
        .toList();
  }

  // copyWith 的 ?? 套路分不清"没传"和"故意传 null"，清空最后一条消息
  // 要把 lastMessage/lastMessageAt 真的置空，只能手动重新拼一个新对象
  void clearLastMessage(String convId) {
    state = state
        .map(
          (c) => c.id == convId
              ? Conversation(
                  id: c.id,
                  otherUserId: c.otherUserId,
                  otherUsername: c.otherUsername,
                  otherAvatar: c.otherAvatar,
                  lastMessage: null,
                  lastMessageAt: null,
                  unreadCount: 0,
                  isMuted: c.isMuted,
                )
              : c,
        )
        .toList();
  }
}
