import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_client.dart';
import '../models/forum_model.dart';

const _primary = Color(0xFF6366F1);

// 论坛列表——GET /auth/forums 已经真实上线（连同 follow/posts/replies/likes
// 一整套）。但列表接口没有区分当前用户是否已关注某个论坛（getForums 没有
// 用到 req.userId，SQL 里也没有 JOIN forum_follows 判断当前用户），所以
// "关注"按钮的初始状态只能都显示"关注"，点了之后按真实的 toggle 接口
// 返回的 following 字段更新——这是后端接口本身的缺口，不是这里漏做，
// 已经在这次改动的说明里跟用户提出来了，不在 Flutter 这边私自模拟
class ForumListScreen extends ConsumerStatefulWidget {
  const ForumListScreen({super.key});

  @override
  ConsumerState<ForumListScreen> createState() => _ForumListScreenState();
}

class _ForumListScreenState extends ConsumerState<ForumListScreen> {
  List<ForumModel> _forums = [];
  final Set<String> _following = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadForums();
  }

  Future<void> _loadForums() async {
    if (!mounted) return;
    if (_forums.isEmpty) setState(() => _loading = true);
    final res = await ref.read(apiClientProvider).get('/auth/forums');
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (res.success && res.data != null) {
        _forums = ((res.data['forums'] as List?) ?? [])
            .map((f) => ForumModel.fromJson(Map<String, dynamic>.from(f as Map)))
            .toList();
      }
    });
  }

  Future<void> _toggleFollow(ForumModel forum) async {
    final wasFollowing = _following.contains(forum.id);
    // 乐观更新，真实请求失败再翻回去——跟这个项目其它点赞/关注类交互
    // 的处理方式一致
    setState(() {
      if (wasFollowing) {
        _following.remove(forum.id);
      } else {
        _following.add(forum.id);
      }
    });
    final res = await ref
        .read(apiClientProvider)
        .post('/auth/forums/${forum.id}/follow');
    if (!mounted) return;
    if (!res.success) {
      setState(() {
        if (wasFollowing) {
          _following.add(forum.id);
        } else {
          _following.remove(forum.id);
        }
      });
      return;
    }
    final following = res.data?['following'] == true;
    setState(() {
      if (following) {
        _following.add(forum.id);
      } else {
        _following.remove(forum.id);
      }
    });
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
                    '论坛',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                  ),
                  const Spacer(),
                ],
              ),
            ),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _forums.isEmpty
                  ? _buildEmptyState(isDark)
                  : RefreshIndicator(
                      onRefresh: _loadForums,
                      child: ListView.builder(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        itemCount: _forums.length,
                        itemBuilder: (ctx, i) => _forumCard(_forums[i], isDark),
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
          Icon(Icons.forum_outlined, size: 48, color: Colors.grey[300]),
          const SizedBox(height: 12),
          Text(
            '还没有任何论坛',
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

  Widget _forumCard(ForumModel forum, bool isDark) {
    final following = _following.contains(forum.id);

    return GestureDetector(
      // 帖子列表页这次不在范围内——真实的 posts/replies/likes 接口后端
      // 已经有了，但 Flutter 这边还没做详情页，老实提示，不假装能点进去
      onTap: () {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('论坛详情页即将上线')),
        );
      },
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
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFFE0F2FE), Color(0xFFBAE6FD)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Center(
                child: Text(
                  forum.name.isNotEmpty ? forum.name.substring(0, 1) : '论',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF0891B2),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    forum.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    (forum.description?.isNotEmpty ?? false)
                        ? forum.description!
                        : '暂无简介',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      color: isDark
                          ? Colors.white.withValues(alpha: 0.4)
                          : Colors.grey[500],
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${forum.followerCount} 人关注 · ${forum.postCount} 个帖子',
                    style: TextStyle(
                      fontSize: 11,
                      color: isDark
                          ? Colors.white.withValues(alpha: 0.35)
                          : Colors.grey[400],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: () => _toggleFollow(forum),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: following
                      ? (isDark
                            ? Colors.white.withValues(alpha: 0.08)
                            : const Color(0xFFF2F2F2))
                      : _primary,
                  borderRadius: BorderRadius.circular(99),
                ),
                child: Text(
                  following ? '已关注' : '关注',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: following
                        ? (isDark ? Colors.white70 : Colors.grey[600])
                        : Colors.white,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
