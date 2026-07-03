import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';

class AriaScreen extends StatelessWidget {
  const AriaScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(title: const Text('ARIA')),
      body: const Center(
        child: Text('ARIA 页面开发中', style: TextStyle(color: AppColors.textMuted)),
      ),
    );
  }
}
