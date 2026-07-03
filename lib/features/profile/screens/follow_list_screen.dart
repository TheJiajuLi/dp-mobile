import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/api_response.dart';
import '../models/user_profile_model.dart';

String _initial(String? name) {
  if (name == null || name.isEmpty) return '?';
  return name.substring(0, 1).toUpperCase();
}

class FollowListScreen extends ConsumerStatefulWidget {
  final String userId;
  final String type; // 'followers' | 'following'

  const FollowListScreen({super.key, required this.userId, required this.type});

  @override
  ConsumerState<FollowListScreen> createState() => _FollowListScreenState();
}

class _FollowListScreenState extends ConsumerState<FollowListScreen> {
  late final Future<ApiResponse<dynamic>> _future;

  @override
  void initState() {
    super.initState();
    // 在 initState 里发起一次，不要放进 build()——放 build() 里 FutureBuilder
    // 每次重建都会拿到一个新 Future，导致列表反复回到 loading 状态
    _future = ref.read(apiClientProvider).get('/auth/users/${widget.userId}/${widget.type}');
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.type == 'followers' ? '粉丝' : '关注';
    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
      ),
      body: FutureBuilder<ApiResponse<dynamic>>(
        future: _future,
        builder: (ctx, snap) {
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final res = snap.data!;
          if (!res.success || res.data == null) {
            return Center(
              child: Text('加载失败：${res.message ?? ""}', style: const TextStyle(color: Colors.grey)),
            );
          }
          final key = widget.type == 'followers' ? 'followers' : 'following';
          final rawList = (res.data[key] as List?) ?? [];
          final users =
              rawList.map((j) => UserProfile.fromJson(j as Map<String, dynamic>)).toList();

          if (users.isEmpty) {
            return Center(
              child: Text(widget.type == 'followers' ? '暂无粉丝' : '暂无关注',
                  style: const TextStyle(color: Colors.grey)),
            );
          }

          return ListView.builder(
            itemCount: users.length,
            itemBuilder: (ctx, i) {
              final u = users[i];
              return ListTile(
                leading: CircleAvatar(
                  backgroundColor: const Color(0xFF6366F1),
                  child: Text(_initial(u.username),
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                ),
                title: Text(u.username, style: const TextStyle(fontWeight: FontWeight.w600)),
                subtitle: u.handle != null ? Text('@${u.handle}') : null,
                onTap: () => context.push('/users/${u.username}'),
              );
            },
          );
        },
      ),
    );
  }
}
