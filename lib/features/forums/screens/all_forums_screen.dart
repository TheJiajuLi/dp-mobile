import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_client.dart';
import '../models/forum_model.dart';

const _primary = Color(0xFF6366F1);

// 论坛的"选坛页"——后端论坛分两层：GET /auth/forums 列出所有论坛，
// GET /auth/forums/:forumId/posts 列出某个论坛内的帖子。帖子列表/详情/
// 发帖/回复/点赞那一整套已经在 lib/features/forum/（单数）里做好了，
// 但那边的 ForumListScreen 其实是"某个论坛内的帖子列表"，需要外部传入
// forumId，它自己的注释也写明"论坛选择页后续再做"——这个文件就是那个
// 后续，选中一个论坛后 push 到 /forum/:forumId 进已有的帖子列表页
//
// GET /auth/forums 现在会返回 is_following（0/1），关注按钮的初始状态直接用
// 它来定；点击后按 toggle 接口返回的 following 字段更新，请求失败则回滚
class AllForumsScreen extends ConsumerStatefulWidget {
  const AllForumsScreen({super.key});

  @override
  ConsumerState<AllForumsScreen> createState() => _AllForumsScreenState();
}

class _AllForumsScreenState extends ConsumerState<AllForumsScreen> {
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
        // 用后端返回的 is_following 初始化/刷新关注态，服务端为准
        _following
          ..clear()
          ..addAll(_forums.where((f) => f.isFollowing).map((f) => f.id));
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
      onTap: () => context.push('/forum-home/${forum.id}'),
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
