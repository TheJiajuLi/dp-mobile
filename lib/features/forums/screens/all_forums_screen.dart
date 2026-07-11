import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_client.dart';
import '../../../shared/utils/forum_gradient.dart';
import '../../../shared/widgets/rounded_list_card.dart';
import '../models/forum_model.dart';

const _primary = Color(0xFF6366F1);

// 消息页论坛Tab——只显示"我关注的论坛"，不再是浏览全部论坛的入口。
// GET /auth/forums 目前唯一支持的排序是 post_count DESC，也没有
// "只返回我关注的" 这个过滤参数，所以还是拉全量列表，在客户端按
// is_following 筛出关注的这几个——量级上可以接受（论坛数量远小于用户/
// 帖子数量），比让后端专门加一个新接口划算
//
// 关注按钮挪掉了：这个页面现在是纯只读的"我的论坛"列表，取消关注要去
// 论坛主页（ForumHomeScreen）操作，取消后下次回到这个列表会因为
// is_following 变化自动被过滤掉，不需要另外处理"移除"逻辑
class AllForumsScreen extends ConsumerStatefulWidget {
  const AllForumsScreen({super.key});

  @override
  ConsumerState<AllForumsScreen> createState() => _AllForumsScreenState();
}

class _AllForumsScreenState extends ConsumerState<AllForumsScreen> {
  List<ForumModel> _followedForums = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadForums();
  }

  Future<void> _loadForums() async {
    if (!mounted) return;
    if (_followedForums.isEmpty) setState(() => _loading = true);
    final res = await ref.read(apiClientProvider).get('/auth/forums');
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (res.success && res.data != null) {
        final all = ((res.data['forums'] as List?) ?? [])
            .map((f) => ForumModel.fromJson(Map<String, dynamic>.from(f as Map)))
            .toList();
        _followedForums = all.where((f) => f.isFollowing).toList();
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
                  : _followedForums.isEmpty
                  ? _buildEmptyState(isDark)
                  : RefreshIndicator(
                      onRefresh: _loadForums,
                      child: ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        children: [
                          RoundedListCard(
                            children: _followedForums
                                .map((f) => _forumTile(f, isDark))
                                .toList(),
                          ),
                          const SizedBox(height: 10),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            child: Text(
                              '取消关注后自动从此处移除',
                              style: TextStyle(
                                fontSize: 11,
                                color: isDark
                                    ? Colors.white.withValues(alpha: 0.3)
                                    : Colors.grey[400],
                              ),
                            ),
                          ),
                        ],
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
            '还没有关注任何论坛',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: Colors.grey[400],
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '去搜索页发现感兴趣的论坛',
            style: TextStyle(fontSize: 13, color: Colors.grey[400]),
          ),
          const SizedBox(height: 20),
          ElevatedButton(
            // search_screen.dart 目前只有 教程/用户/话题/群组 四个Tab，
            // 没有论坛Tab，也没有论坛搜索功能——这里老实跳转到搜索页本身，
            // 不假装能自动切到一个还不存在的论坛Tab
            onPressed: () => context.push('/search'),
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
              '去搜索',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  Widget _forumTile(ForumModel forum, bool isDark) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          gradient: (forum.avatar?.isNotEmpty ?? false)
              ? null
              : LinearGradient(
                  colors: forumGradientFor(forum.colorIdx),
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
          image: (forum.avatar?.isNotEmpty ?? false)
              ? DecorationImage(
                  image: NetworkImage(forum.avatar!),
                  fit: BoxFit.cover,
                )
              : null,
          borderRadius: BorderRadius.circular(10),
        ),
        child: (forum.avatar?.isNotEmpty ?? false)
            ? null
            : Center(
                child: Text(
                  forum.name.isNotEmpty ? forum.name.substring(0, 1) : '论',
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
              ),
      ),
      title: Text(
        forum.name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
      ),
      subtitle: Text(
        '${forum.postCount} 帖子 · ${forum.followerCount} 成员',
        style: TextStyle(
          fontSize: 12,
          color: isDark ? Colors.white.withValues(alpha: 0.4) : Colors.grey[500],
        ),
      ),
      trailing: Icon(
        Icons.chevron_right,
        size: 20,
        color: isDark ? Colors.white.withValues(alpha: 0.25) : Colors.grey[300],
      ),
      onTap: () => context.push('/forum-home/${forum.id}'),
    );
  }
}
