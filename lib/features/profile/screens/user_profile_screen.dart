import 'dart:convert';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_client.dart';
import '../../../shared/models/tutorial_model.dart';
import '../../auth/auth_service.dart';
import '../models/user_profile_model.dart';

const _primary = Color(0xFF6366F1);

String _initial(String? name) {
  if (name == null || name.isEmpty) return '?';
  return name.substring(0, 1).toUpperCase();
}

const _coverPalette = [
  (bg: Color(0xFFEEF2FF), icon: Icons.bar_chart, fg: Color(0xFF6366F1)),
  (bg: Color(0xFFECFDF5), icon: Icons.functions, fg: Color(0xFF16A34A)),
  (bg: Color(0xFFFFF7ED), icon: Icons.psychology, fg: Color(0xFFD97706)),
  (bg: Color(0xFFFDF2F8), icon: Icons.code, fg: Color(0xFFDB2777)),
  (bg: Color(0xFFEFF6FF), icon: Icons.table_chart, fg: Color(0xFF2563EB)),
];

class UserProfileScreen extends ConsumerStatefulWidget {
  final String identifier; // username 或 handle
  // 作为底部导航"我的" tab 用时是根级页面，没有可以返回的上一页
  final bool showBackButton;
  const UserProfileScreen({
    super.key,
    required this.identifier,
    this.showBackButton = true,
  });

  @override
  ConsumerState<UserProfileScreen> createState() => _UserProfileScreenState();
}

class _UserProfileScreenState extends ConsumerState<UserProfileScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabCtrl;
  UserProfile? _profile;
  List<TutorialModel> _tutorials = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 3, vsync: this);
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    final api = ref.read(apiClientProvider);

    final profileRes = await api.get('/auth/users/profile/${widget.identifier}');
    if (!profileRes.success || profileRes.data == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    final profile = UserProfile.fromJson(profileRes.data as Map<String, dynamic>);

    // 检查是否已关注
    final currentUserId = ref.read(currentUserProvider)?.id;
    if (currentUserId != null && currentUserId != profile.id) {
      final followRes = await api.get('/auth/users/${profile.id}/follow-status');
      if (followRes.success && followRes.data != null) {
        profile.isFollowing = followRes.data['isFollowing'] == true;
      }
    }

    // 获取用户教程
    var tuts = <TutorialModel>[];
    final tutRes = await api.get(
      '/auth/tutorials',
      queryParameters: {'author': profile.username, 'status': 'published'},
    );
    if (tutRes.success && tutRes.data != null) {
      final rawList = (tutRes.data['tutorials'] as List?) ?? [];
      tuts = rawList
          .map((j) => TutorialModel.fromJson(j as Map<String, dynamic>))
          .toList();
    }

    if (!mounted) return;
    setState(() {
      _profile = profile;
      _tutorials = tuts;
      _loading = false;
    });
  }

  Future<void> _toggleFollow() async {
    if (_profile == null) return;
    final api = ref.read(apiClientProvider);
    final res = _profile!.isFollowing
        ? await api.delete('/auth/users/${_profile!.id}/follow')
        : await api.post('/auth/users/${_profile!.id}/follow');

    if (!res.success) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('操作失败：${res.message}')));
      return;
    }
    setState(() {
      if (_profile!.isFollowing) {
        _profile!.isFollowing = false;
        _profile!.followerCount--;
      } else {
        _profile!.isFollowing = true;
        _profile!.followerCount++;
      }
    });
  }

  Future<void> _startChat() async {
    if (_profile == null) return;
    final api = ref.read(apiClientProvider);

    // 查找现有会话
    final res = await api.get('/auth/conversations');
    if (res.success && res.data != null) {
      final convs = (res.data['conversations'] as List?) ?? [];
      final existing = convs.cast<Map<String, dynamic>?>().firstWhere(
            (c) => c?['other_user_id']?.toString() == _profile!.id,
            orElse: () => null,
          );
      if (existing != null) {
        if (!mounted) return;
        context.push('/messages/chat/${existing['id']}');
        return;
      }
    }

    // 没有现成会话，发一条消息创建新会话
    final msgRes = await api.post('/auth/messages', data: {
      'toUserId': _profile!.id,
      'content': '你好！',
      'type': 'text',
    });
    if (!msgRes.success || msgRes.data == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('发送失败：${msgRes.message}')));
      return;
    }
    if (!mounted) return;
    context.push('/messages/chat/${msgRes.data['conversationId']}');
  }

  Widget _buildAvatar({double radius = 36}) {
    final p = _profile;
    if (p?.avatar != null && p!.avatar!.isNotEmpty) {
      if (p.avatar!.startsWith('data:image')) {
        final base64Data = p.avatar!.split(',').last;
        try {
          return CircleAvatar(
            radius: radius,
            backgroundImage: MemoryImage(base64Decode(base64Data)),
          );
        } catch (_) {
          // 解码失败落到下面的首字母占位
        }
      } else {
        return CircleAvatar(
          radius: radius,
          backgroundImage: CachedNetworkImageProvider(p.avatar!),
        );
      }
    }
    return CircleAvatar(
      radius: radius,
      backgroundColor: _primary,
      child: Text(
        _initial(_profile?.username),
        style: TextStyle(fontSize: radius * 0.6, color: Colors.white, fontWeight: FontWeight.w700),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final currentUserId = ref.watch(currentUserProvider)?.id;
    final isMe = currentUserId != null && currentUserId == _profile?.id;

    return Scaffold(
      backgroundColor: const Color(0xFFF8F8F8),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _profile == null
              ? const Center(child: Text('用户不存在'))
              : NestedScrollView(
                  headerSliverBuilder: (ctx, _) => [
                    SliverToBoxAdapter(
                      child: Column(
                        children: [
                          // 封面+头像
                          Stack(
                            clipBehavior: Clip.none,
                            children: [
                              Container(height: 120, color: const Color(0xFFEEF0FF), width: double.infinity),
                              if (widget.showBackButton)
                                Positioned(
                                  top: 8,
                                  left: 8,
                                  child: SafeArea(
                                    child: IconButton(
                                      icon: const Icon(Icons.arrow_back_ios, color: Colors.black54),
                                      onPressed: () => context.pop(),
                                    ),
                                  ),
                                ),
                              Positioned(bottom: -36, left: 16, child: _buildAvatar(radius: 36)),
                            ],
                          ),
                          const SizedBox(height: 44),

                          // 操作按钮行
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            child: Row(
                              children: [
                                const Spacer(),
                                if (!isMe) ...[
                                  OutlinedButton.icon(
                                    onPressed: _startChat,
                                    icon: const Icon(Icons.message_outlined, size: 16),
                                    label: const Text('发消息'),
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor: _primary,
                                      side: const BorderSide(color: _primary),
                                      shape:
                                          RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  ElevatedButton(
                                    onPressed: _toggleFollow,
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor:
                                          _profile!.isFollowing ? Colors.grey[200] : _primary,
                                      foregroundColor:
                                          _profile!.isFollowing ? Colors.black87 : Colors.white,
                                      elevation: 0,
                                      shape:
                                          RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                                    ),
                                    child: Text(_profile!.isFollowing ? '已关注' : '关注'),
                                  ),
                                ] else
                                  OutlinedButton.icon(
                                    onPressed: () {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        const SnackBar(content: Text('编辑资料即将上线，敬请期待')),
                                      );
                                    },
                                    icon: const Icon(Icons.edit, size: 16),
                                    label: const Text('编辑资料'),
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor: Colors.black87,
                                      side: BorderSide(color: Colors.grey.shade300),
                                      shape:
                                          RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 12),

                          // 用户信息
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(_profile!.username,
                                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                                if (_profile!.handle != null)
                                  Text('@${_profile!.handle}',
                                      style: const TextStyle(fontSize: 14, color: Colors.grey)),
                                if (_profile!.bio?.isNotEmpty == true) ...[
                                  const SizedBox(height: 6),
                                  Text(_profile!.bio!, style: const TextStyle(fontSize: 14, height: 1.5)),
                                ],
                                if (_profile!.website?.isNotEmpty == true) ...[
                                  const SizedBox(height: 4),
                                  Row(
                                    children: [
                                      const Icon(Icons.link, size: 14, color: _primary),
                                      const SizedBox(width: 4),
                                      Text(
                                        _profile!.website!
                                            .replaceAll('https://', '')
                                            .replaceAll('http://', ''),
                                        style: const TextStyle(fontSize: 13, color: _primary),
                                      ),
                                    ],
                                  ),
                                ],
                              ],
                            ),
                          ),
                          const SizedBox(height: 14),

                          // 统计数据
                          Container(
                            color: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            child: Row(
                              children: [
                                _statItem('${_profile!.tutorialCount}', '教程'),
                                _divider(),
                                _statItem(_formatCount(_profile!.followerCount), '粉丝',
                                    onTap: () => context.push('/users/${_profile!.id}/followers')),
                                _divider(),
                                _statItem(_formatCount(_profile!.followingCount), '关注',
                                    onTap: () => context.push('/users/${_profile!.id}/following')),
                              ],
                            ),
                          ),

                          // Tabs
                          Container(
                            color: Colors.white,
                            child: TabBar(
                              controller: _tabCtrl,
                              labelColor: _primary,
                              unselectedLabelColor: Colors.grey,
                              indicatorColor: _primary,
                              indicatorWeight: 2,
                              tabs: const [
                                Tab(icon: Icon(Icons.grid_view, size: 20)),
                                Tab(icon: Icon(Icons.bookmark_outline, size: 20)),
                                Tab(icon: Icon(Icons.favorite_outline, size: 20)),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  body: TabBarView(
                    controller: _tabCtrl,
                    children: [
                      // 教程九宫格
                      _tutorials.isEmpty
                          ? const Center(
                              child: Text('还没有发布的教程', style: TextStyle(color: Colors.grey)))
                          : GridView.builder(
                              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: 2,
                                crossAxisSpacing: 2,
                                mainAxisSpacing: 2,
                                childAspectRatio: 3 / 4,
                              ),
                              itemCount: _tutorials.length,
                              itemBuilder: (ctx, i) {
                                final t = _tutorials[i];
                                return _TutorialGridItem(
                                  tutorial: t,
                                  onTap: () {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(content: Text('教程详情页即将上线')),
                                    );
                                  },
                                );
                              },
                            ),
                      // 收藏（占位）
                      const Center(child: Text('收藏功能即将上线', style: TextStyle(color: Colors.grey))),
                      // 点赞（占位）
                      const Center(child: Text('点赞列表即将上线', style: TextStyle(color: Colors.grey))),
                    ],
                  ),
                ),
    );
  }

  Widget _statItem(String value, String label, {VoidCallback? onTap}) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Column(
          children: [
            Text(value, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
            const SizedBox(height: 2),
            Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
          ],
        ),
      ),
    );
  }

  Widget _divider() => Container(width: 0.5, height: 32, color: Colors.grey.shade200);

  String _formatCount(int n) {
    if (n >= 10000) return '${(n / 10000).toStringAsFixed(1)}万';
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}k';
    return '$n';
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }
}

// 教程九宫格 item
class _TutorialGridItem extends StatelessWidget {
  final TutorialModel tutorial;
  final VoidCallback onTap;

  const _TutorialGridItem({required this.tutorial, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final entry = _coverPalette[
        tutorial.title.isNotEmpty ? tutorial.title.codeUnitAt(0) % _coverPalette.length : 0];

    return GestureDetector(
      onTap: onTap,
      child: Stack(
        fit: StackFit.expand,
        children: [
          tutorial.coverImage?.isNotEmpty == true
              ? CachedNetworkImage(
                  imageUrl: tutorial.coverImage!,
                  fit: BoxFit.cover,
                  placeholder: (context, url) => Container(color: entry.bg),
                  errorWidget: (context, url, error) =>
                      Container(color: entry.bg, child: Icon(entry.icon, size: 40, color: entry.fg)),
                )
              : Container(color: entry.bg, child: Icon(entry.icon, size: 40, color: entry.fg)),

          // 底部渐变信息
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: [Colors.black54, Colors.transparent],
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(tutorial.title,
                      style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w500),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      const Icon(Icons.favorite, size: 11, color: Colors.white70),
                      const SizedBox(width: 2),
                      Text('${tutorial.likes}', style: const TextStyle(color: Colors.white70, fontSize: 11)),
                      const SizedBox(width: 8),
                      const Icon(Icons.visibility, size: 11, color: Colors.white70),
                      const SizedBox(width: 2),
                      Text('${tutorial.views}', style: const TextStyle(color: Colors.white70, fontSize: 11)),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
