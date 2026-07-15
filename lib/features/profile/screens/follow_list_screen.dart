import 'dart:convert';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/api_response.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../models/user_profile_model.dart';

String _initial(String? name) {
  if (name == null || name.isEmpty) return '?';
  return name.substring(0, 1).toUpperCase();
}

// 跟全项目其它头像渲染的地方保持一致：data:image 是旧的 base64 头像，
// 否则是 COS 图片 URL
Widget _buildAvatar(String? avatar, String username) {
  if (avatar != null && avatar.isNotEmpty) {
    if (avatar.startsWith('data:image')) {
      try {
        return CircleAvatar(
          backgroundImage: MemoryImage(base64Decode(avatar.split(',').last)),
        );
      } catch (_) {
        // 解码失败落到下面的首字母占位
      }
    } else {
      return CircleAvatar(backgroundImage: CachedNetworkImageProvider(avatar));
    }
  }
  return CircleAvatar(
    backgroundColor: const Color(0xFF6366F1),
    child: Text(
      _initial(username),
      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
    ),
  );
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
    final l10n = AppLocalizations.of(context)!;
    final title = widget.type == 'followers' ? l10n.followersCountLabel : l10n.followingCountLabel;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    // AppBar 之前固定白底+黑字，跟下面 body（走主题默认背景）不是同一个值，
    // 两者拼在一起会露出一条接缝，深色模式下黑字更是直接看不见——统一改成
    // 跟首页/极索/创作者中心同款的米白 #FAFAF8（深色跟主题），AppBar/body
    // 用同一个值，前景色也跟主题走
    final bg = isDark ? Theme.of(context).scaffoldBackgroundColor : const Color(0xFFFAFAF8);
    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        title: Text(title),
        backgroundColor: bg,
        foregroundColor: Theme.of(context).textTheme.bodyLarge?.color,
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
              child: Text(
                l10n.loadFailedWithReason(res.message ?? ''),
                style: const TextStyle(color: Colors.grey),
              ),
            );
          }
          final key = widget.type == 'followers' ? 'followers' : 'following';
          final rawList = (res.data[key] as List?) ?? [];
          final users =
              rawList.map((j) => UserProfile.fromJson(j as Map<String, dynamic>)).toList();

          if (users.isEmpty) {
            return Center(
              child: Text(
                widget.type == 'followers' ? l10n.noFollowersYet : l10n.noFollowingYet,
                style: const TextStyle(color: Colors.grey),
              ),
            );
          }

          return ListView.builder(
            itemCount: users.length,
            itemBuilder: (ctx, i) {
              final u = users[i];
              return ListTile(
                leading: _buildAvatar(u.avatar, u.username),
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
