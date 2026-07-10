import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_client.dart';
import '../models/forum_post_model.dart';
import '../widgets/post_card.dart';

const _primary = Color(0xFF6366F1);

// 后端论坛分「论坛」和「帖子」两层：GET /auth/forums 列出论坛，
// GET /auth/forums/:forumId/posts 列出某个论坛的帖子。这里先只做帖子列表，
// forumId 由路由传入；论坛选择页后续再做
class ForumListScreen extends ConsumerStatefulWidget {
  final String forumId;
  const ForumListScreen({super.key, required this.forumId});

  @override
  ConsumerState<ForumListScreen> createState() => _ForumListScreenState();
}

class _ForumListScreenState extends ConsumerState<ForumListScreen> {
  List<ForumPost> _posts = [];
  bool _loading = true;
  String _sort = 'latest';
  String? _selectedTag;

  final _tags = ['全部', '数学', '编程', 'AI', '数据分析', '物理'];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final res = await ref
        .read(apiClientProvider)
        .get(
          '/auth/forums/${widget.forumId}/posts',
          queryParameters: {
            'sort': _sort,
            if (_selectedTag != null && _selectedTag != '全部')
              'tag': _selectedTag,
          },
        );
    if (!mounted) return;
    if (res.success && res.data is Map) {
      final list = ((res.data as Map)['posts'] as List?) ?? const [];
      setState(() {
        _posts = list
            .map((p) => ForumPost.fromJson(Map<String, dynamic>.from(p as Map)))
            .toList();
        _loading = false;
      });
    } else {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, size: 18),
          onPressed: () => context.pop(),
        ),
        title: const Text(
          '论坛',
          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
        ),
      ),
      body: Column(
        children: [
          // 分类标签横滑
          SizedBox(
            height: 44,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              itemCount: _tags.length,
              separatorBuilder: (_, __) => const SizedBox(width: 6),
              itemBuilder: (ctx, i) {
                final tag = _tags[i];
                final isOn = tag == '全部'
                    ? _selectedTag == null
                    : _selectedTag == tag;
                return GestureDetector(
                  onTap: () {
                    setState(() => _selectedTag = tag == '全部' ? null : tag);
                    _load();
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 13,
                      vertical: 4,
                    ),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: isOn
                          ? const Color(0xFFEEF0FF)
                          : (isDark
                                ? Colors.white.withValues(alpha: 0.05)
                                : Colors.white),
                      borderRadius: BorderRadius.circular(99),
                      border: Border.all(
                        color: isOn
                            ? _primary
                            : (isDark
                                  ? Colors.white.withValues(alpha: 0.08)
                                  : const Color(0xFFEBEBEB)),
                        width: 0.5,
                      ),
                    ),
                    child: Text(
                      tag,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: isOn ? FontWeight.w500 : FontWeight.w400,
                        color: isOn
                            ? _primary
                            : (isDark
                                  ? Colors.white.withValues(alpha: 0.5)
                                  : Colors.grey[600]),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),

          // 排序行
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.06)
                      : const Color(0xFFEBEBEB),
                  width: 0.5,
                ),
              ),
            ),
            child: Row(
              children: [
                _SortBtn(
                  label: '最新',
                  selected: _sort == 'latest',
                  onTap: () {
                    setState(() => _sort = 'latest');
                    _load();
                  },
                ),
                const SizedBox(width: 12),
                _SortBtn(
                  label: '最热',
                  selected: _sort == 'hot',
                  onTap: () {
                    setState(() => _sort = 'hot');
                    _load();
                  },
                ),
              ],
            ),
          ),

          // 帖子列表
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _posts.isEmpty
                ? _buildEmpty()
                : RefreshIndicator(
                    onRefresh: _load,
                    child: ListView.builder(
                      itemCount: _posts.length,
                      itemBuilder: (ctx, i) => PostCard(
                        post: _posts[i],
                        onTap: () =>
                            context.push('/forum/post/${_posts[i].id}'),
                      ),
                    ),
                  ),
          ),
        ],
      ),

      // 发帖 FAB——发完回来刷新列表
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          await context.push(
            '/forum/create',
            extra: {'forumId': widget.forumId},
          );
          _load();
        },
        backgroundColor: _primary,
        child: const Icon(Icons.edit, color: Colors.white),
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
          '还没有帖子',
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

class _SortBtn extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _SortBtn({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Text(
      label,
      style: TextStyle(
        fontSize: 13,
        fontWeight: selected ? FontWeight.w500 : FontWeight.w400,
        color: selected ? _primary : Colors.grey[400],
      ),
    ),
  );
}
