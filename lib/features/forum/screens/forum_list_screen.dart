import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_client.dart';
import '../models/forum_post_model.dart';
import '../widgets/post_card.dart';

// 现在是 ForumHomeScreen 的 TabBarView 子项（精华/最新/最热三个 tab
// 各拿一个 sort 值），不再是独立路由页——AppBar/分类标签/排序按钮/发帖
// FAB 都交给 ForumHomeScreen 统一管理，这里只负责按 sort 拉一屏帖子列表
class ForumListScreen extends ConsumerStatefulWidget {
  final String forumId;
  final String sort; // 'latest' / 'hot' / 'featured'
  const ForumListScreen({
    super.key,
    required this.forumId,
    this.sort = 'latest',
  });

  @override
  ConsumerState<ForumListScreen> createState() => _ForumListScreenState();
}

class _ForumListScreenState extends ConsumerState<ForumListScreen> {
  List<ForumPost> _posts = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    // 后端 getPosts 只认识 sort/tag 两个查询参数，'featured' 不是它认识的
    // 排序值——精华 tab 老实按 'latest' 去拉最近 50 条（后端 LIMIT 50），
    // 再在客户端过滤 is_featured。这意味着精华帖如果不在最近50条创建的
    // 帖子里就不会出现在这个 tab，是当前这版的已知局限，不是漏了处理
    final effectiveSort = widget.sort == 'featured' ? 'latest' : widget.sort;
    final res = await ref
        .read(apiClientProvider)
        .get(
          '/auth/forums/${widget.forumId}/posts',
          queryParameters: {'sort': effectiveSort},
        );
    if (!mounted) return;
    if (res.success && res.data is Map) {
      final list = ((res.data as Map)['posts'] as List?) ?? const [];
      var posts = list
          .map((p) => ForumPost.fromJson(Map<String, dynamic>.from(p as Map)))
          .toList();
      if (widget.sort == 'featured') {
        posts = posts.where((p) => p.isFeatured).toList();
      }
      setState(() {
        _posts = posts;
        _loading = false;
      });
    } else {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return _loading
        ? const Center(child: CircularProgressIndicator())
        : _posts.isEmpty
        ? _buildEmpty()
        : RefreshIndicator(
            onRefresh: _load,
            child: ListView.builder(
              itemCount: _posts.length,
              itemBuilder: (ctx, i) => PostCard(
                post: _posts[i],
                onTap: () => context.push('/forum/post/${_posts[i].id}'),
              ),
            ),
          );
  }

  Widget _buildEmpty() => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.forum_outlined, size: 40, color: Colors.grey[300]),
        const SizedBox(height: 12),
        Text(
          widget.sort == 'featured' ? '还没有精华帖' : '还没有帖子',
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: Colors.grey[400],
          ),
        ),
        const SizedBox(height: 6),
        Text('来发第一篇吧', style: TextStyle(fontSize: 13, color: Colors.grey[400])),
      ],
    ),
  );
}
