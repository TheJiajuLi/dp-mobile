import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

// 群聊主页还没做（建群流程本身是这一批任务的范围，群聊页是下一步）——
// 群刚建好之后点"进入群聊"总得有个地方落地，先用这个占位页接住，
// 不让用户点完弹一个 SnackBar 就没反应了
class GroupChatPlaceholderScreen extends StatelessWidget {
  final String groupId;
  const GroupChatPlaceholderScreen({super.key, required this.groupId});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, size: 18),
          onPressed: () => context.go('/messages'),
        ),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: const BoxDecoration(
                  color: Color(0xFFEEF0FF),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.groups_outlined,
                  size: 30,
                  color: Color(0xFF6366F1),
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                '群聊页开发中',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              Text(
                '群已经建好了，群聊主页还在路上，敬请期待',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  color: Colors.grey[500],
                  height: 1.6,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
