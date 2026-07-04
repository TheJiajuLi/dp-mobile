import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/network/api_client.dart';
import '../models/conversation_model.dart';
import '../models/notification_model.dart';

final unreadCountProvider = StateProvider<int>((ref) => 0);

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
}

final conversationsProvider =
    StateNotifierProvider<ConversationsNotifier, List<Conversation>>((ref) {
  return ConversationsNotifier(ref.read(apiClientProvider));
});

class ConversationsNotifier extends StateNotifier<List<Conversation>> {
  final ApiClient _api;
  ConversationsNotifier(this._api) : super([]);

  Future<void> fetch() async {
    final res = await _api.get('/auth/conversations');
    if (!res.success || res.data == null) {
      debugPrint('[conversations] fetch failed: ${res.message}');
      return;
    }
    try {
      final list = (res.data['conversations'] as List)
          .map((j) => Conversation.fromJson(j as Map<String, dynamic>))
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
}
