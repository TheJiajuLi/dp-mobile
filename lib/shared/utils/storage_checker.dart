import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/network/api_client.dart';
import '../../l10n/generated/app_localizations.dart';

class StorageChecker {
  static Future<bool> checkAndPrompt(
    BuildContext context,
    WidgetRef ref, {
    int estimatedBytes = 0,
  }) async {
    // ApiClient.get 内部吞掉了 DioException，不会抛异常——失败与否要看
    // res.success，不能只靠 try/catch。检查失败就放行，不能因为查配额这一步
    // 网络抖动就把发送挡住
    final res = await ref.read(apiClientProvider).get('/auth/storage/usage');
    if (!res.success || res.data == null) return true;

    final data = res.data as Map<String, dynamic>;
    final total = (data['totalBytes'] as num?)?.toInt() ?? 0;
    final quota = (data['quota'] as num?)?.toInt() ?? 200 * 1024 * 1024;
    final used = total + estimatedBytes;
    final percent = used / quota;

    if (!context.mounted) return true;

    if (percent >= 1.0) {
      // 已满，显示升级或清理提示
      await _showFullDialog(context, total, quota);
      return false;
    }

    if (percent >= 0.5) {
      // 超过 50%，显示提醒，但不阻断
      _showWarningSnackbar(context, total, quota);
    }

    return true;
  }

  static String _fmt(int b) {
    if (b < 1024 * 1024) return '${(b / 1024).toStringAsFixed(1)}KB';
    return '${(b / 1024 / 1024).toStringAsFixed(1)}MB';
  }

  static Future<void> _showFullDialog(
    BuildContext context,
    int used,
    int quota,
  ) async {
    final l10n = AppLocalizations.of(context)!;
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.storageFull),
        content: Text(
          l10n.storageFullMessage(_fmt(used), _fmt(quota)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(l10n.cancel, style: const TextStyle(color: Colors.grey)),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              context.push('/settings/storage');
            },
            child: Text(l10n.manageStorage, style: const TextStyle(color: Color(0xFF6366F1))),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF6366F1)),
            onPressed: () {
              Navigator.pop(ctx);
              context.push('/settings/subscription');
            },
            child: Text(l10n.upgradeMembership, style: const TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  static void _showWarningSnackbar(BuildContext context, int used, int quota) {
    final l10n = AppLocalizations.of(context)!;
    final pct = (used / quota * 100).toInt();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(l10n.storageUsedPercentWarning(pct)),
        action: SnackBarAction(
          label: l10n.manage,
          onPressed: () => context.push('/settings/storage'),
        ),
      ),
    );
  }
}
