import 'dart:convert';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../auth_service.dart';

const _primary = Color(0xFF6366F1);

class SwitchAccountScreen extends ConsumerStatefulWidget {
  const SwitchAccountScreen({super.key});

  @override
  ConsumerState<SwitchAccountScreen> createState() => _SwitchAccountScreenState();
}

class _SwitchAccountScreenState extends ConsumerState<SwitchAccountScreen> {
  List<Map<String, dynamic>> _accounts = [];
  bool _loading = true;
  bool _managing = false;
  String? _switchingId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final accounts = await ref.read(authServiceProvider).getRecentAccounts();
    if (!mounted) return;
    setState(() {
      _accounts = accounts;
      _loading = false;
    });
  }

  Future<void> _switchTo(String userId) async {
    if (_switchingId != null) return;
    setState(() => _switchingId = userId);
    final ok = await ref.read(authServiceProvider).switchToAccount(userId);
    if (!mounted) return;
    if (ok) {
      // 换账号之后首页/我的等 tab 的页面实例都还是旧账号加载出来的数据，
      // 走 /splash 重新过一遍启动流程，让整个底部导航 shell 重新搭建，
      // 而不是指望每个页面自己去监听 currentUserProvider 变化刷新
      context.go('/splash');
      return;
    }
    setState(() {
      _switchingId = null;
      _accounts.removeWhere((e) => e['id'] == userId);
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('登录状态已过期，请重新登录')),
    );
  }

  Future<void> _remove(String userId) async {
    await ref.read(authServiceProvider).removeRecentAccount(userId);
    if (!mounted) return;
    setState(() => _accounts.removeWhere((e) => e['id'] == userId));
  }

  @override
  Widget build(BuildContext context) {
    final currentUserId = ref.watch(currentUserProvider)?.id;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back_ios),
                    onPressed: () => context.pop(),
                  ),
                  Expanded(
                    child: Text(
                      '切换账号',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                        color: Theme.of(context).textTheme.bodyLarge?.color,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: _accounts.length <= 1
                        ? null
                        : () => setState(() => _managing = !_managing),
                    child: Text(
                      _managing ? '完成' : '管理',
                      style: TextStyle(
                        fontSize: 15,
                        color: _accounts.length <= 1 ? Colors.grey : _primary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (_loading)
              const Expanded(child: Center(child: CircularProgressIndicator()))
            else
              Expanded(
                child: ListView(
                  children: [
                    ..._accounts.map(
                      (a) => _AccountRow(
                        id: a['id']?.toString() ?? '',
                        username: a['username']?.toString() ?? '',
                        avatar: a['avatar']?.toString(),
                        isCurrent: a['id']?.toString() == currentUserId,
                        managing: _managing,
                        switching: _switchingId == a['id']?.toString(),
                        onSwitch: () => _switchTo(a['id']?.toString() ?? ''),
                        onRemove: () => _remove(a['id']?.toString() ?? ''),
                      ),
                    ),
                    ListTile(
                      leading: Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Theme.of(context).inputDecorationTheme.fillColor,
                        ),
                        child: const Icon(Icons.add, color: _primary),
                      ),
                      title: const Text(
                        '添加其他账号',
                        style: TextStyle(fontWeight: FontWeight.w500),
                      ),
                      onTap: () => context.push('/login'),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
                      child: Text(
                        '支持至多3个账号切换',
                        style: TextStyle(
                          fontSize: 12,
                          color: Theme.of(context).textTheme.bodySmall?.color,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _AccountRow extends StatelessWidget {
  final String id;
  final String username;
  final String? avatar;
  final bool isCurrent;
  final bool managing;
  final bool switching;
  final VoidCallback onSwitch;
  final VoidCallback onRemove;

  const _AccountRow({
    required this.id,
    required this.username,
    required this.avatar,
    required this.isCurrent,
    required this.managing,
    required this.switching,
    required this.onSwitch,
    required this.onRemove,
  });

  Widget _buildAvatar() {
    if (avatar != null && avatar!.isNotEmpty) {
      if (avatar!.startsWith('data:image')) {
        try {
          final base64Data = avatar!.split(',').last;
          return CircleAvatar(
            radius: 22,
            backgroundImage: MemoryImage(base64Decode(base64Data)),
          );
        } catch (_) {
          // 解码失败落到下面的首字母占位
        }
      } else {
        return CircleAvatar(
          radius: 22,
          backgroundImage: CachedNetworkImageProvider(avatar!),
        );
      }
    }
    return CircleAvatar(
      radius: 22,
      backgroundColor: _primary,
      child: Text(
        (username.isNotEmpty ? username[0] : '?').toUpperCase(),
        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: _buildAvatar(),
      title: Text(
        username,
        style: TextStyle(
          fontWeight: FontWeight.w600,
          color: Theme.of(context).textTheme.bodyLarge?.color,
        ),
      ),
      trailing: managing
          ? (isCurrent
                ? null
                : GestureDetector(
                    onTap: onRemove,
                    child: const Icon(Icons.remove_circle_outline, color: Colors.red),
                  ))
          : isCurrent
          ? Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFFFEF2F2),
                borderRadius: BorderRadius.circular(99),
              ),
              child: const Text(
                '当前登录',
                style: TextStyle(fontSize: 12, color: Color(0xFFDC2626)),
              ),
            )
          : switching
          ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2, color: _primary),
            )
          : OutlinedButton(
              onPressed: onSwitch,
              style: OutlinedButton.styleFrom(
                foregroundColor: _primary,
                side: const BorderSide(color: _primary),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: const Text('切换到此账号'),
            ),
    );
  }
}
