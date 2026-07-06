import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_client.dart';
import '../../../shared/models/tutorial_model.dart';
import '../../../shared/utils/topic_badge.dart';
import '../../auth/auth_service.dart';

const _primary = Color(0xFF6366F1);

// 教程的 status 是数据库 ENUM('draft','published','deleted')，只有这三个
// 合法值——这里的"下架"不是调用 DELETE /auth/tutorials/:id 真删（那个
// 接口会连带清掉评论/点赞/收藏，且没有恢复入口，跟"下架"这个词的直觉不
// 符），而是把 status 改成 'deleted'：内容还在，公开列表里不再出现，且
// 可以在"下架"tab里一键恢复上架。真正的永久删除只在草稿/已下架内容里
// 提供，那两种情况下数据本来就还没公开或已经不公开，删掉不会有社交层面
// 的连带损失
enum _WorkTab { published, draft, archived }

class WorksScreen extends ConsumerStatefulWidget {
  final int initialTab;
  const WorksScreen({super.key, this.initialTab = 0});
  @override
  ConsumerState<WorksScreen> createState() => _WorksScreenState();
}

class _WorksScreenState extends ConsumerState<WorksScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabCtrl;
  final Map<_WorkTab, List<TutorialModel>> _lists = {};
  final Map<_WorkTab, bool> _loading = {
    _WorkTab.published: true,
    _WorkTab.draft: true,
    _WorkTab.archived: true,
  };

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(
      length: 3,
      vsync: this,
      initialIndex: widget.initialTab.clamp(0, 2),
    );
    _loadAll();
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  String _statusFor(_WorkTab tab) => switch (tab) {
    _WorkTab.published => 'published',
    _WorkTab.draft => 'draft',
    _WorkTab.archived => 'deleted',
  };

  Future<void> _loadAll() async {
    await Future.wait(_WorkTab.values.map(_load));
  }

  Future<void> _load(_WorkTab tab) async {
    final user = ref.read(currentUserProvider);
    if (user == null) return;
    final res = await ref.read(apiClientProvider).get(
      '/auth/tutorials',
      queryParameters: {
        'author': user.username,
        'status': _statusFor(tab),
        'limit': 50,
      },
    );
    if (!mounted) return;
    var list = <TutorialModel>[];
    if (res.success && res.data != null) {
      list = ((res.data['tutorials'] as List?) ?? [])
          .map((j) => TutorialModel.fromJson(j as Map<String, dynamic>))
          .where((t) => t.userId == user.id)
          .toList();
    }
    setState(() {
      _lists[tab] = list;
      _loading[tab] = false;
    });
  }

  // 下架/恢复/删除都要"整份覆盖"式的 PUT，先把这篇教程的完整内容（含
  // blocks）拉回来，只改 status 一个字段，其余原样传回去，不然
  // updateTutorial 会把 blocks/tags 清空成默认值
  Future<bool> _changeStatus(String id, String newStatus) async {
    final api = ref.read(apiClientProvider);
    final full = await api.get('/auth/tutorials/$id');
    if (!full.success || full.data == null) return false;
    final t = full.data as Map;
    final res = await api.put(
      '/auth/tutorials/$id',
      data: {
        'title': t['title'],
        'summary': t['summary'],
        'cover_image': t['cover_image'],
        'tags': t['tags'],
        'blocks': t['blocks'],
        'status': newStatus,
      },
    );
    return res.success;
  }

  Future<void> _confirmAndRun({
    required String title,
    required String message,
    required Future<bool> Function() action,
  }) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消', style: TextStyle(color: Colors.grey)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('确定', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final ok = await action();
    if (!mounted) return;
    if (ok) {
      await _loadAll();
    } else {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('操作失败，请重试')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFAFAF8),
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _header(),
            Container(
              color: Colors.white,
              child: TabBar(
                controller: _tabCtrl,
                labelColor: _primary,
                unselectedLabelColor: const Color(0xFF999999),
                indicatorColor: _primary,
                tabs: const [
                  Tab(text: '已发布'),
                  Tab(text: '草稿'),
                  Tab(text: '下架'),
                ],
              ),
            ),
            Expanded(
              child: TabBarView(
                controller: _tabCtrl,
                children: _WorkTab.values.map(_buildTab).toList(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _header() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)],
        ),
      ),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => context.pop(),
            child: Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.arrow_back, size: 17, color: Colors.white),
            ),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Text(
              '作品管理',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
          ),
          GestureDetector(
            onTap: () => ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('批量操作即将上线，敬请期待')),
            ),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Text(
                '批量',
                style: TextStyle(fontSize: 12, color: Colors.white),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTab(_WorkTab tab) {
    if (_loading[tab] == true) {
      return const Center(child: CircularProgressIndicator());
    }
    final list = _lists[tab] ?? [];
    if (list.isEmpty) {
      return Center(
        child: Text(
          switch (tab) {
            _WorkTab.published => '还没有发布的作品',
            _WorkTab.draft => '草稿箱是空的',
            _WorkTab.archived => '没有已下架的内容',
          },
          style: const TextStyle(fontSize: 13, color: Color(0xFF999999)),
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: list.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (ctx, i) => _workCard(tab, list[i]),
    );
  }

  Widget _workCard(_WorkTab tab, TutorialModel t) {
    final rule = matchedTopicRuleFor(t.tags);
    final bg = rule?.bg ?? const Color(0xFFF5F5F5);
    final fg = rule?.fg ?? const Color(0xFF999999);
    final time = DateTime.fromMillisecondsSinceEpoch(t.createdAt);
    final timeLabel = '${time.year}-${time.month.toString().padLeft(2, '0')}-'
        '${time.day.toString().padLeft(2, '0')}';

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFF0F0F0), width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: bg,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(Icons.description_outlined, color: fg, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        t.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF1A1A1A),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          const Icon(
                            Icons.visibility_outlined,
                            size: 13,
                            color: Color(0xFF999999),
                          ),
                          const SizedBox(width: 3),
                          Text(
                            '${t.views}',
                            style: const TextStyle(
                              fontSize: 12,
                              color: Color(0xFF999999),
                            ),
                          ),
                          const SizedBox(width: 10),
                          const Icon(
                            Icons.favorite_border,
                            size: 13,
                            color: Color(0xFF999999),
                          ),
                          const SizedBox(width: 3),
                          Text(
                            '${t.likes}',
                            style: const TextStyle(
                              fontSize: 12,
                              color: Color(0xFF999999),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Text(
                            timeLabel,
                            style: const TextStyle(
                              fontSize: 12,
                              color: Color(0xFFC7C7CC),
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
          Container(
            decoration: const BoxDecoration(
              border: Border(top: BorderSide(color: Color(0xFFF0F0F0), width: 0.5)),
            ),
            child: Row(
              children: _actionsFor(tab, t),
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _actionsFor(_WorkTab tab, TutorialModel t) {
    switch (tab) {
      case _WorkTab.published:
        return [
          _actionBtn('编辑', Icons.edit_outlined, _ink, () {
            context.push('/publish/${t.id}');
          }),
          _actionBtn('数据', Icons.bar_chart_outlined, _ink, () {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('数据详情即将上线，敬请期待')),
            );
          }),
          _actionBtn('下架', Icons.visibility_off_outlined, Colors.red, () {
            _confirmAndRun(
              title: '下架这篇内容？',
              message: '下架后读者将看不到这篇内容，你可以随时在"下架"里恢复上架。',
              action: () => _changeStatus(t.id, 'deleted'),
            );
          }),
        ];
      case _WorkTab.draft:
        return [
          _actionBtn('编辑', Icons.edit_outlined, _ink, () {
            context.push('/publish/${t.id}');
          }),
          _actionBtn('删除', Icons.delete_outline, Colors.red, () {
            _confirmAndRun(
              title: '删除这篇草稿？',
              message: '删除后无法恢复。',
              action: () async {
                final res = await ref
                    .read(apiClientProvider)
                    .delete('/auth/tutorials/${t.id}');
                return res.success;
              },
            );
          }),
        ];
      case _WorkTab.archived:
        return [
          _actionBtn('恢复上架', Icons.visibility_outlined, _primary, () {
            _confirmAndRun(
              title: '恢复上架这篇内容？',
              message: '恢复后读者可以重新看到这篇内容。',
              action: () => _changeStatus(t.id, 'published'),
            );
          }),
          _actionBtn('彻底删除', Icons.delete_forever_outlined, Colors.red, () {
            _confirmAndRun(
              title: '彻底删除这篇内容？',
              message: '删除后连同评论/点赞/收藏一起清除，无法恢复。',
              action: () async {
                final res = await ref
                    .read(apiClientProvider)
                    .delete('/auth/tutorials/${t.id}');
                return res.success;
              },
            );
          }),
        ];
    }
  }

  static const _ink = Color(0xFF555555);

  Widget _actionBtn(String label, IconData icon, Color color, VoidCallback onTap) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 15, color: color),
              const SizedBox(width: 5),
              Text(label, style: TextStyle(fontSize: 12.5, color: color)),
            ],
          ),
        ),
      ),
    );
  }
}
