import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';
import '../../../l10n/generated/app_localizations.dart';

// 这个占位屏是 2026-07 之前"问问小梦"唯一的落地页——真实的对话功能已经
// 搬到 lib/features/ai/（欢迎页/对话页/历史页都是真实接口）。这个文件
// 现在没有任何路由/按钮指向它了，保留只是为了不留死掉的 Aria 命名
class XiaomengPlaceholderScreen extends StatelessWidget {
  const XiaomengPlaceholderScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(title: const Text('小梦')),
      body: Center(
        child: Text(
          l10n.pageUnderDevelopment('小梦'),
          style: const TextStyle(color: AppColors.textMuted),
        ),
      ),
    );
  }
}
