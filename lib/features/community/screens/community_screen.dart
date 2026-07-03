import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';

class CommunityScreen extends StatelessWidget {
  const CommunityScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(title: const Text('社区')),
      body: const Center(
        child: Text('社区页面开发中', style: TextStyle(color: AppColors.textMuted)),
      ),
    );
  }
}
