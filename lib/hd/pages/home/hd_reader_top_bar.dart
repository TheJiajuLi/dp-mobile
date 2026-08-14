import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../features/community/providers/article_provider.dart';
import '../../../features/community/widgets/article_actions.dart';
import '../../../features/community/widgets/article_body_view.dart';
import '../../../shared/widgets/app_toast.dart';
import 'hd_toc_panel.dart';

const _primary = AppColors.primary;

// 中间阅读面板顶栏：标题 + 收藏/分享/PDF/更多。中窄屏(768-1024)额外露出「目录」
// 按钮，点开浮层显示目录（宽屏有独立右侧目录面板，不需要）
class HdReaderTopBar extends ConsumerWidget {
  final String tutorialId;
  final ArticleBodyController controller;
  final bool showTocButton;
  // 窄屏单栏模式下显示返回按钮（回到列表）；宽/中屏为 null 不显示
  final VoidCallback? onBack;
  const HdReaderTopBar({
    super.key,
    required this.tutorialId,
    required this.controller,
    this.showTocButton = false,
    this.onBack,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark
        ? Theme.of(context).scaffoldBackgroundColor
        : const Color(0xFFFAFAF8);
    final ink = isDark ? const Color(0xFFE6E6E6) : const Color(0xFF1A1A1A);
    final iconc = isDark ? const Color(0xFFB8BCCB) : const Color(0xFF555555);
    final divider = isDark
        ? Colors.white.withValues(alpha: 0.08)
        : const Color(0xFFE5E5EA);

    final state = ref.watch(articleProvider(tutorialId));
    final tutorial = state.tutorial;
    final title = tutorial?['title'] as String? ?? '';

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
        border: Border(bottom: BorderSide(color: divider, width: 0.5)),
      ),
      child: Row(
        children: [
          if (onBack != null) ...[
            _iconBtn(Icons.arrow_back_ios, iconc, '返回', onBack),
            const SizedBox(width: 2),
          ],
          if (showTocButton) ...[
            _iconBtn(Icons.list, iconc, '目录', () => _showTocSheet(context)),
            const SizedBox(width: 4),
          ],
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: ink,
              ),
            ),
          ),
          const SizedBox(width: 8),
          _iconBtn(
            state.saved ? Icons.bookmark : Icons.bookmark_border,
            state.saved ? _primary : iconc,
            '收藏',
            onSave,
          ),
          if (state.allowRepost) ...[
            _iconBtn(
              Icons.share_outlined,
              iconc,
              '分享',
              () => tutorial == null
                  ? null
                  : showArticleShareSheet(context, tutorial),
            ),
            _iconBtn(
              Icons.picture_as_pdf_outlined,
              iconc,
              '导出 PDF',
              () => tutorial == null
                  ? null
                  : openArticleExportSheet(
                      context,
                      ref,
                      tutorial,
                      state.blocks,
                    ),
            ),
          ],
          _iconBtn(
            Icons.more_horiz,
            iconc,
            '更多',
            () => showAppToast(context, '更多功能即将上线', ok: true),
          ),
        ],
      ),
    );
  }

  Widget _iconBtn(IconData icon, Color color, String tip, VoidCallback? onTap) {
    return Tooltip(
      message: tip,
      child: IconButton(
        icon: Icon(icon, size: 20, color: color),
        onPressed: onTap,
        splashRadius: 20,
        visualDensity: VisualDensity.compact,
      ),
    );
  }

  // 中窄屏目录浮层——复用 HdTocList，点条目跳转并关闭
  void _showTocSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final isDark = Theme.of(ctx).brightness == Brightness.dark;
        final ink = isDark ? const Color(0xFFE6E6E6) : const Color(0xFF1A1A1A);
        return Container(
          height: MediaQuery.of(ctx).size.height * 0.6,
          decoration: BoxDecoration(
            color: Theme.of(ctx).cardColor,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
          ),
          child: Column(
            children: [
              Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.grey[isDark ? 700 : 300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 2, 16, 8),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    '目录',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: ink,
                    ),
                  ),
                ),
              ),
              Expanded(
                child: HdTocList(
                  tutorialId: tutorialId,
                  controller: controller,
                  onItemTap: () => Navigator.pop(ctx),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
