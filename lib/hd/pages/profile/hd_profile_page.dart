import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../features/auth/auth_service.dart';
import '../../../features/profile/screens/user_profile_screen.dart';

// HD「我的」——直接复用手机端 UserProfileScreen（跟 HD 设置/Notebook 一样整块
// 嵌入手机页面），不再各维护一份假数据。identifier 用当前登录用户的 username；
// UserProfileScreen 内部按 currentUserProvider 判定 isOwnProfile 走"我的主页"渲染。
// 根级页面，不显示返回键
class HdProfilePage extends ConsumerWidget {
  const HdProfilePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);
    if (user == null) {
      return const Center(child: CircularProgressIndicator());
    }
    return UserProfileScreen(
      identifier: user.username,
      showBackButton: false,
    );
  }
}
