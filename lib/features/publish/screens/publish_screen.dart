import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';

class PublishScreen extends StatelessWidget {
  const PublishScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(title: const Text('发布')),
      body: const Center(
        child: Text('发布页面开发中', style: TextStyle(color: AppColors.textMuted)),
      ),
    );
  }
}
