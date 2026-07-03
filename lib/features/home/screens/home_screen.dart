import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_theme.dart';
import '../../auth/auth_service.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(title: Text(user?.username ?? '首页')),
      body: Center(
        child: Text(
          '欢迎，${user?.username ?? ''}',
          style: const TextStyle(color: AppColors.textPrimary, fontSize: 16),
        ),
      ),
    );
  }
}
