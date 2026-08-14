import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../features/community/providers/article_provider.dart';
import '../../../features/community/widgets/article_actions.dart';
import '../../../shared/widgets/app_toast.dart';

const _primary = AppColors.primary;

// 中间阅读面板底栏：点赞/收藏/评论 + 小梦解读。点赞/收藏走 articleProvider
// notifier（真实）；评论阶段2 先占位（手机评论 sheet 深绑 State，抽取是后续
// 单独任务）；小梦解读占位 toast（阶段3 接 xmeng 流式）
class HdReaderBottomBar extends ConsumerWidget {
  final String tutorialId;
  const HdReaderBottomBar({super.key, required this.tutorialId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark
        ? Theme.of(context).scaffoldBackgroundColor
        : const Color(0xFFFAFAF8);
    final iconc = isDark ? const Color(0xFFB8BCCB) : const Color(0xFF888888);
    final divider = isDark
        ? Colors.white.withValues(alpha: 0.08)
        : const Color(0xFFE5E5EA);

    final state = ref.watch(articleProvider(tutorialId));
    final commentCount =
        (state.tutorial?['comment_count'] as num?)?.toInt() ?? 0;

    Future<void> onLike() async {
      final ok = await ref
          .read(articleProvider(tutorialId).notifier)
          .toggleLike();
      if (!ok && context.mounted) showAppToast(context, '操作失败，请重试');
    }

    Future<void> onSave() async {
      final ok = await ref
          .read(articleProvider(tutorialId).notifier)
          .toggleSave();
      if (!ok && context.mounted) showAppToast(context, '操作失败，请重试');
    }

    return Container(
      height: 52,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: bg,
        border: Border(top: BorderSide(color: divider, width: 0.5)),
      ),
      child: Row(
        children: [
          _action(
            state.liked ? Icons.favorite : Icons.favorite_border,
            state.liked ? const Color(0xFFEF4444) : iconc,
            '${state.likes}',
            onLike,
          ),
          const SizedBox(width: 20),
          _action(
            state.saved ? Icons.bookmark : Icons.bookmark_border,
            state.saved ? _primary : iconc,
            '${state.saveCount}',
            onSave,
          ),
          const SizedBox(width: 20),
          _action(
            Icons.chat_bubble_outline,
            iconc,
            '$commentCount',
            // 评论——手机评论 sheet 深绑 tutorial_detail_screen 的 State，
            // 抽成可复用是独立任务，阶段2 先占位
            () => showAppToast(context, '评论即将上线', ok: true),
          ),
          const Spacer(),
          GestureDetector(
            onTap: () => explainArticleWithXmeng(context),
            behavior: HitTestBehavior.opaque,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
              decoration: BoxDecoration(
                color: _primary.withValues(alpha: isDark ? 0.16 : 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.auto_awesome, size: 14, color: _primary),
                  SizedBox(width: 5),
                  Text(
                    '小梦解读',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: _primary,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _action(IconData icon, Color color, String label, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 20, color: color),
          const SizedBox(width: 5),
          Text(label, style: TextStyle(fontSize: 13, color: color)),
        ],
      ),
    );
  }
}
