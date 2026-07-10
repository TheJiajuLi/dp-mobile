import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_client.dart';

const _primary = Color(0xFF6366F1);

// 我加入的群组列表——GET /auth/groups 已经真实上线了（跟建群/群聊页
// 那两步同一批后端接口）。getMyGroups 现在已经在 SQL 里 LEFT JOIN 了
// 每个群最新一条 group_messages，返回 last_message/last_message_type/
// last_message_at，卡片预览走真实的最后一条消息内容，不是写死的占位文案
class GroupListScreen extends ConsumerStatefulWidget {
  const GroupListScreen({super.key});

  @override
  ConsumerState<GroupListScreen> createState() => _GroupListScreenState();
}

class _GroupListScreenState extends ConsumerState<GroupListScreen>
    with WidgetsBindingObserver {
  List<Map<String, dynamic>> _groups = [];
  bool _loading = true;
  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadGroups();
    // 群卡片右上角的未读数是进列表时的快照，群聊页标记已读之后这个页面
    // 不会自动知道——轮询兜底，跟消息主页/私信页同一套节奏
    _pollTimer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => _loadGroups(),
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _loadGroups();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pollTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadGroups() async {
    if (!mounted) return;
    if (_groups.isEmpty) setState(() => _loading = true);
    final res = await ref.read(apiClientProvider).get('/auth/groups');
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (res.success && res.data != null) {
        _groups = ((res.data['groups'] as List?) ?? [])
            .map((g) => Map<String, dynamic>.from(g as Map))
            .toList();
      }
    });
  }

  // 从群聊页退回来之后立即补拉一次——比等30秒轮询更及时，进群聊时
  // 已经真实调用过 POST /:id/read，这里只是让列表把最新的
  // unread_count 显示出来，不是另外发起一次标记已读
  Future<void> _openGroup(Map<String, dynamic> g) async {
    await context.push(
      '/group/${g['id']}',
      extra: {
        'name': g['name'],
        'memberCount': (g['member_count'] as num?)?.toInt(),
      },
    );
    _loadGroups();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

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
                  const Text(
                    '群组',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                  ),
                  const Spacer(),
                  IconButton(
                    onPressed: () => context.push('/groups/create'),
                    icon: const Icon(Icons.add, size: 22),
                  ),
                ],
              ),
            ),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _groups.isEmpty
                  ? _buildEmptyState(isDark)
                  : RefreshIndicator(
                      onRefresh: _loadGroups,
                      child: ListView.builder(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        itemCount: _groups.length,
                        itemBuilder: (ctx, i) => _groupCard(_groups[i], isDark),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState(bool isDark) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.groups_outlined, size: 48, color: Colors.grey[300]),
          const SizedBox(height: 12),
          Text(
            '还没有加入任何群组',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: Colors.grey[400],
            ),
          ),
          const SizedBox(height: 20),
          ElevatedButton(
            onPressed: () => context.push('/groups/create'),
            style: ElevatedButton.styleFrom(
              backgroundColor: _primary,
              foregroundColor: Colors.white,
              elevation: 0,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(99),
              ),
            ),
            child: const Text(
              '创建群组',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  Widget _groupCard(Map<String, dynamic> g, bool isDark) {
    final name = g['name'] as String? ?? '';
    final memberCount = (g['member_count'] as num?)?.toInt() ?? 1;
    final unreadCount = (g['unread_count'] as num?)?.toInt() ?? 0;
    final createdAt = (g['created_at'] as num?)?.toInt() ?? 0;
    final lastMessageAt = (g['last_message_at'] as num?)?.toInt();

    return GestureDetector(
      onTap: () => _openGroup(g),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isDark
                ? Colors.white.withValues(alpha: 0.08)
                : const Color(0xFFEBEBEB),
            width: 0.5,
          ),
        ),
        child: Row(
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFFEEF0FF), Color(0xFFDDD6FE)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Center(
                    child: Text(
                      name.isNotEmpty ? name.substring(0, 1) : '群',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: _primary,
                      ),
                    ),
                  ),
                ),
                if (unreadCount > 0)
                  Positioned(
                    top: -3,
                    right: -3,
                    child: Container(
                      constraints: const BoxConstraints(minWidth: 16),
                      height: 16,
                      padding: const EdgeInsets.symmetric(horizontal: 3),
                      decoration: BoxDecoration(
                        color: const Color(0xFFEF4444),
                        borderRadius: BorderRadius.circular(99),
                        border: Border.all(
                          color: Theme.of(context).cardColor,
                          width: 1.5,
                        ),
                      ),
                      child: Center(
                        child: Text(
                          unreadCount > 99 ? '99+' : '$unreadCount',
                          style: const TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      Text(
                        _formatDate(lastMessageAt ?? createdAt),
                        style: TextStyle(
                          fontSize: 11,
                          color: isDark
                              ? Colors.white.withValues(alpha: 0.35)
                              : Colors.grey[400],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          _buildPreview(g),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            color: isDark
                                ? Colors.white.withValues(alpha: 0.4)
                                : Colors.grey[500],
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        '$memberCount 人',
                        style: TextStyle(
                          fontSize: 11,
                          color: isDark
                              ? Colors.white.withValues(alpha: 0.35)
                              : Colors.grey[400],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // last_message 为空但 unread_count > 0 理论上不该发生（有未读消息
  // 就该有一条对应的最新消息记录），真出现这种数据不一致的情况就老实
  // 说"有 N 条新消息"，不要跟"暂无消息"这个真正空群的文案混在一起
  String _buildPreview(Map<String, dynamic> g) {
    final lastMsg = g['last_message'] as String?;
    final unread = (g['unread_count'] as num?)?.toInt() ?? 0;

    if (lastMsg == null || lastMsg.isEmpty) {
      if (unread > 0) return '有 $unread 条新消息';
      return '暂无消息，点击开始聊天';
    }

    final type = g['last_message_type'] as String? ?? 'text';
    if (type == 'share_tutorial') return '📄 分享了一篇文章';
    if (type == 'share_question') return '❓ 分享了一个问题';
    return lastMsg.length > 30 ? '${lastMsg.substring(0, 30)}...' : lastMsg;
  }

  String _formatDate(int tsSeconds) {
    if (tsSeconds == 0) return '';
    final d = DateTime.fromMillisecondsSinceEpoch(tsSeconds * 1000);
    final now = DateTime.now();
    if (d.year == now.year && d.month == now.month && d.day == now.day) {
      return '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
    }
    return '${d.month}/${d.day}';
  }
}
