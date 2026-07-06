import 'dart:convert';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_client.dart';
import '../models/conversation_model.dart';

const _primary = Color(0xFF6366F1);

String _initial(String? name) {
  if (name == null || name.isEmpty) return '?';
  return name.substring(0, 1).toUpperCase();
}

// 跟 chat_screen.dart/messages_screen.dart 同一套判断：data:image 开头是
// 旧的 base64 头像，否则是 COS 图片 URL
Widget _buildAvatar(String? avatar, String username, {double radius = 24}) {
  if (avatar != null && avatar.isNotEmpty) {
    if (avatar.startsWith('data:image')) {
      try {
        return CircleAvatar(
          radius: radius,
          backgroundImage: MemoryImage(base64Decode(avatar.split(',').last)),
        );
      } catch (_) {
        // 解码失败落到下面的首字母占位
      }
    } else {
      return CircleAvatar(
        radius: radius,
        backgroundImage: CachedNetworkImageProvider(avatar),
      );
    }
  }
  return CircleAvatar(
    radius: radius,
    backgroundColor: _primary,
    child: Text(
      _initial(username),
      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
    ),
  );
}

// 好友：互相关注的用户（GET /auth/friends，跟 chat_screen.dart 判断陌生人
// 限制用的是同一份口径）。点开一个好友进聊天时，接口本身没有直接返回
// conversation id（只 JOIN 出了 last_message/last_message_at），复用
// user_profile_screen.dart「发消息」按钮那套"先查有没有现成会话，没有就
// 发一条默认招呼语创建一个"逻辑，不是凭空造一个 /chat/:id 路由
class FriendListScreen extends ConsumerStatefulWidget {
  const FriendListScreen({super.key});
  @override
  ConsumerState<FriendListScreen> createState() => _FriendListScreenState();
}

class _FriendListScreenState extends ConsumerState<FriendListScreen> {
  bool _loading = true;
  List<Map<String, dynamic>> _friends = [];
  final Set<String> _openingChatWith = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final res = await ref.read(apiClientProvider).get('/auth/friends');
    if (!mounted) return;
    setState(() {
      _friends = res.success && res.data != null
          ? List<Map<String, dynamic>>.from(
              (res.data['friends'] as List?) ?? [],
            )
          : [];
      _loading = false;
    });
  }

  Future<void> _openChat(Map<String, dynamic> f) async {
    final friendId = f['id']?.toString() ?? '';
    if (friendId.isEmpty || _openingChatWith.contains(friendId)) return;
    setState(() => _openingChatWith.add(friendId));

    try {
      final api = ref.read(apiClientProvider);
      final res = await api.get('/auth/conversations');
      if (res.success && res.data != null) {
        final convs = (res.data['conversations'] as List?) ?? [];
        final existing = convs.cast<Map<String, dynamic>?>().firstWhere(
          (c) => c?['other_user_id']?.toString() == friendId,
          orElse: () => null,
        );
        if (existing != null) {
          if (!mounted) return;
          context.push(
            '/messages/chat/${existing['id']}',
            extra: Conversation.fromJson(existing),
          );
          return;
        }
      }

      if (!mounted) return;
      final msgRes = await api.post(
        '/auth/messages',
        data: {'toUserId': friendId, 'content': '你好！', 'type': 'text'},
      );
      if (!msgRes.success || msgRes.data == null) {
        if (!mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('打开聊天失败：${msgRes.message}')));
        return;
      }
      if (!mounted) return;
      context.push(
        '/messages/chat/${msgRes.data['conversationId']}',
        extra: Conversation(
          id: msgRes.data['conversationId'].toString(),
          otherUserId: friendId,
          otherUsername: f['username']?.toString() ?? '',
          otherAvatar: f['avatar']?.toString(),
          unreadCount: 0,
        ),
      );
    } finally {
      if (mounted) setState(() => _openingChatWith.remove(friendId));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: () => context.pop(),
                    child: const Icon(Icons.arrow_back_ios, size: 18),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '好友',
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      color: Theme.of(context).textTheme.bodyLarge?.color,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _friends.isEmpty
                  ? const Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.people_outline,
                            size: 48,
                            color: Color(0xFFE5E5EA),
                          ),
                          SizedBox(height: 12),
                          Text('还没有好友', style: TextStyle(color: Colors.grey)),
                          SizedBox(height: 6),
                          Text(
                            '互相关注后成为好友',
                            style: TextStyle(fontSize: 12, color: Colors.grey),
                          ),
                        ],
                      ),
                    )
                  : ListView.separated(
                      itemCount: _friends.length,
                      separatorBuilder: (_, _) =>
                          const Divider(height: 0.5, indent: 76),
                      itemBuilder: (ctx, i) {
                        final f = _friends[i];
                        final username = f['username']?.toString() ?? '';
                        final unread =
                            (f['unread_count'] as num?)?.toInt() ?? 0;
                        return ListTile(
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 6,
                          ),
                          leading: _buildAvatar(
                            f['avatar']?.toString(),
                            username,
                          ),
                          title: Text(
                            username,
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          subtitle: f['last_message'] != null
                              ? Text(
                                  f['last_message'].toString(),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontSize: 12),
                                )
                              : const Text(
                                  '发消息打招呼',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey,
                                  ),
                                ),
                          trailing: unread > 0
                              ? Container(
                                  padding: const EdgeInsets.all(4),
                                  decoration: const BoxDecoration(
                                    color: _primary,
                                    shape: BoxShape.circle,
                                  ),
                                  child: Text(
                                    '$unread',
                                    style: const TextStyle(
                                      fontSize: 10,
                                      color: Colors.white,
                                    ),
                                  ),
                                )
                              : null,
                          onTap: () => _openChat(f),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
